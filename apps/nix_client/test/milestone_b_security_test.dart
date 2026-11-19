import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/database/local_database.dart';
import 'package:nix_client/core/security/key_vault.dart';
import 'package:nix_client/core/security/os_key_storage.dart';
import 'package:nix_client/core/security/seed_recovery.dart';
import 'package:nix_client/state/nix_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fase 1 P0: Seed A, OsKeyStorage, Duress PIN, SQLCipher & Reload', () {
    late Directory tempDir;
    late String dbPath;
    late String vaultPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_milestone_b_');
      dbPath = '${tempDir.path}/nix_local_v4.db';
      vaultPath = '${tempDir.path}/vault_bootstrap.json';
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('SeedRecoveryManager gera 24 palavras com checksum e recupera exatamente a NixIdentity', () async {
      final words = SeedRecoveryManager.generateMnemonic();
      expect(words.length, 24);
      expect(SeedRecoveryManager.validateMnemonic(words), isTrue);

      // Adulteração de uma palavra invalida o checksum SHA-256
      final tampered = List<String>.from(words);
      tampered[0] = tampered[0] == 'anchor' ? 'abandon' : 'anchor';
      expect(SeedRecoveryManager.validateMnemonic(tampered), isFalse);

      final id1 = await SeedRecoveryManager.deriveIdentityFromMnemonic(words);
      final id2 = await SeedRecoveryManager.deriveIdentityFromMnemonic(words);
      expect(id1.publicId, startsWith('NIX-'));
      expect(id1.publicId, equals(id2.publicId));
      expect(id1.ed25519PublicHex, equals(id2.ed25519PublicHex));
      expect(id1.x25519PublicHex, equals(id2.x25519PublicHex));
    });

    test('Fluxo completo: Seed A -> SQLCipher -> Restart Reload -> Mensagens Salvas & Fail-Closed', () async {
      final sharedKeyring = InMemoryOsKeyStorage();
      final words = SeedRecoveryManager.generateMnemonic();
      final expectedIdentity = await SeedRecoveryManager.deriveIdentityFromMnemonic(words);

      // 1. Fail-closed antes de desbloquear o KeyVault
      final lockedState = NixState(
        loadMockData: false,
        keyVault: KeyVault(osKeyStorage: sharedKeyring),
      );
      final denied = await lockedState.sendSovereignMessage(
        conversationId: 'conv_none',
        text: 'nao deve gravar em claro',
      );
      expect(denied, isFalse);

      // 2. Provisiona identidade via Seed A + keyring do SO + SQLCipher
      final firstState = NixState(
        loadMockData: false,
        keyVault: KeyVault(osKeyStorage: sharedKeyring),
      );
      final ok = await firstState.initializeEncryptedDatabase(
        passphrase: 'frase-secreta-soberana',
        customDbPath: dbPath,
        customVaultPath: vaultPath,
        bindToOsKeyring: true,
      );
      expect(ok, isTrue);

      await firstState.persistPrimaryIdentity(
        identity: expectedIdentity,
        displayName: 'Operador Alpha',
        bio: 'Estação Isolada',
      );

      // Envia mensagem na Outbox sem chave do par -> usa selamento do cofre, zero plaintext
      const secretNote = 'SEGREDO_CRITICO_ZERO_PLAINTEXT_9911';
      final queued = await firstState.sendSovereignMessage(
        conversationId: 'dm_saved_messages',
        text: secretNote,
      );
      expect(queued, isTrue);

      final pendingRows = await firstState.outboxRepo!.getPendingEnvelopes();
      expect(pendingRows.length, 1);
      final ciphertext = pendingRows.first['ciphertext'] as List<int>;
      expect(utf8.decode(ciphertext, allowMalformed: true), isNot(contains(secretNote)));

      // Verifica no arquivo em disco caso o runtime ativo seja SQLCipher real
      final isSqlCipher = firstState.localDatabase!.cipherInfo.isEncrypted;
      await firstState.localDatabase!.close();

      if (isSqlCipher) {
        final rawDiskBytes = await File(dbPath).readAsBytes();
        final rawAscii = utf8.decode(rawDiskBytes, allowMalformed: true);
        expect(rawAscii, isNot(startsWith('SQLite format 3')));
        expect(rawAscii, isNot(contains(secretNote)));
        await expectLater(
          LocalDatabase.open(path: dbPath, rawCipherKey: Uint8List(32)),
          throwsA(isA<Exception>()),
        );
      }

      // 3. Simula reinicialização fria (nova instância NixState com mesmo keyring)
      final restartedState = NixState(
        loadMockData: false,
        keyVault: KeyVault(osKeyStorage: sharedKeyring),
      );
      final restoredOk = await restartedState.tryAutoUnlockAndRestore(
        customDbPath: dbPath,
        customVaultPath: vaultPath,
      );
      expect(restoredOk, isTrue);
      expect(restartedState.isOnboarded, isTrue);
      expect(restartedState.userProfile.publicId, equals(expectedIdentity.publicId));
      expect(restartedState.userProfile.displayName, equals('Operador Alpha'));
      expect(restartedState.primaryIdentity, isNotNull);
      expect(restartedState.primaryIdentity!.ed25519PublicHex,
          equals(expectedIdentity.ed25519PublicHex));

      final savedThread = restartedState.directMessages
          .firstWhere((d) => d.id == 'dm_saved_messages');
      expect(savedThread.messages.any((m) => m.text == secretNote), isTrue);

      await restartedState.localDatabase!.close();
    });

    test('PIN de Coacao (Duress PIN) aciona shredder e limpa SQLCipher + KeyVault + OS Keyring', () async {
      final sharedKeyring = InMemoryOsKeyStorage();
      final vault = KeyVault(osKeyStorage: sharedKeyring);
      final state = NixState(loadMockData: false, keyVault: vault);

      final ok = await state.initializeEncryptedDatabase(
        passphrase: 'senha-real-de-acesso',
        duressPassphrase: 'pin-coacao-emergencia',
        customDbPath: dbPath,
        customVaultPath: vaultPath,
        bindToOsKeyring: true,
      );
      expect(ok, isTrue);

      final identity = await SeedRecoveryManager.deriveIdentityFromMnemonic(
        SeedRecoveryManager.generateMnemonic(),
      );
      await state.persistPrimaryIdentity(
        identity: identity,
        displayName: 'Identidade Descartavel',
      );
      expect(await File(dbPath).exists(), isTrue);
      expect(
        await KeyVault(osKeyStorage: sharedKeyring).tryUnlockWithOsKeyring(
          customPath: vaultPath,
        ),
        isNotNull,
      );

      // Fecha DB e testa acionamento real do PIN de coação via unlockWithPassphrase
      await state.localDatabase!.close();

      final recoveryState = NixState(
        loadMockData: false,
        keyVault: KeyVault(osKeyStorage: sharedKeyring),
      );
      final checkRes = await recoveryState.unlockWithPassphrase(
        'pin-coacao-emergencia',
        customDbPath: dbPath,
        customVaultPath: vaultPath,
        customWipeBaseDir: tempDir.path,
      );
      expect(checkRes.status, equals(VaultUnlockStatus.duressTriggered));
      expect(await File(dbPath).exists(), isFalse);
      expect(await File(vaultPath).exists(), isFalse);
      expect(
        await KeyVault(osKeyStorage: sharedKeyring).tryUnlockWithOsKeyring(
          customPath: vaultPath,
        ),
        isNull,
      );
      expect(recoveryState.isOnboarded, isFalse);
      expect(recoveryState.primaryIdentity, isNull);
    });

    test('rollback atômico remove bootstrap órfão e keyring se SQLCipher falhar na criação',
        () async {
      final keyring = InMemoryOsKeyStorage();
      final vaultPath = '${tempDir.path}/rollback_vault.json';
      final dbPath = '${tempDir.path}/rollback_empty.db';
      final state = NixState(
        loadMockData: false,
        keyVault: KeyVault(osKeyStorage: keyring),
      );
      addTearDown(state.dispose);

      final ok = await state.initializeEncryptedDatabase(
        passphrase: 'senha-teste-rollback',
        customDbPath: dbPath,
        customVaultPath: vaultPath,
        bindToOsKeyring: true,
        migration001Sql: 'INVALID SQL STATEMENT;',
        migration002Sql: '',
      );
      expect(ok, isFalse);
      expect(state.lastDatabaseInitError, isNotNull);
      expect(await File(vaultPath).exists(), isFalse);
      expect(
        await KeyVault(osKeyStorage: keyring).tryUnlockWithOsKeyring(
          customPath: vaultPath,
        ),
        isNull,
      );
      expect(await File(dbPath).exists(), isFalse);
    });
  });
}
