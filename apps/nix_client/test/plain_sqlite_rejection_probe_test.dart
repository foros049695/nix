import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/database/local_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'Fase 5 Probe: SQLite comum (libsqlite3.so.0) mesmo com rawCipherKey de 32 bytes '
      'é rejeitado fail-closed quando requireEncryption=true', () async {
    if (!Platform.isLinux) return;
    final plainLibCandidates = [
      '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
      '/usr/lib/libsqlite3.so.0',
      'libsqlite3.so.0',
      'libsqlite3.so',
    ];
    DynamicLibrary? foundPlain;
    for (final c in plainLibCandidates) {
      try {
        foundPlain = DynamicLibrary.open(c);
        break;
      } catch (_) {}
    }
    if (foundPlain == null) {
      return;
    }

    LocalDatabase.testNativeLibraryOverride = () => foundPlain!;
    addTearDown(() => LocalDatabase.testNativeLibraryOverride = null);

    final tempDir =
        await Directory.systemTemp.createTemp('nix_plain_sqlite_probe_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final dbPath = '${tempDir.path}/should_be_rejected.db';
    final validKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 11));

    // Mesmo passando chave válida de 32 bytes, SQLite comum não possui SQLCipher -> DEVE ser bloqueado!
    await expectLater(
      () => LocalDatabase.open(
        path: dbPath,
        rawCipherKey: validKey,
        requireEncryption: true,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('SQLCipher obrigatório'),
        ),
      ),
    );
    expect(File(dbPath).existsSync(), isFalse);

    // Sem requireEncryption (modo dev/laboratório), reporta honestamente isEncrypted == false
    final devDbPath = '${tempDir.path}/dev_honest.db';
    final devDb = await LocalDatabase.open(
      path: devDbPath,
      rawCipherKey: validKey,
      requireEncryption: false,
    );
    try {
      expect(devDb.cipherInfo.isEncrypted, isFalse);
      expect(devDb.cipherInfo.cipherVersion, isNull);
      expect(devDb.cipherInfo.cipherEngine, equals('SQLite-Development-Clearnet'));
    } finally {
      await devDb.close();
    }
  });
}
