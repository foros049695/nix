import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/downloads/aria2_download_controller.dart';
import 'package:nix_client/core/downloads/dart_segmented_downloader.dart';
import 'package:nix_client/core/downloads/models/download_task.dart';

Future<File> _createFakeAria2ForSha256(Directory dir, File rpcLog) async {
  final script = File('${dir.path}/fake_aria2_sha.py');
  await script.writeAsString('''#!/usr/bin/env python3
import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

log_path = ${jsonEncode(rpcLog.path)}
port = 6800
for arg in sys.argv[1:]:
    if arg.startswith('--rpc-listen-port='):
        port = int(arg.split('=', 1)[1])

stopped = []

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        body = json.loads(self.rfile.read(length))
        method = body.get('method', '')
        if method == 'aria2.addUri':
            uris = body['params'][1]
            opts = body['params'][2]
            with open(log_path, 'a', encoding='utf-8') as fh:
                fh.write(json.dumps({'uris': uris, 'options': opts}) + '\\n')
            gid = '%016x' % (len(stopped) + 1)
            out_dir = opts.get('dir', '')
            out_name = opts.get('out', '')
            os.makedirs(out_dir, exist_ok=True)
            target = os.path.join(out_dir, out_name)
            url = uris[0] if uris else ''
            if url.endswith('/valid.bin'):
                data = b'nix-valid-payload'
                with open(target, 'wb') as out_fh:
                    out_fh.write(data)
                size = str(len(data))
            elif url.endswith('/corrupt.bin'):
                data = b'tampered-payload'
                with open(target, 'wb') as out_fh:
                    out_fh.write(data)
                size = str(len(data))
            else:
                size = '16'
            stopped.append({
                'gid': gid,
                'status': 'complete',
                'totalLength': size,
                'completedLength': size,
                'downloadSpeed': '0',
                'connections': '0',
            })
            result = gid
        elif method == 'aria2.getVersion':
            result = {'version': '1.37.0'}
        elif method == 'aria2.tellStopped':
            result = list(stopped)
        elif method in ('aria2.tellActive', 'aria2.tellWaiting'):
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

void main() {
  group('Verificação SHA-256 no motor aria2 e interpolação de erro no fallback Dart', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_sha256_probe_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('aria2: envia checksum sha-256 ao addUri, aprova hash íntegro e reprova divergente ou ausente', () async {
      final rpcLog = File('${tempDir.path}/rpc_sha.jsonl');
      final fakeBin = await _createFakeAria2ForSha256(tempDir, rpcLog);
      final dlDir = '${tempDir.path}/dl';

      final ctl = Aria2DownloadController(
        downloadDir: dlDir,
        customBinaryPath: fakeBin.path,
        storageFilePath: '${tempDir.path}/tasks.json',
        rpcPort: 0,
      );
      addTearDown(() async => ctl.stopDaemon());
      await ctl.startDaemon();

      final validSha = std_crypto.sha256.convert(utf8.encode('nix-valid-payload')).toString();
      final tamperedSha = std_crypto.sha256.convert(utf8.encode('tampered-payload')).toString();
      final wrongExpected = '00' * 32;
      final missingExpected = '11' * 32;

      await ctl.addDownload(
        url: 'https://example.invalid/valid.bin',
        sha256Expected: validSha.toUpperCase(),
      );
      await ctl.addDownload(
        url: 'https://example.invalid/corrupt.bin',
        sha256Expected: wrongExpected,
      );
      await ctl.addDownload(
        url: 'https://example.invalid/missing.bin',
        sha256Expected: missingExpected,
      );

      // Aguarda dois ciclos de polling para garantir que o estado reprovado não seja revertido
      await Future<void>.delayed(const Duration(milliseconds: 2400));

      final validTask = ctl.tasks.firstWhere((t) => t.url.endsWith('/valid.bin'));
      final corruptTask = ctl.tasks.firstWhere((t) => t.url.endsWith('/corrupt.bin'));
      final missingTask = ctl.tasks.firstWhere((t) => t.url.endsWith('/missing.bin'));

      expect(validTask.status, equals(DownloadStatus.completed));
      expect(validTask.sha256Actual, equals(validSha));

      expect(corruptTask.status, equals(DownloadStatus.failed));
      expect(corruptTask.sha256Actual, equals(tamperedSha));
      expect(corruptTask.errorMessage, contains(wrongExpected));
      expect(corruptTask.errorMessage, contains(tamperedSha));
      expect(corruptTask.errorMessage, isNot(contains('Instance of')));

      expect(missingTask.status, equals(DownloadStatus.failed));
      expect(missingTask.errorMessage, isNotNull);

      final loggedCalls = rpcLog
          .readAsLinesSync()
          .map((l) => jsonDecode(l) as Map<String, dynamic>)
          .toList();
      expect(loggedCalls.length, equals(3));
      final firstOpts = loggedCalls[0]['options'] as Map<String, dynamic>;
      expect(firstOpts['checksum'], equals('sha-256=$validSha'));
      expect(firstOpts['check-integrity'], equals('true'));
    });

    test('DartSegmentedDownloader: interpola corretamente sha256Expected na mensagem de falha', () async {
      final data = Uint8List.fromList(utf8.encode('payload-teste-interpolacao'));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));

      server.listen((req) async {
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.contentLength = data.length;
        if (req.method != 'HEAD') {
          req.response.add(data);
        }
        await req.response.close();
      });

      final expected = 'ff' * 32;
      final downloader = DartSegmentedDownloader();
      final result = await downloader.download(
        task: DownloadTask(
          id: 'dl_interp_probe',
          url: 'http://127.0.0.1:${server.port}/payload.bin',
          destinationPath: '${tempDir.path}/payload.bin',
          fileName: 'payload.bin',
          sha256Expected: expected,
          createdAt: DateTime.now(),
        ),
      );

      expect(result.status, equals(DownloadStatus.failed));
      expect(result.errorMessage, contains(expected));
      expect(result.errorMessage, isNot(contains('Instance of')));
      expect(result.errorMessage, isNot(contains('.sha256Expected')));
    });
  });
}
