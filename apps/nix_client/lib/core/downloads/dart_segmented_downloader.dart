import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as std_crypto;
import '../security/fail_closed_http_overrides.dart';
import 'models/download_task.dart';

typedef DownloadProgressCallback = void Function(DownloadTask updatedTask);

class RangeNotSupportedException implements Exception {
  final String message;
  const RangeNotSupportedException(this.message);
  @override
  String toString() => 'RangeNotSupportedException: $message';
}

class SegmentValidationException implements Exception {
  final String message;
  const SegmentValidationException(this.message);
  @override
  String toString() => 'SegmentValidationException: $message';
}

class _RangeSlice {
  final int id;
  final int startByte;
  int endByte;
  int writtenBytes;
  final File file;
  bool completed = false;

  _RangeSlice({
    required this.id,
    required this.startByte,
    required this.endByte,
    required this.file,
    this.writtenBytes = 0,
    this.completed = false,
  });

  int get totalExpected => endByte - startByte + 1;
  int get remainingBytes => totalExpected - writtenBytes;
}

class _TaskRunState {
  final String taskId;
  final int generation;
  final HttpClient client;
  final List<HttpClientRequest> activeRequests = [];
  final Completer<void> _stopSignal = Completer<void>();
  final Completer<void> _doneCompleter = Completer<void>();
  bool isPaused = false;
  bool isCancelled = false;

  _TaskRunState({
    required this.taskId,
    required this.generation,
    required this.client,
  });

  Future<void> get stopSignal => _stopSignal.future;
  Future<void> get done => _doneCompleter.future;

  bool isStopped(Map<String, int> activeGenerations) =>
      isPaused || isCancelled || activeGenerations[taskId] != generation;

  void registerRequest(HttpClientRequest request) {
    activeRequests.add(request);
  }

  void unregisterRequest(HttpClientRequest request) {
    activeRequests.remove(request);
  }

  void abort({bool paused = false, bool cancelled = false}) {
    if (paused) isPaused = true;
    if (cancelled) isCancelled = true;
    if (!_stopSignal.isCompleted) {
      _stopSignal.complete();
    }
    for (final req in List<HttpClientRequest>.of(activeRequests)) {
      try {
        req.abort();
      } catch (_) {}
    }
    activeRequests.clear();
    try {
      client.close(force: true);
    } catch (_) {}
  }

  void markDone() {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
  }
}

/// Downloader nativo em puro Dart utilizando HTTP Range Requests (RFC 7233).
/// Serve como mecanismo principal em dispositivos sem o binário aria2c (ex: Android)
/// ou como fallback transparente de alta performance com cancelamento cooperativo real.
///
/// Restrições:
/// - Exclusivamente HTTP/HTTPS.
/// - Bloqueia magnets e BitTorrent.
/// - Suporta download paralelo por segmentos de bytes, pausa real imediata, retomada segura e conferência SHA-256.
class DartSegmentedDownloader {
  final Map<String, int> _activeGenerations = {};
  final Map<String, _TaskRunState> _activeRuns = {};

  /// Inicia ou retoma o download de um arquivo direto HTTP/HTTPS.
  Future<DownloadTask> download({
    required DownloadTask task,
    int splitCount = 8,
    DownloadProgressCallback? onProgress,
  }) async {
    if (task.allowClearnet) {
      return NixFailClosedHttpOverrides.runWithExplicitClearnetDownload(
        action: () => _executeDownload(task: task, splitCount: splitCount, onProgress: onProgress),
      );
    }
    return _executeDownload(task: task, splitCount: splitCount, onProgress: onProgress);
  }

  /// Pausa imediatamente a transferência da geração ativa, abortando os sockets de rede.
  void pause(String taskId) {
    _activeRuns[taskId]?.abort(paused: true);
  }

  /// Cancela a transferência da geração ativa, abortando requisições e limpando buffers.
  void cancel(String taskId) {
    _activeRuns[taskId]?.abort(cancelled: true);
  }

  Future<DownloadTask> _executeDownload({
    required DownloadTask task,
    int splitCount = 8,
    DownloadProgressCallback? onProgress,
  }) async {
    _validateHttpUrl(task.url);

    final previousRun = _activeRuns[task.id];

    // Geração única desta execução da tarefa para encerrar workers antigos e descartar callbacks obsoletos
    final gen = (_activeGenerations[task.id] ?? 0) + 1;
    _activeGenerations[task.id] = gen;

    final client = HttpClient()
      ..maxConnectionsPerHost = 32
      ..connectionTimeout = const Duration(seconds: 25);
    final runState = _TaskRunState(
      taskId: task.id,
      generation: gen,
      client: client,
    );
    _activeRuns[task.id] = runState;

    var current = task.copyWith(
      status: DownloadStatus.starting,
      downloadEngine: 'dart_range',
    );

    try {
      // Caso uma execução anterior da mesma tarefa ainda esteja fechando arquivos após pausa rápida,
      // sinaliza parada imediata e aguarda seu encerramento antes de tocar nos segmentos em disco.
      if (previousRun != null) {
        previousRun.abort(paused: !previousRun.isCancelled);
        await previousRun.done;
      }

      if (runState.isCancelled) {
        current = current.copyWith(
          status: DownloadStatus.cancelled,
          speedBytesPerSec: 0,
          clearEta: true,
        );
        if (_activeGenerations[task.id] == gen) {
          onProgress?.call(current);
        }
        return current;
      }
      if (runState.isStopped(_activeGenerations)) {
        current = current.copyWith(
          status: DownloadStatus.paused,
          speedBytesPerSec: 0,
          clearEta: true,
        );
        if (_activeGenerations[task.id] == gen) {
          onProgress?.call(current);
        }
        return current;
      }

      if (_activeGenerations[task.id] == gen) {
        onProgress?.call(current);
      }

      final uri = Uri.parse(task.url);

      // 1. Consulta cabeçalhos para obter tamanho, ETag, Last-Modified e verificar suporte a Range Requests
      final headReq = await client.headUrl(uri);
      runState.registerRequest(headReq);
      final headRes = await headReq.close();
      runState.unregisterRequest(headReq);

      if (runState.isStopped(_activeGenerations)) {
        return _buildStoppedResult(current, runState, onProgress);
      }

      int? contentLength;
      final clHeader = headRes.headers.value(HttpHeaders.contentLengthHeader);
      if (clHeader != null) {
        contentLength = int.tryParse(clHeader);
      }

      final etag = headRes.headers.value(HttpHeaders.etagHeader);
      final lastModified = headRes.headers.value(HttpHeaders.lastModifiedHeader);

      final acceptRanges = headRes.headers.value(HttpHeaders.acceptRangesHeader)?.toLowerCase() == 'bytes';
      var isRangeSupported = acceptRanges && (contentLength != null && contentLength > 1024 * 1024);

      final targetFile = File(task.destinationPath);
      if (!targetFile.parent.existsSync()) {
        targetFile.parent.createSync(recursive: true);
      }

      // Se o ETag ou Last-Modified remoto mudou em relação à sessão anterior, descarta segmentos locais
      if ((task.lastEtag != null && etag != null && task.lastEtag != etag) ||
          (task.lastModified != null && lastModified != null && task.lastModified != lastModified)) {
        _wipeSegmentFiles(targetFile);
      }

      current = current.copyWith(
        fileSizeBytes: contentLength,
        isRangeSupported: isRangeSupported,
        splitCount: isRangeSupported ? splitCount : 1,
        activeSegments: isRangeSupported ? splitCount : 1,
        lastEtag: etag ?? task.lastEtag,
        lastModified: lastModified ?? task.lastModified,
        status: DownloadStatus.downloading,
      );

      if (_activeGenerations[task.id] == gen) {
        onProgress?.call(current);
      }

      if (isRangeSupported) {
        try {
          current = await _downloadSegmented(
            client: client,
            uri: uri,
            targetFile: targetFile,
            contentLength: contentLength,
            splitCount: splitCount,
            etag: etag ?? task.lastEtag,
            lastModified: lastModified ?? task.lastModified,
            task: current,
            runState: runState,
            onProgress: onProgress,
          );
        } on RangeNotSupportedException {
          // Servidor indicou suportar Range mas retornou HTTP 200 no segmento:
          // chaveia transparentemente para fluxo direto sequencial sem duplicar dados
          isRangeSupported = false;
          _wipeSegmentFiles(targetFile);
          current = await _downloadDirectStream(
            client: client,
            uri: uri,
            targetFile: targetFile,
            task: current.copyWith(isRangeSupported: false, splitCount: 1),
            runState: runState,
            onProgress: onProgress,
          );
        }
      } else {
        _wipeSegmentFiles(targetFile);
        current = await _downloadDirectStream(
          client: client,
          uri: uri,
          targetFile: targetFile,
          task: current,
          runState: runState,
          onProgress: onProgress,
        );
      }

      // Validação de integridade SHA-256 quando fornecida
      if (current.status == DownloadStatus.completed &&
          task.sha256Expected != null &&
          task.sha256Expected!.trim().isNotEmpty) {
        final expectedSha = task.sha256Expected!.trim();
        current = current.copyWith(status: DownloadStatus.finalizing);
        if (_activeGenerations[task.id] == gen) {
          onProgress?.call(current);
        }
        final actualHash = await computeFileSha256(targetFile);
        final matches = actualHash.toLowerCase() == expectedSha.toLowerCase();
        if (!matches) {
          current = current.copyWith(
            status: DownloadStatus.failed,
            sha256Actual: actualHash,
            errorMessage: 'Falha de integridade: SHA-256 esperado ($expectedSha) difere do obtido ($actualHash).',
          );
        } else {
          current = current.copyWith(
            status: DownloadStatus.completed,
            sha256Actual: actualHash,
          );
        }
        if (_activeGenerations[task.id] == gen) {
          onProgress?.call(current);
        }
      }

      return current;
    } catch (e) {
      if (runState.isCancelled) {
        _wipeSegmentFiles(File(task.destinationPath));
        current = current.copyWith(
          status: DownloadStatus.cancelled,
          speedBytesPerSec: 0,
          clearEta: true,
        );
      } else if (runState.isStopped(_activeGenerations)) {
        current = current.copyWith(
          status: DownloadStatus.paused,
          speedBytesPerSec: 0,
          clearEta: true,
        );
      } else {
        current = current.copyWith(
          status: DownloadStatus.failed,
          errorMessage: 'Falha no download: $e',
          speedBytesPerSec: 0,
          clearEta: true,
        );
      }
      if (_activeGenerations[task.id] == gen) {
        onProgress?.call(current);
      }
      return current;
    } finally {
      if (identical(_activeRuns[task.id], runState)) {
        _activeRuns.remove(task.id);
      }
      client.close(force: true);
      runState.markDone();
    }
  }

  DownloadTask _buildStoppedResult(
    DownloadTask current,
    _TaskRunState runState,
    DownloadProgressCallback? onProgress,
  ) {
    final stoppedStatus = runState.isCancelled
        ? DownloadStatus.cancelled
        : DownloadStatus.paused;
    final updated = current.copyWith(
      status: stoppedStatus,
      speedBytesPerSec: 0,
      clearEta: true,
    );
    if (_activeGenerations[runState.taskId] == runState.generation) {
      onProgress?.call(updated);
    }
    return updated;
  }

  static File _manifestFileFor(File targetFile) =>
      File('${targetFile.path}.parts.json');

  void _writeSegmentManifest({
    required File targetFile,
    required int totalSize,
    required int splitCount,
    required String? etag,
    required String? lastModified,
    required List<_RangeSlice> slices,
  }) {
    final manifestFile = _manifestFileFor(targetFile);
    final tmpFile = File('${manifestFile.path}.tmp');
    final ordered = List<_RangeSlice>.of(slices)
      ..sort((a, b) => a.startByte.compareTo(b.startByte));
    final payload = <String, dynamic>{
      'version': 1,
      'totalSize': totalSize,
      'splitCount': splitCount,
      if (etag != null) 'etag': etag,
      if (lastModified != null) 'lastModified': lastModified,
      'segments': ordered
          .map((s) => <String, int>{
                'id': s.id,
                'startByte': s.startByte,
                'endByte': s.endByte,
              })
          .toList(),
    };
    tmpFile.writeAsStringSync(jsonEncode(payload), flush: true);
    tmpFile.renameSync(manifestFile.path);
  }

  List<_RangeSlice>? _tryLoadCompatibleSlices({
    required File targetFile,
    required int contentLength,
    required int splitCount,
    required String? etag,
    required String? lastModified,
  }) {
    final manifestFile = _manifestFileFor(targetFile);
    if (!manifestFile.existsSync()) return null;

    try {
      final decoded = jsonDecode(manifestFile.readAsStringSync());
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['version'] != 1) return null;
      if (decoded['totalSize'] != contentLength) return null;
      if (decoded['splitCount'] != splitCount) return null;

      final savedEtag = decoded['etag'] as String?;
      if (savedEtag != null && etag != null && savedEtag != etag) {
        return null;
      }
      final savedLastModified = decoded['lastModified'] as String?;
      if (savedLastModified != null &&
          lastModified != null &&
          savedLastModified != lastModified) {
        return null;
      }

      final rawSegments = decoded['segments'];
      if (rawSegments is! List || rawSegments.isEmpty) return null;

      final parsed = <_RangeSlice>[];
      final usedIds = <int>{};
      for (final entry in rawSegments) {
        if (entry is! Map) return null;
        final id = entry['id'];
        final startByte = entry['startByte'];
        final endByte = entry['endByte'];
        if (id is! int || startByte is! int || endByte is! int) return null;
        if (id < 0 || startByte < 0 || endByte < startByte || !usedIds.add(id)) {
          return null;
        }
        final segFile = File('${targetFile.path}.part$id');
        var existing = 0;
        if (segFile.existsSync()) {
          existing = segFile.lengthSync();
          final maxExpected = endByte - startByte + 1;
          if (existing > maxExpected) {
            final raf = segFile.openSync(mode: FileMode.writeOnlyAppend);
            raf.truncateSync(maxExpected);
            raf.closeSync();
            existing = maxExpected;
          }
        }
        parsed.add(_RangeSlice(
          id: id,
          startByte: startByte,
          endByte: endByte,
          file: segFile,
          writtenBytes: existing,
          completed: existing == (endByte - startByte + 1),
        ));
      }

      final sorted = List<_RangeSlice>.of(parsed)
        ..sort((a, b) => a.startByte.compareTo(b.startByte));
      if (sorted.first.startByte != 0 || sorted.last.endByte != contentLength - 1) {
        return null;
      }
      for (var i = 1; i < sorted.length; i++) {
        if (sorted[i].startByte != sorted[i - 1].endByte + 1) {
          return null;
        }
      }

      // Remove eventuais partes órfãs fora do manifesto validado
      _deleteUnlistedPartFiles(targetFile, usedIds);
      return sorted;
    } catch (_) {
      return null;
    }
  }

  void _deleteUnlistedPartFiles(File targetFile, Set<int> validIds) {
    final parent = targetFile.parent;
    if (!parent.existsSync()) return;
    final baseName = targetFile.uri.pathSegments.isNotEmpty
        ? targetFile.uri.pathSegments.last
        : targetFile.path.split(Platform.pathSeparator).last;
    final partPattern = RegExp('^${RegExp.escape(baseName)}\\.part(\\d+)\$');
    try {
      for (final entity in parent.listSync(followLinks: false)) {
        final name = entity.path.split(Platform.pathSeparator).last;
        final match = partPattern.firstMatch(name);
        if (match != null) {
          final id = int.tryParse(match.group(1)!);
          if (id == null || !validIds.contains(id)) {
            try {
              entity.deleteSync();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  void _wipeSegmentFiles(File targetFile) {
    final manifestFile = _manifestFileFor(targetFile);
    for (final aux in [manifestFile, File('${manifestFile.path}.tmp')]) {
      if (aux.existsSync()) {
        try {
          aux.deleteSync();
        } catch (_) {}
      }
    }
    _deleteUnlistedPartFiles(targetFile, const <int>{});
  }

  Future<DownloadTask> _downloadSegmented({
    required HttpClient client,
    required Uri uri,
    required File targetFile,
    required int contentLength,
    required int splitCount,
    required String? etag,
    required String? lastModified,
    required DownloadTask task,
    required _TaskRunState runState,
    DownloadProgressCallback? onProgress,
  }) async {
    final generation = runState.generation;
    var restoredSlices = _tryLoadCompatibleSlices(
      targetFile: targetFile,
      contentLength: contentLength,
      splitCount: splitCount,
      etag: etag,
      lastModified: lastModified,
    );

    final List<_RangeSlice> slices;
    if (restoredSlices != null) {
      slices = restoredSlices;
    } else {
      // Descarta partes incompatíveis (sem manifesto, outro splitCount, tamanho/ETag divergente)
      _wipeSegmentFiles(targetFile);
      final chunkSize = (contentLength / splitCount).ceil();
      slices = <_RangeSlice>[];
      for (var i = 0; i < splitCount; i++) {
        final start = i * chunkSize;
        final end = (i == splitCount - 1) ? contentLength - 1 : (start + chunkSize - 1);
        final segFile = File('${targetFile.path}.part$i');
        slices.add(_RangeSlice(
          id: i,
          startByte: start,
          endByte: end,
          file: segFile,
          writtenBytes: 0,
        ));
      }
    }

    _writeSegmentManifest(
      targetFile: targetFile,
      totalSize: contentLength,
      splitCount: splitCount,
      etag: etag,
      lastModified: lastModified,
      slices: slices,
    );

    final activeSliceIds = <int>{};
    var current = task;
    var lastRecordedBytes = slices.fold<int>(0, (sum, s) => sum + s.writtenBytes);
    var smoothedSpeed = 0.0;
    final totalDownStopwatch = Stopwatch()..start();
    var totalBytesTransferredThisSession = 0;

    // Timer suave para notificações da UI (a cada 350ms) usando média móvel exponencial (EMA)
    Timer? progressTimer;
    progressTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (runState.isStopped(_activeGenerations)) return;

      final totalDown = slices.fold<int>(0, (sum, s) => sum + s.writtenBytes);
      final deltaBytes = totalDown - lastRecordedBytes;
      lastRecordedBytes = totalDown;

      if (deltaBytes > 0) {
        totalBytesTransferredThisSession += deltaBytes;
      }

      // Cálculo de velocidade instantânea (bytes / 0.35s)
      final instSpeed = (deltaBytes / 0.35).round();

      // Suavização EMA e amortecimento para evitar oscilações artificiais ou quedas abruptas
      if (smoothedSpeed == 0) {
        smoothedSpeed = instSpeed.toDouble();
      } else if (instSpeed > 0) {
        smoothedSpeed = (0.35 * instSpeed) + (0.65 * smoothedSpeed);
      } else {
        // Amortecimento gradual em jitter transitório de pacotes TCP
        smoothedSpeed = smoothedSpeed * 0.92;
        if (smoothedSpeed < 256) smoothedSpeed = 0;
      }

      final elapsedTotalSec = totalDownStopwatch.elapsedMilliseconds / 1000.0;
      final avgSpeed = elapsedTotalSec > 0.5 ? (totalBytesTransferredThisSession / elapsedTotalSec) : smoothedSpeed;

      final speedInt = smoothedSpeed.round();
      final remainingBytes = contentLength - totalDown;
      final eta = speedInt > 0 ? (remainingBytes / speedInt).ceil() : null;

      current = current.copyWith(
        downloadedBytes: totalDown,
        speedBytesPerSec: speedInt,
        averageSpeedBytesPerSec: avgSpeed,
        etaSeconds: eta,
        activeSegments: activeSliceIds.isNotEmpty ? activeSliceIds.length : splitCount,
        downloadEngine: 'dart_range',
      );

      if (_activeGenerations[task.id] == generation) {
        onProgress?.call(current);
      }
    });

    Future<void> downloadSliceWorker(_RangeSlice slice) async {
      int retries = 0;
      const maxRetries = 3;

      while (true) {
        if (runState.isStopped(_activeGenerations)) {
          return;
        }

        final actualStart = slice.startByte + slice.writtenBytes;
        if (actualStart > slice.endByte) {
          slice.completed = true;
          return;
        }

        HttpClientRequest? req;
        RandomAccessFile? raf;
        try {
          req = await client.getUrl(uri);
          runState.registerRequest(req);
          if (runState.isStopped(_activeGenerations)) {
            req.abort();
            return;
          }
          req.headers.set('Range', 'bytes=$actualStart-${slice.endByte}');
          final res = await req.close();

          if (runState.isStopped(_activeGenerations)) {
            return;
          }

          if (res.statusCode == HttpStatus.ok) {
            throw const RangeNotSupportedException(
              'Servidor retornou HTTP 200 OK em solicitação Range. Range Requests não são atendidos.',
            );
          }

          if (res.statusCode != HttpStatus.partialContent) {
            throw HttpException(
              'Status HTTP inesperado para o segmento (${slice.id} $actualStart-${slice.endByte}): ${res.statusCode}',
            );
          }

          // Validação rigorosa do cabeçalho Content-Range (RFC 7233)
          final contentRange = res.headers.value(HttpHeaders.contentRangeHeader);
          if (contentRange != null && contentRange.startsWith('bytes ')) {
            final spec = contentRange.substring(6).trim();
            final slash = spec.indexOf('/');
            final rangePart = slash != -1 ? spec.substring(0, slash) : spec;
            final dash = rangePart.indexOf('-');
            if (dash != -1) {
              final returnedStart = int.tryParse(rangePart.substring(0, dash));
              final returnedEnd = int.tryParse(rangePart.substring(dash + 1));
              if (returnedStart != null && returnedStart != actualStart) {
                throw SegmentValidationException(
                  'Content-Range incoerente: esperado início $actualStart mas recebido $returnedStart',
                );
              }
              if (returnedEnd != null && returnedEnd < actualStart) {
                throw SegmentValidationException(
                  'Content-Range incoerente: fim $returnedEnd é menor que início $actualStart',
                );
              }
            }
            if (slash != -1) {
              final returnedTotal = int.tryParse(spec.substring(slash + 1));
              if (returnedTotal != null && returnedTotal != contentLength) {
                throw SegmentValidationException(
                  'Content-Range total incoerente: esperado $contentLength mas retornado $returnedTotal',
                );
              }
            }
          }

          raf = await slice.file.open(mode: FileMode.writeOnlyAppend);
          int bytesSinceFlush = 0;

          await for (final chunk in res.timeout(const Duration(seconds: 40))) {
            if (runState.isStopped(_activeGenerations)) {
              break;
            }

            final remainingInSlice = slice.totalExpected - slice.writtenBytes;
            if (remainingInSlice <= 0) {
              break;
            }

            final bytesToWrite = chunk.length > remainingInSlice ? remainingInSlice : chunk.length;
            raf.writeFromSync(chunk.sublist(0, bytesToWrite));
            slice.writtenBytes += bytesToWrite;
            bytesSinceFlush += bytesToWrite;

            // Backpressure: flush periódico a cada 2 MB para evitar acúmulo de memória na VM Dart
            if (bytesSinceFlush >= 2 * 1024 * 1024) {
              await raf.flush();
              bytesSinceFlush = 0;
            }

            if (slice.writtenBytes >= slice.totalExpected) {
              break;
            }
          }

          await raf.flush();
          await raf.close();
          raf = null;

          if (slice.writtenBytes >= slice.totalExpected) {
            slice.completed = true;
            return;
          } else {
            if (runState.isStopped(_activeGenerations)) {
              return;
            }
            throw HttpException('Segmento ${slice.id} incompleto: ${slice.writtenBytes} de ${slice.totalExpected} bytes');
          }
        } catch (e) {
          if (e is RangeNotSupportedException) {
            rethrow;
          }
          if (runState.isStopped(_activeGenerations)) {
            return;
          }
          retries++;
          if (retries >= maxRetries) {
            rethrow;
          }
          await Future.any([
            Future<void>.delayed(const Duration(milliseconds: 250)),
            runState.stopSignal,
          ]);
        } finally {
          if (req != null) runState.unregisterRequest(req);
          if (raf != null) {
            try {
              await raf.flush();
              await raf.close();
            } catch (_) {}
          }
        }
      }
    }

    Future<void> runWorker(int workerIndex) async {
      while (true) {
        if (runState.isStopped(_activeGenerations)) {
          return;
        }

        _RangeSlice? assigned;

        // 1. Localiza fatia inicial pendente
        for (final s in slices) {
          if (!s.completed && !activeSliceIds.contains(s.id)) {
            assigned = s;
            activeSliceIds.add(s.id);
            break;
          }
        }

        // 2. Dynamic Work Stealing: se não há fatia livre, rouba metade do maior segmento lento
        if (assigned == null) {
          _RangeSlice? slowestTarget;
          int maxRemaining = 0;

          for (final s in slices) {
            if (!s.completed && activeSliceIds.contains(s.id)) {
              final rem = s.remainingBytes;
              if (rem > maxRemaining) {
                maxRemaining = rem;
                slowestTarget = s;
              }
            }
          }

          // Só rouba se a fatia mais lenta tiver pelo menos 2 MB restantes
          if (slowestTarget != null && maxRemaining >= 2 * 1024 * 1024) {
            final currentPos = slowestTarget.startByte + slowestTarget.writtenBytes;
            final originalEnd = slowestTarget.endByte;
            final remaining = originalEnd - currentPos;
            if (remaining >= 2 * 1024 * 1024) {
              final half = remaining ~/ 2;
              final newTargetEnd = currentPos + half;
              final stolenStart = newTargetEnd + 1;

              slowestTarget.endByte = newTargetEnd;

              final nextId = slices.fold<int>(-1, (m, s) => s.id > m ? s.id : m) + 1;
              final stolenFile = File('${targetFile.path}.part$nextId');
              if (stolenFile.existsSync()) {
                try {
                  stolenFile.deleteSync();
                } catch (_) {}
              }

              final stolenSlice = _RangeSlice(
                id: nextId,
                startByte: stolenStart,
                endByte: originalEnd,
                file: stolenFile,
                writtenBytes: 0,
              );

              slices.add(stolenSlice);
              _writeSegmentManifest(
                targetFile: targetFile,
                totalSize: contentLength,
                splitCount: splitCount,
                etag: etag,
                lastModified: lastModified,
                slices: slices,
              );
              activeSliceIds.add(nextId);
              assigned = stolenSlice;
            }
          }
        }

        if (assigned == null) {
          // Não há mais trabalho a ser feito por este worker
          return;
        }

        try {
          await downloadSliceWorker(assigned);
        } finally {
          activeSliceIds.remove(assigned.id);
        }
      }
    }

    final futures = List.generate(splitCount, (idx) => runWorker(idx));

    try {
      await Future.wait(futures);
    } catch (e) {
      progressTimer.cancel();
      if (e is RangeNotSupportedException) {
        rethrow;
      }
      if (runState.isCancelled) {
        _wipeSegmentFiles(targetFile);
        return current.copyWith(
          status: DownloadStatus.cancelled,
          speedBytesPerSec: 0,
          clearEta: true,
        );
      }
      if (runState.isStopped(_activeGenerations)) {
        return current.copyWith(
          status: DownloadStatus.paused,
          speedBytesPerSec: 0,
          clearEta: true,
        );
      }
      rethrow;
    } finally {
      progressTimer.cancel();
    }

    if (runState.isCancelled) {
      _wipeSegmentFiles(targetFile);
      return current.copyWith(
        status: DownloadStatus.cancelled,
        speedBytesPerSec: 0,
        clearEta: true,
      );
    }
    if (runState.isStopped(_activeGenerations)) {
      return current.copyWith(
        status: DownloadStatus.paused,
        speedBytesPerSec: 0,
        clearEta: true,
      );
    }

    // Transiciona para o estado FINALIZING antes de costurar os segmentos no disco
    current = current.copyWith(
      status: DownloadStatus.finalizing,
      downloadedBytes: contentLength,
      speedBytesPerSec: 0,
      clearEta: true,
    );
    if (_activeGenerations[task.id] == generation) {
      onProgress?.call(current);
    }

    // Ordena fatias pelo byte de início e valida cobertura contígua antes da costura
    slices.sort((a, b) => a.startByte.compareTo(b.startByte));
    for (var i = 0; i < slices.length; i++) {
      final s = slices[i];
      if (!s.file.existsSync() || s.file.lengthSync() != s.totalExpected) {
        throw SegmentValidationException(
          'Segmento ${s.id} inválido na costura final.',
        );
      }
      if (i == 0 && s.startByte != 0) {
        throw const SegmentValidationException('Início do primeiro segmento diverge de zero.');
      }
      if (i > 0 && s.startByte != slices[i - 1].endByte + 1) {
        throw SegmentValidationException(
          'Lacuna ou sobreposição detectada entre segmentos ${slices[i - 1].id} e ${s.id}.',
        );
      }
    }
    if (slices.isEmpty || slices.last.endByte != contentLength - 1) {
      throw const SegmentValidationException('Fim do último segmento diverge do tamanho total.');
    }

    // Costura todas as fatias no arquivo final usando RandomAccessFile para máxima eficiência
    final outRaf = await targetFile.open(mode: FileMode.writeOnly);
    try {
      for (final s in slices) {
        if (s.file.existsSync()) {
          final inRaf = await s.file.open(mode: FileMode.read);
          try {
            while (true) {
              final buf = inRaf.readSync(1024 * 1024); // Bloco de 1 MB
              if (buf.isEmpty) break;
              outRaf.writeFromSync(buf);
            }
          } finally {
            await inRaf.close();
            try {
              s.file.deleteSync();
            } catch (_) {}
          }
        }
      }
      await outRaf.flush();
    } finally {
      await outRaf.close();
    }
    _wipeSegmentFiles(targetFile);

    current = current.copyWith(
      downloadedBytes: contentLength,
      status: DownloadStatus.completed,
      completedAt: DateTime.now(),
      speedBytesPerSec: 0,
      clearEta: true,
    );
    if (_activeGenerations[task.id] == generation) {
      onProgress?.call(current);
    }
    return current;
  }

  Future<DownloadTask> _downloadDirectStream({
    required HttpClient client,
    required Uri uri,
    required File targetFile,
    required DownloadTask task,
    required _TaskRunState runState,
    DownloadProgressCallback? onProgress,
  }) async {
    final generation = runState.generation;
    HttpClientRequest? req;
    try {
      req = await client.getUrl(uri);
      runState.registerRequest(req);
      if (runState.isStopped(_activeGenerations)) {
        req.abort();
        return _buildStoppedResult(task, runState, onProgress);
      }
      final res = await req.close();
      if (runState.isStopped(_activeGenerations)) {
        return _buildStoppedResult(task, runState, onProgress);
      }

      if (res.statusCode != HttpStatus.ok && res.statusCode != HttpStatus.partialContent) {
        throw HttpException('Status HTTP inválido para download direto: ${res.statusCode}');
      }

      var current = task;
      var downloaded = 0;
      var lastRecordedBytes = 0;
      var smoothedSpeed = 0.0;
      final speedStopwatch = Stopwatch()..start();

      Timer? progressTimer;
      progressTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (runState.isStopped(_activeGenerations)) return;

        final elapsedSec = speedStopwatch.elapsedMilliseconds / 1000.0;
        if (elapsedSec >= 0.3) {
          final deltaBytes = downloaded - lastRecordedBytes;
          final instSpeed = deltaBytes > 0 ? (deltaBytes / elapsedSec).round() : 0;
          lastRecordedBytes = downloaded;
          speedStopwatch.reset();
          speedStopwatch.start();

          if (smoothedSpeed == 0) {
            smoothedSpeed = instSpeed.toDouble();
          } else if (instSpeed > 0) {
            smoothedSpeed = 0.3 * instSpeed + 0.7 * smoothedSpeed;
          } else {
            smoothedSpeed = smoothedSpeed * 0.85;
            if (smoothedSpeed < 512) smoothedSpeed = 0;
          }
        }

        final speedInt = smoothedSpeed.round();
        final eta = (task.fileSizeBytes != null && speedInt > 0)
            ? ((task.fileSizeBytes! - downloaded) / speedInt).ceil()
            : null;

        current = current.copyWith(
          downloadedBytes: downloaded,
          speedBytesPerSec: speedInt,
          etaSeconds: eta,
          downloadEngine: 'dart_stream',
        );
        if (_activeGenerations[task.id] == generation) {
          onProgress?.call(current);
        }
      });

      final raf = await targetFile.open(mode: FileMode.writeOnly);
      int bytesSinceFlush = 0;
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 40))) {
          if (runState.isCancelled) {
            await raf.close();
            if (targetFile.existsSync()) targetFile.deleteSync();
            return current.copyWith(status: DownloadStatus.cancelled, speedBytesPerSec: 0, clearEta: true);
          }
          if (runState.isStopped(_activeGenerations)) {
            await raf.flush();
            await raf.close();
            return current.copyWith(status: DownloadStatus.paused, speedBytesPerSec: 0, clearEta: true);
          }

          raf.writeFromSync(chunk);
          downloaded += chunk.length;
          bytesSinceFlush += chunk.length;

          // Backpressure a cada 2 MB
          if (bytesSinceFlush >= 2 * 1024 * 1024) {
            await raf.flush();
            bytesSinceFlush = 0;
          }
        }
        await raf.flush();
        await raf.close();
      } finally {
        progressTimer.cancel();
      }

      current = current.copyWith(
        downloadedBytes: downloaded,
        status: DownloadStatus.completed,
        completedAt: DateTime.now(),
        speedBytesPerSec: 0,
        clearEta: true,
      );
      if (_activeGenerations[task.id] == generation) {
        onProgress?.call(current);
      }
      return current;
    } finally {
      if (req != null) runState.unregisterRequest(req);
    }
  }

  static Future<String> computeFileSha256(File file) async {
    final digest = await std_crypto.sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  static void _validateHttpUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError(
        'Protocolo inválido: o Nix Downloads opera exclusivamente com HTTP e HTTPS. '
        'Transferências BitTorrent ou magnet links via Tor são terminantemente bloqueadas.',
      );
    }
  }
}
