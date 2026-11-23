import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart' as std_crypto;
import 'models/download_task.dart';

typedef DownloadProgressCallback = void Function(DownloadTask updatedTask);

/// Downloader nativo em puro Dart utilizando HTTP Range Requests (RFC 7233).
/// Serve como mecanismo principal em dispositivos sem o binário aria2c (ex: Android)
/// ou como fallback transparente de alta performance.
///
/// Restrições:
/// - Exclusivamente HTTP/HTTPS.
/// - Bloqueia magnets e BitTorrent.
/// - Suporta download paralelo por segmentos de bytes, pausa, retomada e conferência SHA-256.
class DartSegmentedDownloader {
  final Map<String, bool> _pausedTasks = {};
  final Map<String, bool> _cancelledTasks = {};

  /// Inicia ou retoma o download de um arquivo direto HTTP/HTTPS.
  Future<DownloadTask> download({
    required DownloadTask task,
    int splitCount = 4,
    DownloadProgressCallback? onProgress,
  }) async {
    _validateHttpUrl(task.url);

    _pausedTasks[task.id] = false;
    _cancelledTasks[task.id] = false;

    var current = task.copyWith(status: DownloadStatus.starting);
    onProgress?.call(current);

    final client = HttpClient();
    try {
      final uri = Uri.parse(task.url);

      // 1. Consulta cabeçalhos para obter tamanho e verificar suporte a Range Requests
      final headReq = await client.headUrl(uri);
      final headRes = await headReq.close();

      int? contentLength;
      final clHeader = headRes.headers.value(HttpHeaders.contentLengthHeader);
      if (clHeader != null) {
        contentLength = int.tryParse(clHeader);
      }

      final acceptRanges = headRes.headers.value(HttpHeaders.acceptRangesHeader)?.toLowerCase() == 'bytes';
      final isRangeSupported = acceptRanges && (contentLength != null && contentLength > 1024 * 1024);

      current = current.copyWith(
        fileSizeBytes: contentLength,
        isRangeSupported: isRangeSupported,
        splitCount: isRangeSupported ? splitCount : 1,
        status: DownloadStatus.downloading,
      );
      onProgress?.call(current);

      final targetFile = File(task.destinationPath);
      if (!targetFile.parent.existsSync()) {
        targetFile.parent.createSync(recursive: true);
      }

      if (isRangeSupported) {
        current = await _downloadSegmented(
          client: client,
          uri: uri,
          targetFile: targetFile,
          contentLength: contentLength,
          splitCount: splitCount,
          task: current,
          onProgress: onProgress,
        );
      } else {
        current = await _downloadDirectStream(
          client: client,
          uri: uri,
          targetFile: targetFile,
          task: current,
          onProgress: onProgress,
        );
      }

      // Validação de integridade SHA-256 quando fornecida
      if (current.status == DownloadStatus.completed && task.sha256Expected != null) {
        final actualHash = await computeFileSha256(targetFile);
        final matches = actualHash.toLowerCase() == task.sha256Expected!.toLowerCase();
        if (!matches) {
          current = current.copyWith(
            status: DownloadStatus.failed,
            sha256Actual: actualHash,
            errorMessage: 'Falha de integridade: SHA-256 esperado ($task.sha256Expected) difere do obtido ($actualHash).',
          );
          onProgress?.call(current);
        } else {
          current = current.copyWith(sha256Actual: actualHash);
          onProgress?.call(current);
        }
      }

      return current;
    } catch (e) {
      current = current.copyWith(
        status: DownloadStatus.failed,
        errorMessage: 'Falha no download: $e',
      );
      onProgress?.call(current);
      return current;
    } finally {
      client.close(force: true);
    }
  }

  void pause(String taskId) {
    _pausedTasks[taskId] = true;
  }

  void cancel(String taskId) {
    _cancelledTasks[taskId] = true;
  }

  Future<DownloadTask> _downloadSegmented({
    required HttpClient client,
    required Uri uri,
    required File targetFile,
    required int contentLength,
    required int splitCount,
    required DownloadTask task,
    DownloadProgressCallback? onProgress,
  }) async {
    final chunkSize = (contentLength / splitCount).ceil();
    final segmentFiles = <File>[];
    final segmentProgress = List<int>.filled(splitCount, 0);

    var current = task;
    final stopwatch = Stopwatch()..start();
    var lastRecordedBytes = 0;

    final futures = <Future<void>>[];

    for (var i = 0; i < splitCount; i++) {
      final start = i * chunkSize;
      final end = (i == splitCount - 1) ? contentLength - 1 : (start + chunkSize - 1);
      final segFile = File('${targetFile.path}.part$i');
      segmentFiles.add(segFile);

      futures.add(() async {
        var existingBytes = 0;
        if (segFile.existsSync()) {
          existingBytes = segFile.lengthSync();
        }
        segmentProgress[i] = existingBytes;

        final actualStart = start + existingBytes;
        if (actualStart > end) return; // Este segmento já está completo

        final req = await client.getUrl(uri);
        req.headers.set('Range', 'bytes=$actualStart-$end');
        final res = await req.close();

        final sink = segFile.openWrite(mode: FileMode.append);
        try {
          await for (final chunk in res) {
            if (_cancelledTasks[task.id] == true) {
              await sink.close();
              throw Exception('Download cancelado pelo usuário');
            }
            if (_pausedTasks[task.id] == true) {
              await sink.close();
              return;
            }

            sink.add(chunk);
            segmentProgress[i] += chunk.length;

            final totalDown = segmentProgress.reduce((a, b) => a + b);
            final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
            final speed = elapsedSec > 0.5 ? ((totalDown - lastRecordedBytes) / 0.5).round() : 0;
            if (elapsedSec > 0.5) {
              lastRecordedBytes = totalDown;
              stopwatch.reset();
              stopwatch.start();
            }

            final remainingBytes = contentLength - totalDown;
            final eta = speed > 0 ? (remainingBytes / speed).ceil() : null;

            current = current.copyWith(
              downloadedBytes: totalDown,
              speedBytesPerSec: speed,
              etaSeconds: eta,
            );
            onProgress?.call(current);
          }
        } finally {
          await sink.flush();
          await sink.close();
        }
      }());
    }

    try {
      await Future.wait(futures);
    } catch (e) {
      if (_cancelledTasks[task.id] == true) {
        for (final f in segmentFiles) {
          if (f.existsSync()) f.deleteSync();
        }
        return current.copyWith(status: DownloadStatus.cancelled);
      }
      if (_pausedTasks[task.id] == true) {
        return current.copyWith(status: DownloadStatus.paused);
      }
      rethrow;
    }

    if (_pausedTasks[task.id] == true) {
      return current.copyWith(status: DownloadStatus.paused);
    }

    // Costura todos os segmentos no arquivo final
    final outSink = targetFile.openWrite();
    try {
      for (final segFile in segmentFiles) {
        if (segFile.existsSync()) {
          await outSink.addStream(segFile.openRead());
          segFile.deleteSync();
        }
      }
    } finally {
      await outSink.flush();
      await outSink.close();
    }

    return current.copyWith(
      downloadedBytes: contentLength,
      status: DownloadStatus.completed,
      completedAt: DateTime.now(),
      speedBytesPerSec: 0,
      etaSeconds: 0,
    );
  }

  Future<DownloadTask> _downloadDirectStream({
    required HttpClient client,
    required Uri uri,
    required File targetFile,
    required DownloadTask task,
    DownloadProgressCallback? onProgress,
  }) async {
    final req = await client.getUrl(uri);
    final res = await req.close();

    var current = task;
    var downloaded = 0;
    final stopwatch = Stopwatch()..start();
    var lastRecordedBytes = 0;

    final sink = targetFile.openWrite();
    try {
      await for (final chunk in res) {
        if (_cancelledTasks[task.id] == true) {
          await sink.close();
          if (targetFile.existsSync()) targetFile.deleteSync();
          return current.copyWith(status: DownloadStatus.cancelled);
        }
        if (_pausedTasks[task.id] == true) {
          await sink.close();
          return current.copyWith(status: DownloadStatus.paused);
        }

        sink.add(chunk);
        downloaded += chunk.length;

        final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
        final speed = elapsedSec > 0.5 ? ((downloaded - lastRecordedBytes) / 0.5).round() : 0;
        if (elapsedSec > 0.5) {
          lastRecordedBytes = downloaded;
          stopwatch.reset();
          stopwatch.start();
        }

        final eta = (task.fileSizeBytes != null && speed > 0)
            ? ((task.fileSizeBytes! - downloaded) / speed).ceil()
            : null;

        current = current.copyWith(
          downloadedBytes: downloaded,
          speedBytesPerSec: speed,
          etaSeconds: eta,
        );
        onProgress?.call(current);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    return current.copyWith(
      downloadedBytes: downloaded,
      status: DownloadStatus.completed,
      completedAt: DateTime.now(),
      speedBytesPerSec: 0,
      etaSeconds: 0,
    );
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
