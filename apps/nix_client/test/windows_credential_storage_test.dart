import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/security/os_key_storage.dart';

void main() {
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
}
