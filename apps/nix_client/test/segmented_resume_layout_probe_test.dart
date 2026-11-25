import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/downloads/dart_segmented_downloader.dart';
import 'package:nix_client/core/downloads/models/download_task.dart';

void main() {
  group('DartSegmentedDownloader — Manifesto de Fatias e Isolamento de Geração', () {
    late Directory tempDir;

    setUp(() async {
      HttpOverrides.global = null;
      tempDir = await Directory.systemTemp.createTemp('nix_seg_probe_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('persiste manifesto ao pausar e não corrompe arquivo ao mudar splitCount (4->8, 8->2) ou órfãos', () async {
      final rnd = Random(1);
      final data = Uint8List.fromList(
        List.generate(4 * 1024 * 1024, (_) => rnd.nextInt(256)),
      );
      final expectedSha = std_crypto.sha256.convert(data).toString();

      var holdPartial = true;
      var partialSlicesSent = 0;
      var targetSlicesBeforePause = 4;
      Completer<void> readyToPause = Completer<void>();
      Completer<void> holdGate = Completer<void>();
      const currentEtag = '"v1-etag"';
      const lastMod = 'Wed, 25 Nov 2026 12:00:00 GMT';

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        if (!holdGate.isCompleted) holdGate.complete();
        await server.close(force: true);
      });

      server.listen((req) async {
        final res = req.response;
        res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        res.headers.set(HttpHeaders.etagHeader, currentEtag);
        res.headers.set(HttpHeaders.lastModifiedHeader, lastMod);
        if (req.method == 'HEAD') {
          res.headers.contentLength = data.length;
          await res.close();
          return;
        }
        final range = req.headers.value(HttpHeaders.rangeHeader);
        var start = 0;
        var end = data.length - 1;
        if (range != null) {
          final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
          start = int.parse(m.group(1)!);
          end = int.parse(m.group(2)!);
          res.statusCode = HttpStatus.partialContent;
          res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${data.length}');
        }
        res.headers.contentLength = end - start + 1;
        try {
          if (holdPartial) {
            // Envia 128 KB iniciais deste segmento e segura a conexão até a pausa
            final partialEnd = min(start + 131072, end + 1);
            res.add(data.sublist(start, partialEnd));
            await res.flush();
            partialSlicesSent++;
            if (partialSlicesSent >= targetSlicesBeforePause &&
                !readyToPause.isCompleted) {
              readyToPause.complete();
            }
            await holdGate.future;
            return;
          }
          for (var p = start; p <= end; p += 65536) {
            res.add(data.sublist(p, min(p + 65536, end + 1)));
            await res.flush();
          }
          await res.close();
        } catch (_) {}
      });

      Future<void> verifyPauseAndResume(String name, int split1, int split2) async {
        holdPartial = true;
        partialSlicesSent = 0;
        targetSlicesBeforePause = split1;
        readyToPause = Completer<void>();
        holdGate = Completer<void>();

        final downloader = DartSegmentedDownloader();
        final destPath = '${tempDir.path}/$name.bin';
        final task = DownloadTask(
          id: 'dl_$name',
          url: 'http://127.0.0.1:${server.port}/$name.bin',
          destinationPath: destPath,
          fileName: '$name.bin',
          createdAt: DateTime.now(),
        );

        final f1 = downloader.download(task: task, splitCount: split1);
        await readyToPause.future.timeout(const Duration(seconds: 5));
        // Pequena janela para o cliente gravar os 128 KB recebidos em cada .partN
        await Future<void>.delayed(const Duration(milliseconds: 40));
        downloader.pause(task.id);
        final r1 = await f1;
        if (!holdGate.isCompleted) holdGate.complete();
        expect(r1.status, equals(DownloadStatus.paused));

        final manifestFile = File('$destPath.parts.json');
        expect(manifestFile.existsSync(), isTrue,
            reason: 'manifesto de segmentos deve ser persistido junto às partes');
        final manifestJson = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
        expect(manifestJson['totalSize'], equals(data.length));
        expect(manifestJson['etag'], equals(currentEtag));
        expect(manifestJson['lastModified'], equals(lastMod));
        expect((manifestJson['segments'] as List).length, greaterThanOrEqualTo(split1));

        holdPartial = false;
        final r2 = await downloader.download(task: r1, splitCount: split2);
        expect(r2.status, equals(DownloadStatus.completed));

        final got = File(destPath).readAsBytesSync();
        expect(got.length, equals(data.length));
        expect(
          std_crypto.sha256.convert(got).toString(),
          equals(expectedSha),
          reason: '$name: SHA-256 final deve bater exatamente após retomada ($split1 -> $split2)',
        );
        expect(manifestFile.existsSync(), isFalse,
            reason: 'manifesto deve ser removido após costura final');
      }

      await verifyPauseAndResume('same_split_4_4', 4, 4);
      await verifyPauseAndResume('changed_split_4_8', 4, 8);
      await verifyPauseAndResume('changed_split_8_2', 8, 2);

      // Partes órfãs sem manifesto não devem ser aproveitadas às cegas
      final orphanDest = '${tempDir.path}/orphan.bin';
      File('$orphanDest.part0').writeAsBytesSync(List.filled(131072, 0xEE));
      File('$orphanDest.part1').writeAsBytesSync(List.filled(131072, 0xFF));
      holdPartial = false;
      final orphanRes = await DartSegmentedDownloader().download(
        task: DownloadTask(
          id: 'dl_orphan',
          url: 'http://127.0.0.1:${server.port}/orphan.bin',
          destinationPath: orphanDest,
          fileName: 'orphan.bin',
          createdAt: DateTime.now(),
        ),
        splitCount: 4,
      );
      expect(orphanRes.status, equals(DownloadStatus.completed));
      expect(
        std_crypto.sha256.convert(File(orphanDest).readAsBytesSync()).toString(),
        equals(expectedSha),
      );
    });

    test('pausa e retomada rápida encerra workers antigos pela geração em vez da flag _pausedTasks limpa', () async {
      final rnd = Random(7);
      final data = Uint8List.fromList(
        List.generate(2 * 1024 * 1024, (_) => rnd.nextInt(256)),
      );
      final expectedSha = std_crypto.sha256.convert(data).toString();

      var failFirstBatch = true;
      var gen1FailuresSeen = 0;
      final enteredBackoff = Completer<void>();

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));

      server.listen((req) async {
        final res = req.response;
        res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        if (req.method == 'HEAD') {
          res.headers.contentLength = data.length;
          await res.close();
          return;
        }
        final range = req.headers.value(HttpHeaders.rangeHeader)!;
        final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
        final start = int.parse(m.group(1)!);
        final end = int.parse(m.group(2)!);

        // Força a 1ª geração a entrar no backoff de 250ms de retry
        if (failFirstBatch) {
          gen1FailuresSeen++;
          if (gen1FailuresSeen >= 4 && !enteredBackoff.isCompleted) {
            enteredBackoff.complete();
          }
          res.statusCode = HttpStatus.internalServerError;
          await res.close();
          return;
        }

        res.statusCode = HttpStatus.partialContent;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${data.length}');
        res.headers.contentLength = end - start + 1;
        res.add(data.sublist(start, end + 1));
        await res.close();
      });

      final downloader = DartSegmentedDownloader();
      final destPath = '${tempDir.path}/rapid_resume.bin';
      final task = DownloadTask(
        id: 'dl_rapid',
        url: 'http://127.0.0.1:${server.port}/rapid.bin',
        destinationPath: destPath,
        fileName: 'rapid_resume.bin',
        createdAt: DateTime.now(),
      );

      final f1 = downloader.download(task: task, splitCount: 4);
      await enteredBackoff.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Pausa e retoma IMEDIATAMENTE antes da geração 1 acordar do backoff
      downloader.pause(task.id);
      failFirstBatch = false;
      final f2 = downloader.download(task: task, splitCount: 4);

      final r1 = await f1;
      final r2 = await f2;

      expect(r1.status, equals(DownloadStatus.paused),
          reason: 'geração 1 deve encerrar como pausada mesmo após retomada imediata');
      expect(r2.status, equals(DownloadStatus.completed));
      expect(
        std_crypto.sha256.convert(File(destPath).readAsBytesSync()).toString(),
        equals(expectedSha),
      );
    });
  });
}
