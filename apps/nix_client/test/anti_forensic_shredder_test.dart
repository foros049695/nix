import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/security/anti_forensic_shredder.dart';
import 'package:nix_client/core/security/key_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AntiForensicShredder & Botão de Pânico (Destruição Soberana)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_shred_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('sobrescreve arquivo com múltiplas passagens destrutivas e apaga sem deixar rastro', () async {
      final sensitiveFile = File('${tempDir.path}/sensitive_data.txt');
      await sensitiveFile.writeAsString('CONTEUDO_EXTREMAMENTE_CONFIDENCIAL_CHAVE_PRIVADA_12345');

      expect(await sensitiveFile.exists(), isTrue);
      final initialLength = await sensitiveFile.length();
      expect(initialLength, greaterThan(0));

      final wipedBytes = await AntiForensicShredder.shredFile(sensitiveFile, passes: 3);
      expect(wipedBytes, equals(initialLength * 3));

      // Garante que o arquivo original foi totalmente excluído
      expect(await sensitiveFile.exists(), isFalse);

      // Garante que nenhum arquivo temporário de ofuscação sobrou
      final dirEntities = await tempDir.list().toList();
      expect(dirEntities.isEmpty, isTrue);
    });

    test('executa panicWipeAccount destruindo banco, cofre, preferências e memória RAM', () async {
      final dbFile = File('${tempDir.path}/nix_local_v4.db');
      final walFile = File('${tempDir.path}/nix_local_v4.db-wal');
      final vaultFile = File('${tempDir.path}/vault_bootstrap.json');
      final prefsFile = File('${tempDir.path}/client_prefs_v4.json');

      await dbFile.writeAsBytes(Uint8List.fromList(List.generate(1024, (i) => i % 256)));
      await walFile.writeAsBytes(Uint8List.fromList(List.generate(512, (i) => (i * 3) % 256)));
      await vaultFile.writeAsString(jsonEncode({'secret': 'my_vault_parameters'}));
      await prefsFile.writeAsString(jsonEncode({'theme': 'dark'}));

      final vault = KeyVault();
      await vault.initialize(
        passphrase: 'senha-de-teste-para-panico',
        customPath: vaultFile.path,
        overwrite: true,
      );
      expect(vault.isUnlocked, isTrue);

      final report = await AntiForensicShredder.panicWipeAccount(
        activeVault: vault,
        customBaseDir: tempDir.path,
        passes: 3,
      );

      expect(report.memoryWiped, isTrue);
      expect(vault.isUnlocked, isFalse);
      expect(() => vault.masterKey, throwsStateError);

      expect(await dbFile.exists(), isFalse);
      expect(await walFile.exists(), isFalse);
      expect(await vaultFile.exists(), isFalse);
      expect(await prefsFile.exists(), isFalse);

      expect(report.filesOverwritten, greaterThanOrEqualTo(3));
      expect(report.totalBytesWiped, greaterThan(0));
    });
  });
}
