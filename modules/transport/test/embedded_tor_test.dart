import 'dart:io';
import 'package:test/test.dart';
import 'package:nix_transport/nix_transport.dart';

void main() {
  group('EmbeddedTorManager (Tor Embutido Zero-Configuration)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_tor_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('gera arquivo torrc endurecido com diretório isolado e portas configuradas', () async {
      final manager = EmbeddedTorManager(
        socksPort: 9150,
        controlPort: 9151,
        customDataDir: tempDir.path,
      );

      final torrc = await manager.generateHardenedTorrc();
      expect(await torrc.exists(), isTrue);

      final content = await torrc.readAsString();
      expect(content.contains('SocksPort 127.0.0.1:9150'), isTrue);
      expect(content.contains('ControlPort 127.0.0.1:9151'), isTrue);
      expect(content.contains('DataDirectory ${tempDir.path}'), isTrue);
      expect(content.contains('SafeSocks 1'), isTrue);
      expect(content.contains('AvoidDiskWrites 1'), isTrue);
    });

    test('reage com falha explícita se binário tor não for encontrado', () async {
      final manager = EmbeddedTorManager(
        customDataDir: tempDir.path,
        customTorBinary: '/caminho/completamente/inexistente/tor',
      );

      final ok = await manager.startEmbeddedTor();
      expect(ok, isFalse);
      expect(manager.status, equals(EmbeddedTorStatus.error));
      expect(manager.lastSummary.contains('não encontrado'), isTrue);
    });
  });
}
