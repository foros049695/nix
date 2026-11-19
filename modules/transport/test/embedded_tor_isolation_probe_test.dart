import 'dart:io';
import 'package:test/test.dart';
import 'package:nix_transport/nix_transport.dart';

void main() {
  late Directory temp;
  setUp(() async =>
      temp = await Directory.systemTemp.createTemp('nix_tor_probe_'));
  tearDown(() async => temp.delete(recursive: true));

  test('sondagem injetada ignora uma porta real aberta', () async {
    // Servidor sintético somente no namespace de rede isolado dos testes.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    var connections = 0;
    final subscription = server.listen((socket) {
      connections++;
      socket.destroy();
    });
    final manager = EmbeddedTorManager(
      socksPort: server.port,
      customTorBinary: '${temp.path}/missing',
      customDataDir: temp.path,
      portProbe: (_, __) async => false,
    );
    try {
      expect(await manager.startEmbeddedTor(), isFalse);
      expect(manager.status, EmbeddedTorStatus.error);
      expect(connections, 0);
    } finally {
      manager.dispose();
      await subscription.cancel();
      await server.close();
    }
  });

  test('timeout encerra o filho antes de retornar', () async {
    final pidFile = File('${temp.path}/pid');
    final binary = File('${temp.path}/fake-tor');
    await binary.writeAsString(
        '#!/bin/sh\necho \$\$ > "${pidFile.path}"\nexec sleep 60\n');
    expect((await Process.run('chmod', ['+x', binary.path])).exitCode, 0);
    final manager = EmbeddedTorManager(
      socksPort: 1,
      portProbe: (_, __) async => false,
      customTorBinary: binary.path,
      customDataDir: '${temp.path}/data',
    );
    int? childPid;
    try {
      expect(
          await manager.startEmbeddedTor(
              timeout: const Duration(milliseconds: 400)),
          isFalse);
      childPid = int.parse(await pidFile.readAsString());
      expect(await Directory('/proc/$childPid').exists(), isFalse,
          reason: 'o processo simulado ainda está vivo após o timeout');
      expect(manager.status, EmbeddedTorStatus.error);
      expect(manager.lastSummary, contains('limite'));
    } finally {
      if (childPid != null && await Directory('/proc/$childPid').exists()) {
        Process.killPid(childPid, ProcessSignal.sigkill);
      }
      await manager.stop();
      manager.dispose();
    }
  }, skip: !Platform.isLinux ? 'Probe de processo Linux' : false);

  test('starter injetado recebe e preserva LD_LIBRARY_PATH', () async {
    final binary = File('${temp.path}/fake-tor');
    final environmentFile = File('${temp.path}/environment');
    await binary.writeAsString(
        '#!/bin/sh\nprintf "%s" "\$LD_LIBRARY_PATH" > "${environmentFile.path}"\n');
    expect((await Process.run('chmod', ['+x', binary.path])).exitCode, 0);
    Map<String, String>? receivedEnvironment;
    var starts = 0;
    final manager = EmbeddedTorManager(
      customTorBinary: binary.path,
      customDataDir: '${temp.path}/data',
      portProbe: (_, __) async => false,
      processStarter: (binary, args, {environment}) {
        starts++;
        receivedEnvironment = environment;
        return Process.start(binary, args, environment: environment);
      },
    );
    addTearDown(manager.dispose);
    expect(await manager.startEmbeddedTor(), isFalse);
    expect(starts, 1);
    final expectedPath =
        '${temp.path}/lib:${temp.path}:${Platform.environment['HOME'] ?? ''}/.local/lib:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}';
    expect(receivedEnvironment, {'LD_LIBRARY_PATH': expectedPath});
    expect(await environmentFile.readAsString(), expectedPath);
  }, skip: Platform.isWindows ? 'Script POSIX' : false);
}
