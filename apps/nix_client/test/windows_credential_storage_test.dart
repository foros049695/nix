import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/security/os_key_storage.dart';
import 'package:nix_client/core/database/local_database.dart';
import 'package:nix_client/core/database/repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Windows Credential Manager grava, lê e remove segredo temporário',
      () async {
    final backend = WindowsCredentialStorage.tryOpen()!;
    final slot = 'pilot-ci-${pid}_${Random.secure().nextInt(1 << 32)}';
    addTearDown(() => backend.deleteSecret(slot));
    expect(await backend.readSecret(slot), isNull);
    const sample = 'frase sintética de teste 🎵';
    expect(await backend.storeSecret(slot, sample), isTrue);
    expect(await backend.readSecret(slot), sample);
    expect(await backend.deleteSecret(slot), isTrue);
    expect(await backend.readSecret(slot), isNull);
  }, skip: !Platform.isWindows);
  test('Windows carrega SQLCipher e abre um cofre cifrado com a DLL do piloto',
      () async {
    final dir = await Directory.systemTemp.createTemp('nix-windows-sqlcipher-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/pilot.db';
    final key = Uint8List.fromList(
        List<int>.generate(32, (_) => Random.secure().nextInt(256)));
    final db = await LocalDatabase.open(
        path: path, rawCipherKey: key, requireEncryption: true);
    try {
      expect(db.cipherInfo.isEncrypted, isTrue);
      await PreferencesRepository(db)
          .setOption('smoke-check', 'dado sintético protegido');
    } finally {
      await db.close();
    }
    expect(latin1.decode(await File(path).readAsBytes()),
        isNot(contains('smoke-check')));
    final restored = await LocalDatabase.open(
        path: path, rawCipherKey: key, requireEncryption: true);
    try {
      expect(await PreferencesRepository(restored).getOption('smoke-check'),
          'dado sintético protegido');
    } finally {
      await restored.close();
    }
  }, skip: Platform.environment['NIX_TEST_WINDOWS_SQLCIPHER'] != 'true');
}
