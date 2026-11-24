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
    for (var i = 0; i < count; i++) {
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
    final segmentFiles = <File>[];
    final segmentProgress = List<int>.filled(splitCount, 0);

    var current = task;
    var lastRecordedBytes = 0;
    var smoothedSpeed = 0.0;
    final totalDownStopwatch = Stopwatch()..start();
    var totalBytesTransferredThisSession = 0;

    // Timer suave para notificações da UI (a cada 350ms) usando média móvel exponencial (EMA)
    Timer? progressTimer;
    progressTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (_activeGenerations[task.id] != generation) return;

      final totalDown = segmentProgress.reduce((a, b) => a + b);
      final deltaBytes = totalDown - lastRecordedBytes;
      lastRecordedBytes = totalDown;

      if (deltaBytes > 0) {
        totalBytesTransferredThisSession += deltaBytes;
      }

      // Cálculo de velocidade instantânea (bytes / 0.35s)
      final instSpeed = (deltaBytes / 0.35).round();

      // Suavização EMA para evitar oscilações artificiais para 0 KB/s
      if (smoothedSpeed == 0) {
        smoothedSpeed = instSpeed.toDouble();
      } else if (instSpeed > 0) {
        smoothedSpeed = (0.28 * instSpeed) + (0.72 * smoothedSpeed);
      } else {
        // Redução gradual
        smoothedSpeed = smoothedSpeed * 0.82;
        if (smoothedSpeed < 512) smoothedSpeed = 0;
      }

      final elapsedTotalSec = totalDownStopwatch.elapsedMilliseconds / 1000.0;
      final avgSpeed = elapsedTotalSec > 0.5 ? (totalBytesTransferredThisSession / elapsedTotalSec) : smoothedSpeed;

      final speedInt = smoothedSpeed.round();
      final remainingBytes = contentLength - totalDown;
      final eta = speedInt > 0 ? (remainingBytes / speedInt).ceil() : null;

      final activeSegmentsCount = segmentProgress.asMap().entries.where((e) {
        final i = e.key;
        final start = i * chunkSize;
        final end = (i == splitCount - 1) ? contentLength - 1 : (start + chunkSize - 1);
        final expected = end - start + 1;
        return e.value < expected;
      }).length;

      current = current.copyWith(
        downloadedBytes: totalDown,
        speedBytesPerSec: speedInt,
        averageSpeedBytesPerSec: avgSpeed,
        etaSeconds: eta,
        activeSegments: activeSegmentsCount,
        downloadEngine: 'dart_range',
      );

      onProgress?.call(current);
    });

    final futures = <Future<void>>[];

    for (var i = 0; i < splitCount; i++) {
      final start = i * chunkSize;
      final end = (i == splitCount - 1) ? contentLength - 1 : (start + chunkSize - 1);
      final expectedSegSize = (end - start + 1);
      final segFile = File('${targetFile.path}.part$i');
      segmentFiles.add(segFile);

      futures.add(() async {
        int retries = 0;
        const maxRetries = 3;

        while (true) {
          if (_pausedTasks[task.id] == true || _cancelledTasks[task.id] == true) {
            return;
          }

          var existingBytes = 0;
          if (segFile.existsSync()) {
            existingBytes = segFile.lengthSync();
            // Se o arquivo parcial existente for maior que o esperado, trunca para o tamanho exato
            if (existingBytes > expectedSegSize) {
              final raf = segFile.openSync(mode: FileMode.writeOnlyAppend);
              raf.truncateSync(expectedSegSize);
              raf.closeSync();
              existingBytes = expectedSegSize;
            }
          }
          segmentProgress[i] = existingBytes;

          if (existingBytes >= expectedSegSize) {
            return; // Segmento já concluído
          }

          final actualStart = start + existingBytes;
          if (actualStart > end) return;

          HttpClientRequest? req;
          IOSink? sink;
          try {
            req = await client.getUrl(uri);
            _registerRequest(task.id, req);
            req.headers.set('Range', 'bytes=$actualStart-$end');
            final res = await req.close();

            // Validação estrita de Range: se o servidor retornou 200 OK para um pedido parcial,
            // significa que Range não é atendido; dispara RangeNotSupportedException para chavear modo
            if (res.statusCode == HttpStatus.ok) {
              throw const RangeNotSupportedException(
                'Servidor retornou HTTP 200 OK em solicitação Range. Range Requests não são atendidos.',
              );
            }

            if (res.statusCode != HttpStatus.partialContent) {
              throw HttpException(
                'Status HTTP inesperado para o segmento ($actualStart-$end): ${res.statusCode}',
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
                    'Content-Range incoerente: esperado byte inicial $actualStart mas recebido $returnedStart',
                  );
                }
              }
            }

            sink = segFile.openWrite(mode: FileMode.append);
            await for (final chunk in res.timeout(const Duration(seconds: 40))) {
              if (_cancelledTasks[task.id] == true || _pausedTasks[task.id] == true) {
                break;
              }
              sink.add(chunk);
              segmentProgress[i] += chunk.length;
            }

            try {
              await sink.flush();
              await sink.close();
            } catch (_) {}
            sink = null;

            final finalSize = segFile.existsSync() ? segFile.lengthSync() : 0;
            if (finalSize >= expectedSegSize) {
              return; // Sucesso neste segmento
            } else {
              if (_pausedTasks[task.id] == true || _cancelledTasks[task.id] == true) {
                return;
              }
              throw HttpException('Segmento $i incompleto: obtido $finalSize de $expectedSegSize bytes');
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
            await Future.delayed(const Duration(milliseconds: 300));
          } finally {
            if (req != null) _unregisterRequest(task.id, req);
            if (sink != null) {
              try {
                await sink.flush();
                await sink.close();
              } catch (_) {}
            }
          }
        }
      }());
    }

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

    // Transiciona para o estado FINALIZING antes de iniciar a costura e o cálculo de hash
    current = current.copyWith(
      status: DownloadStatus.finalizing,
      downloadedBytes: contentLength,
      speedBytesPerSec: 0,
      clearEta: true,
    );
    if (_activeGenerations[task.id] == generation) {
      onProgress?.call(current);
    }

    // Costura todos os segmentos no arquivo final
    final outSink = targetFile.openWrite();
    try {
      for (final segFile in segmentFiles) {
        if (segFile.existsSync()) {
          await outSink.addStream(segFile.openRead());
          try {
            segFile.deleteSync();
          } catch (_) {}
        }
      }
    } finally {
      await outSink.flush();
      await outSink.close();
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
    IOSink? sink;
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

      sink = targetFile.openWrite();
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 40))) {
          if (_cancelledTasks[task.id] == true) {
            if (targetFile.existsSync()) targetFile.deleteSync();
            return current.copyWith(status: DownloadStatus.cancelled, speedBytesPerSec: 0, clearEta: true);
          }
          if (_pausedTasks[task.id] == true) {
            return current.copyWith(status: DownloadStatus.paused, speedBytesPerSec: 0, clearEta: true);
          }

          sink.add(chunk);
          downloaded += chunk.length;
        }
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
      if (sink != null) {
        try {
          await sink.flush();
          await sink.close();
        } catch (_) {}
      }
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
