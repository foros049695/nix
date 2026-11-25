import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/downloads/aria2_download_controller.dart';
import 'package:nix_client/core/downloads/dart_segmented_downloader.dart';
import 'package:nix_client/core/downloads/models/download_task.dart';

Future<File> _createFakeAria2Binary(Directory dir, File rpcLog) async {
  final script = File('${dir.path}/fake_aria2c.py');
  await script.writeAsString('''#!/usr/bin/env python3
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

log_path = ${jsonEncode(rpcLog.path)}
port = 6800
for arg in sys.argv[1:]:
    if arg.startswith('--rpc-listen-port='):
        port = int(arg.split('=', 1)[1])

gids = []

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        body = json.loads(self.rfile.read(length))
        method = body.get('method', '')
        if method == 'aria2.addUri':
            with open(log_path, 'a', encoding='utf-8') as fh:
                fh.write(json.dumps({
                    'uris': body['params'][1],
                    'options': body['params'][2],
                }) + '\\n')
            gid = '%016x' % (len(gids) + 1)
            gids.append(gid)
            result = gid
        elif method == 'aria2.getVersion':
            result = {'version': '1.37.0'}
        elif method in ('aria2.tellActive', 'aria2.tellWaiting', 'aria2.tellStopped'):
            result = []
        else:
            result = 'OK'
        payload = json.dumps({'jsonrpc': '2.0', 'id': body.get('id'), 'result': result}).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

HTTPServer(('127.0.0.1', port), Handler).serve_forever()
''');
  Process.runSync('chmod', ['+x', script.path]);
  return script;
}

Future<File> _createFailingBinary(Directory dir) async {
  final script = File('${dir.path}/fail_aria2c.sh');
  await script.writeAsString('#!/bin/sh\nexit 1\n');
  Process.runSync('chmod', ['+x', script.path]);
  return script;
}

void main() {
  group('Confinamento de nomes e destinos de download (aria2 + fallback Dart)', () {
    late Directory tempDir;
    late Directory downloadDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_dl_confine_');
      downloadDir = Directory('${tempDir.path}/dl')..createSync(recursive: true);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('aria2: sanitiza traversal na URL, customFileName, ocultos e aceita %25 literal', () async {
      final rpcLog = File('${tempDir.path}/rpc.jsonl');
      final fakeBin = await _createFakeAria2Binary(tempDir, rpcLog);
      final ctl = Aria2DownloadController(
        downloadDir: downloadDir.path,
        customBinaryPath: fakeBin.path,
        storageFilePath: '${tempDir.path}/tasks.json',
        rpcPort: 0,
      );
      addTearDown(() async => ctl.stopDaemon());

      await ctl.startDaemon();
      final canonicalDlDir = downloadDir.resolveSymbolicLinksSync();

      // 1. Path traversal codificado (%2F -> já decodificado em pathSegments)
      final tTraversal = await ctl.addDownload(
        url: 'https://example.invalid/a/..%2F..%2Fescaped.txt',
      );
      expect(tTraversal.fileName, equals('escaped.txt'));
      expect(tTraversal.fileName.contains('/'), isFalse);
      expect(tTraversal.fileName.contains('..'), isFalse);
      expect(File(tTraversal.destinationPath).parent.resolveSymbolicLinksSync(), equals(canonicalDlDir));

      // 2. URL com %25 literal não deve lançar Invalid URL encoding nem decodificar duas vezes
      final tPercent = await ctl.addDownload(
        url: 'https://example.invalid/releases/100%25.zip',
      );
      expect(tPercent.fileName, equals('100%.zip'));
      expect(File(tPercent.destinationPath).parent.resolveSymbolicLinksSync(), equals(canonicalDlDir));

      final tDoubleEncoded = await ctl.addDownload(
        url: 'https://example.invalid/a/..%252F..%252Fdouble.bin',
      );
      expect(tDoubleEncoded.fileName.contains('/'), isFalse);
      expect(tDoubleEncoded.fileName.contains('..'), isFalse);
      expect(tDoubleEncoded.fileName.startsWith('.'), isFalse);

      // 3. customFileName com traversal, separadores Windows, ocultos e '..'
      final tCustomTraversal = await ctl.addDownload(
        url: 'https://example.invalid/pkg.tar.gz',
        customFileName: '../../outside.tar.gz',
      );
      expect(tCustomTraversal.fileName, equals('outside.tar.gz'));
      expect(File(tCustomTraversal.destinationPath).parent.resolveSymbolicLinksSync(), equals(canonicalDlDir));

      final tCustomWin = await ctl.addDownload(
        url: 'https://example.invalid/pkg.tar.gz',
        customFileName: r'..\..\win_escape.exe',
      );
      expect(tCustomWin.fileName, equals('win_escape.exe'));

      final tHidden = await ctl.addDownload(
        url: 'https://example.invalid/.bashrc',
      );
      expect(tHidden.fileName.isNotEmpty, isTrue);
      expect(tHidden.fileName.startsWith('.'), isFalse);

      final tDotDot = await ctl.addDownload(
        url: 'https://example.invalid/ok.bin',
        customFileName: '..',
      );
      expect(tDotDot.fileName.isNotEmpty, isTrue);
      expect(tDotDot.fileName, isNot(equals('..')));
      expect(tDotDot.fileName.startsWith('.'), isFalse);

      // Verifica opções reais enviadas ao RPC aria2.addUri
      final entries = rpcLog
          .readAsLinesSync()
          .map((l) => jsonDecode(l) as Map<String, dynamic>)
          .toList();
      expect(entries, isNotEmpty);
      for (final entry in entries) {
        final opts = entry['options'] as Map<String, dynamic>;
        final outName = opts['out'] as String;
        expect(outName.isNotEmpty, isTrue);
        expect(outName.contains('/'), isFalse);
        expect(outName.contains('\\'), isFalse);
        expect(outName.contains('..'), isFalse);
        expect(outName.startsWith('.'), isFalse);
      }
      expect(
        (entries.first['options'] as Map<String, dynamic>)['out'],
        equals('escaped.txt'),
      );

      // 4. Link simbólico dentro do diretório apontando para fora deve ser recusado
      final outsideTarget = File('${tempDir.path}/outside_secret.txt')
        ..writeAsStringSync('intacto');
      Link('${downloadDir.path}/symlink_escape.bin').createSync(outsideTarget.path);

      await expectLater(
        () => ctl.addDownload(url: 'https://example.invalid/symlink_escape.bin'),
        throwsA(anything),
      );
      expect(outsideTarget.readAsStringSync(), equals('intacto'));
    });

    test('retomada mantém o diretório original da tarefa e reconfina destinos persistidos inseguros', () async {
      final rpcLog = File('${tempDir.path}/rpc_resume.jsonl');
      final fakeBin = await _createFakeAria2Binary(tempDir, rpcLog);
      final storage = File('${tempDir.path}/tasks_resume.json');
      final dirB = Directory('${tempDir.path}/dl_b')..createSync();

      // Tarefa persistida por versão anterior com nome e destino fora do diretório
      storage.writeAsStringSync(jsonEncode([
        DownloadTask(
          id: 'dl_legacy',
          url: 'https://example.invalid/legacy.bin',
          destinationPath: '${downloadDir.path}/../../legacy.bin',
          fileName: '../../legacy.bin',
          status: DownloadStatus.paused,
          isUserPaused: true,
          createdAt: DateTime.now(),
        ).toMap(),
      ]));

      final ctl = Aria2DownloadController(
        downloadDir: downloadDir.path,
        customBinaryPath: fakeBin.path,
        storageFilePath: storage.path,
        rpcPort: 0,
      );
      addTearDown(() async => ctl.stopDaemon());
      await ctl.startDaemon();

      final added = await ctl.addDownload(url: 'https://example.invalid/keep_dir.bin');
      final originalPath = added.destinationPath;
      await ctl.pauseDownload(added.id);

      ctl.setDownloadDir(dirB.path);
      await ctl.resumeDownload(added.id);
      final resumed = ctl.tasks.firstWhere((t) => t.url.endsWith('keep_dir.bin'));
      expect(resumed.destinationPath, equals(originalPath));
      expect(resumed.fileName, equals('keep_dir.bin'));

      await ctl.resumeDownload('dl_legacy');
      final legacy = ctl.tasks.firstWhere((t) => t.url.endsWith('legacy.bin'));
      expect(legacy.fileName, equals('legacy.bin'));
      expect(
        File(legacy.destinationPath).parent.resolveSymbolicLinksSync(),
        equals(dirB.resolveSymbolicLinksSync()),
      );
      final lastOptions = (jsonDecode(rpcLog.readAsLinesSync().last)
          as Map<String, dynamic>)['options'] as Map<String, dynamic>;
      expect(lastOptions['out'], equals('legacy.bin'));
      expect(lastOptions['dir'], equals(dirB.resolveSymbolicLinksSync()));
    });

    test('fallback Dart: confina destino ao diretório de download e recusa escape direto', () async {
      final payload = Uint8List.fromList(utf8.encode('conteudo-seguro-nix'));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));

      server.listen((req) async {
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.contentLength = payload.length;
        if (req.method != 'HEAD') {
          req.response.add(payload);
        }
        await req.response.close();
      });

      final failBin = await _createFailingBinary(tempDir);
      final ctl = Aria2DownloadController(
        downloadDir: downloadDir.path,
        customBinaryPath: failBin.path,
        storageFilePath: '${tempDir.path}/tasks_fb.json',
        rpcPort: 0,
      );
      addTearDown(() async => ctl.stopDaemon());

      final t = await ctl.addDownload(
        url: 'http://127.0.0.1:${server.port}/sub/..%2F..%2Fescaped_fb.bin',
      );
      expect(t.fileName, equals('escaped_fb.bin'));

      // Aguarda conclusão pelo fallback Dart
      for (var i = 0; i < 30; i++) {
        if (ctl.tasks.first.status == DownloadStatus.completed ||
            ctl.tasks.first.status == DownloadStatus.failed) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(ctl.tasks.first.status, equals(DownloadStatus.completed));
      expect(File('${tempDir.path}/escaped_fb.bin').existsSync(), isFalse);
      expect(File('${downloadDir.path}/escaped_fb.bin').existsSync(), isTrue);

      // Chamada direta ao DartSegmentedDownloader com caminho escapando deve falhar sem gravar fora
      final downloader = DartSegmentedDownloader();
      final badResult = await downloader.download(
        task: DownloadTask(
          id: 'dl_escape_direct',
          url: 'http://127.0.0.1:${server.port}/raw.bin',
          destinationPath: '${downloadDir.path}/../direct_escape.bin',
          fileName: '../direct_escape.bin',
          createdAt: DateTime.now(),
        ),
      );
      expect(badResult.status, equals(DownloadStatus.failed));
      expect(File('${tempDir.path}/direct_escape.bin').existsSync(), isFalse);
    });
  });
}
