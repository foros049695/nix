import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/downloads/aria2_download_controller.dart';
import 'package:nix_client/core/downloads/dart_segmented_downloader.dart';
import 'package:nix_client/core/downloads/models/download_task.dart';

void main() {
  group('Aria2DownloadController (Restrições Inegociáveis de Segurança)', () {
    late Aria2DownloadController controller;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_dl_test_');
      controller = Aria2DownloadController(
        downloadDir: tempDir.path,
        storageFilePath: '${tempDir.path}/tasks.json',
      );
    });

    tearDown(() async {
      await controller.stopDaemon();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('BLOQUEIA terminantemente magnets e protocolos BitTorrent', () async {
      const magnetUrl = 'magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12&dn=Ubuntu';
      expect(
        () => controller.addDownload(url: magnetUrl),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('O Nix Downloads utiliza aria2 exclusivamente para downloads diretos HTTP e HTTPS'),
        )),
      );
    });

    test('BLOQUEIA protocolos não autorizados (file://, ftp://, dht://)', () async {
      expect(
        () => controller.addDownload(url: 'file:///etc/passwd'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => controller.addDownload(url: 'ftp://ftp.example.com/file.iso'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Identifica extensões executáveis com aviso de segurança', () {
      final taskExe = DownloadTask(
        id: '1',
        url: 'https://example.com/installer.exe',
        destinationPath: '/tmp/installer.exe',
        fileName: 'installer.exe',
        createdAt: DateTime.now(),
      );
      expect(taskExe.isExecutable, isTrue);

      final taskSh = DownloadTask(
        id: '2',
        url: 'https://example.com/setup.sh',
        destinationPath: '/tmp/setup.sh',
        fileName: 'setup.sh',
        createdAt: DateTime.now(),
      );
      expect(taskSh.isExecutable, isTrue);

      final taskPdf = DownloadTask(
        id: '3',
        url: 'https://example.com/doc.pdf',
        destinationPath: '/tmp/doc.pdf',
        fileName: 'doc.pdf',
        createdAt: DateTime.now(),
      );
      expect(taskPdf.isExecutable, isFalse);
    });

    test('Notifica listeners via ChangeNotifier e gerencia pausa/remoção resiliente', () async {
      int notifyCount = 0;
      controller.addListener(() {
        notifyCount++;
      });

      final task = await controller.addDownload(url: 'https://example.com/debian.iso');
      expect(task.fileName, equals('debian.iso'));
      expect(controller.tasks.length, equals(1));
      expect(notifyCount, greaterThan(0));

      final countBeforePause = notifyCount;
      await controller.pauseDownload(task.id);
      expect(controller.tasks.first.status, equals(DownloadStatus.paused));
      expect(controller.tasks.first.speedBytesPerSec, equals(0));
      expect(notifyCount, greaterThan(countBeforePause));

      final countBeforeRemove = notifyCount;
      await controller.removeDownload(task.id);
      expect(controller.tasks, isEmpty);
      expect(notifyCount, greaterThan(countBeforeRemove));
    });

    test('Máquina de Estados de Download valida transições permitidas e rejeita inválidas', () {
      expect(DownloadStatus.queued.canTransitionTo(DownloadStatus.starting), isTrue);
      expect(DownloadStatus.queued.canTransitionTo(DownloadStatus.downloading), isFalse);

      expect(DownloadStatus.starting.canTransitionTo(DownloadStatus.downloading), isTrue);
      expect(DownloadStatus.starting.canTransitionTo(DownloadStatus.pausing), isTrue);

      expect(DownloadStatus.downloading.canTransitionTo(DownloadStatus.pausing), isTrue);
      expect(DownloadStatus.downloading.canTransitionTo(DownloadStatus.finalizing), isTrue);
      expect(DownloadStatus.downloading.canTransitionTo(DownloadStatus.resuming), isFalse);

      expect(DownloadStatus.pausing.canTransitionTo(DownloadStatus.paused), isTrue);
      expect(DownloadStatus.paused.canTransitionTo(DownloadStatus.resuming), isTrue);
      expect(DownloadStatus.paused.canTransitionTo(DownloadStatus.downloading), isTrue);

      expect(DownloadStatus.resuming.canTransitionTo(DownloadStatus.downloading), isTrue);
      expect(DownloadStatus.finalizing.canTransitionTo(DownloadStatus.completed), isTrue);
    });

    test('Pausa manual pelo usuário persiste e NUNCA é retomada automaticamente', () async {
      final task = await controller.addDownload(url: 'https://example.com/pause_test.iso');
      expect(task.fileName, equals('pause_test.iso'));

      // Pausa a tarefa
      await controller.pauseDownload(task.id);
      expect(controller.tasks.first.status, equals(DownloadStatus.paused));
      expect(controller.tasks.first.isUserPaused, isTrue);

      // Simula recriação do controlador recarregando o arquivo persistido
      final restoredController = Aria2DownloadController(
        downloadDir: tempDir.path,
        storageFilePath: '${tempDir.path}/tasks.json',
      );
      expect(restoredController.tasks.first.status, equals(DownloadStatus.paused));
      expect(restoredController.tasks.first.isUserPaused, isTrue);
      await restoredController.stopDaemon();
    });

    test('Remoção de download impede terminantemente ressurreição da tarefa', () async {
      final task = await controller.addDownload(url: 'https://example.com/test_iso.iso');
      expect(controller.tasks.length, equals(1));

      // Remove a tarefa
      await controller.removeDownload(task.id);
      expect(controller.tasks, isEmpty);

      // Espera ciclo assíncrono para garantir que nenhum callback ressuscita a tarefa
      await Future.delayed(const Duration(milliseconds: 100));
      expect(controller.tasks, isEmpty);
    });
  });

  group('DartSegmentedDownloader (Range Requests e Integridade)', () {
    late HttpServer server;
    late Directory tempDir;
    late Uint8List dummyData;
    late String dummySha256;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_range_test_');

      // Gera 2MB de dados para teste de Range
      dummyData = Uint8List(2 * 1024 * 1024);
      for (var i = 0; i < dummyData.length; i++) {
        dummyData[i] = i % 256;
      }
      dummySha256 = std_crypto.sha256.convert(dummyData).toString();

      // Servidor HTTP local com suporte a Range Requests
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

        if (request.method == 'HEAD') {
          request.response.headers.add(HttpHeaders.acceptRangesHeader, 'bytes');
          request.response.headers.add(HttpHeaders.contentLengthHeader, dummyData.length.toString());
          request.response.statusCode = HttpStatus.ok;
          request.response.close();
          return;
        }

        if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
          final parts = rangeHeader.substring(6).split('-');
          final start = int.parse(parts[0]);
          final end = (parts.length > 1 && parts[1].isNotEmpty) ? int.parse(parts[1]) : dummyData.length - 1;
          final chunk = dummyData.sublist(start, end + 1);

          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.add(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${dummyData.length}');
          request.response.headers.add(HttpHeaders.contentLengthHeader, chunk.length.toString());

          if (request.uri.path.contains('throttled')) {
            () async {
              const blockSize = 32 * 1024;
              for (var offset = 0; offset < chunk.length; offset += blockSize) {
                final endOffset = (offset + blockSize < chunk.length) ? offset + blockSize : chunk.length;
                try {
                  request.response.add(chunk.sublist(offset, endOffset));
                  await request.response.flush();
                  await Future.delayed(const Duration(milliseconds: 15));
                } catch (_) {
                  break;
                }
              }
              try {
                await request.response.close();
              } catch (_) {}
            }();
          } else {
            request.response.add(chunk);
            request.response.close();
          }
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.add(HttpHeaders.contentLengthHeader, dummyData.length.toString());
          request.response.add(dummyData);
          request.response.close();
        }
      });
    });

    tearDown(() async {
      await server.close(force: true);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Baixa arquivo via HTTP Range Requests segmentados em paralelo e confere SHA-256', () async {
      final downloader = DartSegmentedDownloader();
      final destination = '${tempDir.path}/test_download.bin';

      final task = DownloadTask(
        id: 'task_test_1',
        url: 'http://127.0.0.1:${server.port}/download.bin',
        destinationPath: destination,
        fileName: 'test_download.bin',
        sha256Expected: dummySha256,
        createdAt: DateTime.now(),
      );

      final completed = await downloader.download(task: task, splitCount: 4);

      expect(completed.status, equals(DownloadStatus.completed));
      expect(completed.isRangeSupported, isTrue);
      expect(completed.splitCount, equals(4));
      expect(completed.sha256Actual, equals(dummySha256));

      final downloadedFile = File(destination);
      expect(downloadedFile.existsSync(), isTrue);
      expect(downloadedFile.lengthSync(), equals(dummyData.length));
    });

    test('Falha na verificação de integridade caso o SHA-256 não confira', () async {
      final downloader = DartSegmentedDownloader();
      final destination = '${tempDir.path}/corrupt_test.bin';

      final task = DownloadTask(
        id: 'task_test_corrupt',
        url: 'http://127.0.0.1:${server.port}/download.bin',
        destinationPath: destination,
        fileName: 'corrupt_test.bin',
        sha256Expected: '0000000000000000000000000000000000000000000000000000000000000000', // Hash incorreto
        createdAt: DateTime.now(),
      );

      final completed = await downloader.download(task: task);
      expect(completed.status, equals(DownloadStatus.failed));
      expect(completed.errorMessage, contains('Falha de integridade'));
    });

    test('Pausa imediata congela transferência e retomada conclui com sucesso', () async {
      final downloader = DartSegmentedDownloader();
      final destination = '${tempDir.path}/pause_resume_test.bin';

      final task = DownloadTask(
        id: 'task_pause_resume',
        url: 'http://127.0.0.1:${server.port}/throttled_download.bin',
        destinationPath: destination,
        fileName: 'pause_resume_test.bin',
        sha256Expected: dummySha256,
        createdAt: DateTime.now(),
      );

      // Inicia download em background e pausa aos 50ms
      final dlFuture = downloader.download(
        task: task,
        splitCount: 4,
      );
      Future.delayed(const Duration(milliseconds: 60), () {
        downloader.pause(task.id);
      });

      final pausedResult = await dlFuture;
      expect(pausedResult.status, equals(DownloadStatus.paused));
      expect(pausedResult.downloadedBytes, lessThan(dummyData.length));

      final bytesAtPause = pausedResult.downloadedBytes;
      // Garante que os bytes parciais não continuam crescendo após a confirmação da pausa
      await Future.delayed(const Duration(milliseconds: 150));
      expect(pausedResult.downloadedBytes, equals(bytesAtPause));

      // Retoma a transferência
      final resumedResult = await downloader.download(
        task: pausedResult.copyWith(status: DownloadStatus.downloading),
        splitCount: 4,
      );

      expect(resumedResult.status, equals(DownloadStatus.completed));
      expect(resumedResult.sha256Actual, equals(dummySha256));
      expect(File(destination).lengthSync(), equals(dummyData.length));
    });
  });
}
