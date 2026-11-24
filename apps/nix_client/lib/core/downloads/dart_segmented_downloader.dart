import 'dart:async';
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
  });

  int get totalExpected => endByte - startByte + 1;
  int get remainingBytes => totalExpected - writtenBytes;
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
  final Map<String, bool> _pausedTasks = {};
  final Map<String, bool> _cancelledTasks = {};
  final Map<String, int> _activeGenerations = {};
  final Map<String, List<HttpClientRequest>> _activeRequests = {};
  final Map<String, HttpClient> _activeClients = {};

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

  void _registerRequest(String taskId, HttpClientRequest request) {
    _activeRequests.putIfAbsent(taskId, () => []).add(request);
  }

  void _unregisterRequest(String taskId, HttpClientRequest request) {
    _activeRequests[taskId]?.remove(request);
  }

  /// Pausa imediatamente a transferência, abortando os sockets de rede ativos.
  void pause(String taskId) {
    _pausedTasks[taskId] = true;
    final reqs = _activeRequests[taskId];
    if (reqs != null && reqs.isNotEmpty) {
      for (final req in List<HttpClientRequest>.of(reqs)) {
        try {
          req.abort();
        } catch (_) {}
      }
    }
    final client = _activeClients[taskId];
    if (client != null) {
      try {
        client.close(force: true);
      } catch (_) {}
    }
  }

  /// Cancela a transferência, abortando requisições e limpando buffers.
  void cancel(String taskId) {
    _cancelledTasks[taskId] = true;
    final reqs = _activeRequests[taskId];
    if (reqs != null && reqs.isNotEmpty) {
      for (final req in List<HttpClientRequest>.of(reqs)) {
        try {
          req.abort();
        } catch (_) {}
      }
    }
    final client = _activeClients[taskId];
    if (client != null) {
      try {
        client.close(force: true);
      } catch (_) {}
    }
  }

  Future<DownloadTask> _executeDownload({
    required DownloadTask task,
    int splitCount = 8,
    DownloadProgressCallback? onProgress,
  }) async {
    _validateHttpUrl(task.url);

    // Geração única desta execução da tarefa para descartar callbacks obsoletos
    final gen = (_activeGenerations[task.id] ?? 0) + 1;
    _activeGenerations[task.id] = gen;

    // Reseta flags apenas se uma nova execução explícita foi solicitada
    _pausedTasks[task.id] = false;
    _cancelledTasks[task.id] = false;

    var current = task.copyWith(
      status: DownloadStatus.starting,
      downloadEngine: 'dart_range',
    );
    if (_activeGenerations[task.id] == gen) {
      onProgress?.call(current);
    }

    final client = HttpClient()
      ..maxConnectionsPerHost = 16
      ..connectionTimeout = const Duration(seconds: 25);
    _activeClients[task.id] = client;

    try {
      final uri = Uri.parse(task.url);

      // 1. Consulta cabeçalhos para obter tamanho, ETag, Last-Modified e verificar suporte a Range Requests
      final headReq = await client.headUrl(uri);
      _registerRequest(task.id, headReq);
      final headRes = await headReq.close();
      _unregisterRequest(task.id, headReq);

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

      // Se o ETag do arquivo remoto mudou em relação à sessão anterior, reseta segmentos locais
      if (task.lastEtag != null && etag != null && task.lastEtag != etag) {
        _wipeSegmentFiles(targetFile, 32);
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
            task: current,
            generation: gen,
            onProgress: onProgress,
          );
        } on RangeNotSupportedException {
          // Servidor indicou suportar Range mas retornou HTTP 200 no segmento:
          // chaveia transparentemente para fluxo direto sequencial sem duplicar dados
          isRangeSupported = false;
          _wipeSegmentFiles(targetFile, splitCount);
          current = await _downloadDirectStream(
            client: client,
            uri: uri,
            targetFile: targetFile,
            task: current.copyWith(isRangeSupported: false, splitCount: 1),
            generation: gen,
            onProgress: onProgress,
          );
        }
      } else {
        current = await _downloadDirectStream(
          client: client,
          uri: uri,
          targetFile: targetFile,
          task: current,
          generation: gen,
          onProgress: onProgress,
        );
      }

      // Validação de integridade SHA-256 quando fornecida
      if (current.status == DownloadStatus.completed && task.sha256Expected != null) {
        current = current.copyWith(status: DownloadStatus.finalizing);
        if (_activeGenerations[task.id] == gen) {
          onProgress?.call(current);
        }
        final actualHash = await computeFileSha256(targetFile);
        final matches = actualHash.toLowerCase() == task.sha256Expected!.toLowerCase();
        if (!matches) {
          current = current.copyWith(
            status: DownloadStatus.failed,
            sha256Actual: actualHash,
            errorMessage: 'Falha de integridade: SHA-256 esperado ($task.sha256Expected) difere do obtido ($actualHash).',
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
      if (_cancelledTasks[task.id] == true) {
        current = current.copyWith(
          status: DownloadStatus.cancelled,
          speedBytesPerSec: 0,
          clearEta: true,
        );
      } else if (_pausedTasks[task.id] == true) {
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
      _activeClients.remove(task.id);
      client.close(force: true);
    }
  }

  void _wipeSegmentFiles(File targetFile, int count) {
    for (var i = 0; i < count + 64; i++) {
      final f = File('${targetFile.path}.part$i');
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }

  Future<DownloadTask> _downloadSegmented({
    required HttpClient client,
    required Uri uri,
    required File targetFile,
    required int contentLength,
    required int splitCount,
    required DownloadTask task,
    required int generation,
    DownloadProgressCallback? onProgress,
  }) async {
    final chunkSize = (contentLength / splitCount).ceil();
    final slices = <_RangeSlice>[];
    final activeSliceIds = <int>{};

    for (var i = 0; i < splitCount; i++) {
      final start = i * chunkSize;
      final end = (i == splitCount - 1) ? contentLength - 1 : (start + chunkSize - 1);
      final segFile = File('${targetFile.path}.part$i');
      var existing = 0;
      if (segFile.existsSync()) {
        existing = segFile.lengthSync();
        final maxExpected = end - start + 1;
        if (existing > maxExpected) {
          final raf = segFile.openSync(mode: FileMode.writeOnlyAppend);
          raf.truncateSync(maxExpected);
          raf.closeSync();
          existing = maxExpected;
        }
      }
      slices.add(_RangeSlice(
        id: i,
        startByte: start,
        endByte: end,
        file: segFile,
        writtenBytes: existing,
      ));
    }

    var current = task;
    var lastRecordedBytes = slices.fold<int>(0, (sum, s) => sum + s.writtenBytes);
    var smoothedSpeed = 0.0;
    final totalDownStopwatch = Stopwatch()..start();
    var totalBytesTransferredThisSession = 0;

    // Timer suave para notificações da UI (a cada 350ms) usando média móvel exponencial (EMA)
    Timer? progressTimer;
    progressTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (_activeGenerations[task.id] != generation) return;

      final totalDown = slices.fold<int>(0, (sum, s) => sum + s.writtenBytes);
      final deltaBytes = totalDown - lastRecordedBytes;
      lastRecordedBytes = totalDown;

      if (deltaBytes > 0) {
        totalBytesTransferredThisSession += deltaBytes;
      }

      // Cálculo de velocidade instantânea (bytes / 0.35s)
      final instSpeed = (deltaBytes / 0.35).round();

      // Suavização EMA para evitar oscilações artificiais
      if (smoothedSpeed == 0) {
        smoothedSpeed = instSpeed.toDouble();
      } else if (instSpeed > 0) {
        smoothedSpeed = (0.28 * instSpeed) + (0.72 * smoothedSpeed);
      } else {
        smoothedSpeed = smoothedSpeed * 0.82;
        if (smoothedSpeed < 512) smoothedSpeed = 0;
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

      onProgress?.call(current);
    });

    Future<void> downloadSliceWorker(_RangeSlice slice) async {
      int retries = 0;
      const maxRetries = 3;

      while (true) {
        if (_pausedTasks[task.id] == true || _cancelledTasks[task.id] == true) {
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
          _registerRequest(task.id, req);
          req.headers.set('Range', 'bytes=$actualStart-${slice.endByte}');
          final res = await req.close();

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

          // Validação do cabeçalho Content-Range (RFC 7233)
          final contentRange = res.headers.value(HttpHeaders.contentRangeHeader);
          if (contentRange != null && contentRange.startsWith('bytes ')) {
            final spec = contentRange.substring(6);
            final dash = spec.indexOf('-');
            if (dash != -1) {
              final returnedStart = int.tryParse(spec.substring(0, dash));
              if (returnedStart != null && returnedStart != actualStart) {
                throw SegmentValidationException(
                  'Content-Range incoerente: esperado $actualStart mas retornado $returnedStart',
                );
              }
            }
          }

          raf = await slice.file.open(mode: FileMode.writeOnlyAppend);
          int bytesSinceFlush = 0;

          await for (final chunk in res.timeout(const Duration(seconds: 40))) {
            if (_cancelledTasks[task.id] == true || _pausedTasks[task.id] == true) {
              break;
            }
            raf.writeFromSync(chunk);
            slice.writtenBytes += chunk.length;
            bytesSinceFlush += chunk.length;

            // Backpressure: flush periódico a cada 2 MB para evitar acúmulo de memória na VM Dart
            if (bytesSinceFlush >= 2 * 1024 * 1024) {
              await raf.flush();
              bytesSinceFlush = 0;
            }
          }

          await raf.flush();
          await raf.close();
          raf = null;

          if (slice.writtenBytes >= slice.totalExpected) {
            slice.completed = true;
            return;
          } else {
            if (_pausedTasks[task.id] == true || _cancelledTasks[task.id] == true) {
              return;
            }
            throw HttpException('Segmento ${slice.id} incompleto: ${slice.writtenBytes} de ${slice.totalExpected} bytes');
          }
        } catch (e) {
          if (e is RangeNotSupportedException) {
            rethrow;
          }
          if (_cancelledTasks[task.id] == true || _pausedTasks[task.id] == true) {
            return;
          }
          retries++;
          if (retries >= maxRetries) {
            rethrow;
          }
          await Future.delayed(const Duration(milliseconds: 250));
        } finally {
          if (req != null) _unregisterRequest(task.id, req);
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
        if (_pausedTasks[task.id] == true || _cancelledTasks[task.id] == true) {
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

          // Só rouba se a fatia mais lenta tiver pelo menos 8 MB restantes
          if (slowestTarget != null && maxRemaining >= 8 * 1024 * 1024) {
            final currentPos = slowestTarget.startByte + slowestTarget.writtenBytes;
            final originalEnd = slowestTarget.endByte;
            final remaining = originalEnd - currentPos;
            if (remaining >= 8 * 1024 * 1024) {
              final half = remaining ~/ 2;
              final newTargetEnd = currentPos + half;
              final stolenStart = newTargetEnd + 1;

              slowestTarget.endByte = newTargetEnd;

              final stolenId = slices.length;
              final stolenFile = File('${targetFile.path}.part$stolenId');
              if (stolenFile.existsSync()) {
                try {
                  stolenFile.deleteSync();
                } catch (_) {}
              }

              final stolenSlice = _RangeSlice(
                id: stolenId,
                startByte: stolenStart,
                endByte: originalEnd,
                file: stolenFile,
                writtenBytes: 0,
              );

              slices.add(stolenSlice);
              activeSliceIds.add(stolenId);
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
      if (_cancelledTasks[task.id] == true) {
        _wipeSegmentFiles(targetFile, splitCount);
        return current.copyWith(
          status: DownloadStatus.cancelled,
          speedBytesPerSec: 0,
          clearEta: true,
        );
      }
      if (_pausedTasks[task.id] == true) {
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

    if (_pausedTasks[task.id] == true) {
      return current.copyWith(
        status: DownloadStatus.paused,
        speedBytesPerSec: 0,
        clearEta: true,
      );
    }
    if (_cancelledTasks[task.id] == true) {
      _wipeSegmentFiles(targetFile, splitCount);
      return current.copyWith(
        status: DownloadStatus.cancelled,
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

    // Ordena fatias pelo byte de início para garantir integridade sequencial
    slices.sort((a, b) => a.startByte.compareTo(b.startByte));

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
    required int generation,
    DownloadProgressCallback? onProgress,
  }) async {
    HttpClientRequest? req;
    try {
      req = await client.getUrl(uri);
      _registerRequest(task.id, req);
      final res = await req.close();

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
        if (_activeGenerations[task.id] != generation) return;

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
        onProgress?.call(current);
      });

      final raf = await targetFile.open(mode: FileMode.writeOnly);
      int bytesSinceFlush = 0;
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 40))) {
          if (_cancelledTasks[task.id] == true) {
            await raf.close();
            if (targetFile.existsSync()) targetFile.deleteSync();
            return current.copyWith(status: DownloadStatus.cancelled, speedBytesPerSec: 0, clearEta: true);
          }
          if (_pausedTasks[task.id] == true) {
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
      if (req != null) _unregisterRequest(task.id, req);
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
