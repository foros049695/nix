import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/downloads/aria2_download_controller.dart';

Future<File> _createFakeAria2LifecycleBinary(Directory dir, File argvLog) async {
  final script = File('${dir.path}/fake_aria2c_lifecycle.py');
  await script.writeAsString('''#!/usr/bin/env python3
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

log_path = ${jsonEncode(argvLog.path)}
port = 6800
for arg in sys.argv[1:]:
    if arg.startswith('--rpc-listen-port='):
        port = int(arg.split('=', 1)[1])

with open(log_path, 'a', encoding='utf-8') as fh:
    fh.write(json.dumps({'argv': sys.argv[1:]}) + '\\n')

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        body = json.loads(self.rfile.read(length))
        method = body.get('method', '')
        if method == 'aria2.getVersion':
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

Future<File> _createImmediateExitBinary(Directory dir) async {
  final script = File('${dir.path}/exit_immediately_aria2c.sh');
  await script.writeAsString('#!/bin/sh\nexit 1\n');
  Process.runSync('chmod', ['+x', script.path]);
  return script;
}

Future<File> _createSleeperScript(Directory dir, String fileName) async {
  final script = File('${dir.path}/$fileName');
  await script.writeAsString('''#!/usr/bin/env python3
import time
time.sleep(30)
''');
  Process.runSync('chmod', ['+x', script.path]);
  return script;
}

bool _isPidRunning(int targetPid) {
  if (Platform.isLinux) {
    final statFile = File('/proc/$targetPid/stat');
    if (!statFile.existsSync()) return false;
    try {
      final content = statFile.readAsStringSync();
      // Processos zumbis ('Z') já encerraram e aguardam wait()
      return !RegExp(r'\)\s+Z\s').hasMatch(content);
    } catch (_) {
      return false;
    }
  }
  return false;
}

void main() {
  group('Ciclo de vida do daemon aria2 e persistência multiplataforma', () {
    late Directory tempDir;
    late String dataDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_aria2_lifecycle_');
      dataDir = '${tempDir.path}/data';
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('startDaemon passa --stop-with-process=<pid do app> ao aria2c', () async {
      final argvLog = File('${tempDir.path}/argv.jsonl');
      final fakeBin = await _createFakeAria2LifecycleBinary(tempDir, argvLog);

      final ctl = Aria2DownloadController(
        downloadDir: '${tempDir.path}/dl',
        customBinaryPath: fakeBin.path,
        storageFilePath: '${tempDir.path}/tasks.json',
        rpcPort: 0,
        dataDirectory: dataDir,
      );
      addTearDown(() async => ctl.stopDaemon());

      final started = await ctl.startDaemon();
      expect(started, isTrue);
      expect(ctl.isDaemonRunning, isTrue);

      final logged = jsonDecode(argvLog.readAsLinesSync().first) as Map<String, dynamic>;
      final argv = (logged['argv'] as List).cast<String>();
      expect(argv, contains('--stop-with-process=$pid'));
    });

    test('startDaemon não reporta execução quando nenhum processo aria2 existe ou falha ao subir', () async {
      // 1. Binário inexistente
      final ctlMissing = Aria2DownloadController(
        downloadDir: '${tempDir.path}/dl_missing',
        customBinaryPath: '${tempDir.path}/nonexistent_aria2c_binary',
        storageFilePath: '${tempDir.path}/tasks_missing.json',
        enableFallback: true,
        rpcPort: 0,
        dataDirectory: dataDir,
      );
      addTearDown(() async => ctlMissing.stopDaemon());

      final startedMissing = await ctlMissing.startDaemon();
      expect(startedMissing, isFalse);
      expect(ctlMissing.isDaemonRunning, isFalse);

      // 2. Binário que encerra imediatamente sem abrir RPC
      final exitBin = await _createImmediateExitBinary(tempDir);
      final ctlDead = Aria2DownloadController(
        downloadDir: '${tempDir.path}/dl_dead',
        customBinaryPath: exitBin.path,
        storageFilePath: '${tempDir.path}/tasks_dead.json',
        enableFallback: true,
        rpcPort: 0,
        dataDirectory: dataDir,
      );
      addTearDown(() async => ctlDead.stopDaemon());

      final startedDead = await ctlDead.startDaemon();
      expect(startedDead, isFalse);
      expect(ctlDead.isDaemonRunning, isFalse);
    });

    test('_terminatePreviousNixDaemon preserva processos alheios/irmãos vivos e encerra órfão do Nix', () async {
      final argvLog = File('${tempDir.path}/argv_term.jsonl');
      final fakeBin = await _createFakeAria2LifecycleBinary(tempDir, argvLog);

      // Diretório de dados isolado do teste (mesmo caminho injetado nos controladores)
      Directory(dataDir).createSync(recursive: true);
      final pidFile = File('$dataDir/aria2.pid');
      final sessionPath = '$dataDir/aria2.session';

      // Caso 0: processo arbitrário não-aria2 cujo PID reciclado caiu em aria2.pid
      final unrelatedScript = await _createSleeperScript(tempDir, 'unrelated_worker.py');
      final unrelatedProc = await Process.start(unrelatedScript.path, const []);
      addTearDown(() => unrelatedProc.kill(ProcessSignal.sigkill));
      pidFile.writeAsStringSync('${unrelatedProc.pid}\n');

      final ctl0 = Aria2DownloadController(
        downloadDir: '${tempDir.path}/dl_0',
        customBinaryPath: fakeBin.path,
        storageFilePath: '${tempDir.path}/tasks_0.json',
        rpcPort: 0,
        dataDirectory: dataDir,
      );
      await ctl0.startDaemon();
      await ctl0.stopDaemon();
      expect(
        _isPidRunning(unrelatedProc.pid),
        isTrue,
        reason: 'processo não-aria2 com PID reciclado jamais deve ser encerrado',
      );
      unrelatedProc.kill(ProcessSignal.sigkill);
      await unrelatedProc.exitCode;

      // Caso 1: processo aria2 manual do usuário (RPC habilitado, mas não foi iniciado por este app)
      final manualAriaScript = await _createSleeperScript(tempDir, 'manual_aria2_user.py');
      final manualProc = await Process.start(
        manualAriaScript.path,
        ['--enable-rpc=true'],
      );
      addTearDown(() => manualProc.kill(ProcessSignal.sigkill));

      pidFile.writeAsStringSync('${manualProc.pid}\n');

      final ctl1 = Aria2DownloadController(
        downloadDir: '${tempDir.path}/dl_1',
        customBinaryPath: fakeBin.path,
        storageFilePath: '${tempDir.path}/tasks_1.json',
        rpcPort: 0,
        dataDirectory: dataDir,
      );
      await ctl1.startDaemon();
      await ctl1.stopDaemon();

      expect(
        _isPidRunning(manualProc.pid),
        isTrue,
        reason: 'aria2 manual do usuário não deve ser morto pelo Nix',
      );
      manualProc.kill(ProcessSignal.sigkill);
      await manualProc.exitCode;

      // Caso 2: daemon de outra instância viva do Nix (--stop-with-process aponta para PID vivo)
      final siblingOwnerScript = await _createSleeperScript(tempDir, 'sibling_app.py');
      final siblingOwnerProc = await Process.start(siblingOwnerScript.path, const []);
      addTearDown(() => siblingOwnerProc.kill(ProcessSignal.sigkill));

      final siblingDaemonScript = await _createSleeperScript(tempDir, 'sibling_aria2c.py');
      final siblingDaemonProc = await Process.start(
        siblingDaemonScript.path,
        [
          '--enable-rpc=true',
          '--save-session=$sessionPath',
          '--stop-with-process=${siblingOwnerProc.pid}',
        ],
      );
      addTearDown(() => siblingDaemonProc.kill(ProcessSignal.sigkill));

      pidFile.writeAsStringSync('${siblingDaemonProc.pid}\n');

      final ctl2 = Aria2DownloadController(
        downloadDir: '${tempDir.path}/dl_2',
        customBinaryPath: fakeBin.path,
        storageFilePath: '${tempDir.path}/tasks_2.json',
        rpcPort: 0,
        dataDirectory: dataDir,
      );
      await ctl2.startDaemon();
      await ctl2.stopDaemon();

      expect(
        _isPidRunning(siblingDaemonProc.pid),
        isTrue,
        reason: 'daemon pertencente a outra instância ativa do Nix não deve ser morto',
      );
      siblingDaemonProc.kill(ProcessSignal.sigkill);
      siblingOwnerProc.kill(ProcessSignal.sigkill);
      await siblingDaemonProc.exitCode;
      await siblingOwnerProc.exitCode;

      // Caso 3: daemon órfão do próprio Nix (--stop-with-process aponta para PID inexistente) DEVE ser encerrado
      final orphanDaemonScript = await _createSleeperScript(tempDir, 'orphan_aria2c.py');
      final orphanDaemonProc = await Process.start(
        orphanDaemonScript.path,
        [
          '--enable-rpc=true',
          '--save-session=$sessionPath',
          '--stop-with-process=99999999',
        ],
      );
      addTearDown(() => orphanDaemonProc.kill(ProcessSignal.sigkill));

      pidFile.writeAsStringSync('${orphanDaemonProc.pid}\n');

      final ctl3 = Aria2DownloadController(
        downloadDir: '${tempDir.path}/dl_3',
        customBinaryPath: fakeBin.path,
        storageFilePath: '${tempDir.path}/tasks_3.json',
        rpcPort: 0,
        dataDirectory: dataDir,
      );
      await ctl3.startDaemon();
      await ctl3.stopDaemon();
      await orphanDaemonProc.exitCode.timeout(const Duration(seconds: 10));
      expect(_isPidRunning(orphanDaemonProc.pid), isFalse);
    });

    test('persiste e recarrega tarefas no diretório de dados mesmo sem storageFilePath explícito', () async {
      final ctlWrite = Aria2DownloadController(
        downloadDir: '${tempDir.path}/dl_persist',
        customBinaryPath: '${tempDir.path}/missing_aria2c',
        rpcPort: 0,
        dataDirectory: dataDir,
      );
      addTearDown(() async => ctlWrite.stopDaemon());

      final added = await ctlWrite.addDownload(
        url: 'http://127.0.0.1:9/persisted_platform_check.iso',
      );
      await ctlWrite.pauseDownload(added.id);

      final ctlRead = Aria2DownloadController(
        downloadDir: '${tempDir.path}/dl_persist',
        customBinaryPath: '${tempDir.path}/missing_aria2c',
        rpcPort: 0,
        dataDirectory: dataDir,
      );
      addTearDown(() async {
        await ctlRead.removeDownload(added.id);
        await ctlRead.stopDaemon();
      });

      expect(ctlWrite.isDaemonRunning, isFalse);
      expect(File('$dataDir/downloads_tasks.json').existsSync(), isTrue);
      expect(
        ctlRead.tasks.any((t) => t.id == added.id && t.fileName == 'persisted_platform_check.iso'),
        isTrue,
      );
    });
  });
}
