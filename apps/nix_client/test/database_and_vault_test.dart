import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nix_client/core/database/local_database.dart';
import 'package:nix_client/core/database/repositories.dart';
import 'package:nix_client/core/security/key_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('KeyVault Criptográfico (Marco P0-2 / T-VAULT)', () {
    late Directory tempDir;
    late String bootstrapPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_vault_test_');
      bootstrapPath = '${tempDir.path}/vault_bootstrap.json';
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('inicializa cofre, envelopa chave mestre de 32 bytes e não expõe chave em claro', () async {
      final vault = KeyVault();
      expect(await vault.isInitialized(customPath: bootstrapPath), isFalse);

      final masterKey = await vault.initialize(
        passphrase: 'senha-mestre-super-segura-2026',
        customPath: bootstrapPath,
      );

      expect(masterKey.length, equals(32));
      expect(vault.isUnlocked, isTrue);
      expect(vault.masterKey, equals(masterKey));
      expect(await vault.isInitialized(customPath: bootstrapPath), isTrue);

      // Inspeciona o arquivo no disco para garantir ausência de texto claro
      final content = await File(bootstrapPath).readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      expect(json['version'], equals(1));
      expect(json['kdf']['algorithm'], equals('Argon2id'));
      expect(content.contains(base64Encode(masterKey)), isFalse);
    });

    test('desbloqueia corretamente com a senha correta e rejeita senha incorreta', () async {
      final vault1 = KeyVault();
      final initialKey = await vault1.initialize(
        passphrase: 'minha-senha-correta',
        customPath: bootstrapPath,
      );

      vault1.lock();
      expect(vault1.isUnlocked, isFalse);
      expect(() => vault1.masterKey, throwsStateError);

      // Tentativa com senha incorreta
      final vault2 = KeyVault();
      expect(
        () => vault2.unlock(
          passphrase: 'senha-completamente-errada',
          customPath: bootstrapPath,
        ),
        throwsA(isA<VaultAuthenticationException>()),
      );
      expect(vault2.isUnlocked, isFalse);

      // Desbloqueio com senha correta
      final unlockedKey = await vault2.unlock(
        passphrase: 'minha-senha-correta',
        customPath: bootstrapPath,
      );
      expect(unlockedKey, equals(initialKey));
      expect(vault2.isUnlocked, isTrue);
    });

    test('permite rotação de senha sem alterar a chave mestre interna', () async {
      final vault = KeyVault();
      final originalKey = await vault.initialize(
        passphrase: 'senha-antiga-123',
        customPath: bootstrapPath,
      );

      await vault.changePassphrase(
        oldPassphrase: 'senha-antiga-123',
        newPassphrase: 'senha-nova-reforçada-456',
        customPath: bootstrapPath,
      );

      vault.lock();

      // Antiga não deve funcionar
      expect(
        () => vault.unlock(
          passphrase: 'senha-antiga-123',
          customPath: bootstrapPath,
        ),
        throwsA(isA<VaultAuthenticationException>()),
      );

      // Nova deve recuperar a mesma chave original
      final recoveredKey = await vault.unlock(
        passphrase: 'senha-nova-reforçada-456',
        customPath: bootstrapPath,
      );
      expect(recoveredKey, equals(originalKey));
    });
  });

  group('LocalDatabase & Runner de Migrações (Marco P0-2 / T-DB)', () {
    late Directory tempDir;
    late String dbPath;
    late Uint8List dummyKey;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_db_test_');
      dbPath = '${tempDir.path}/nix_local_test.db';
      dummyKey = Uint8List.fromList(List.generate(32, (i) => i * 7 % 256));
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('aplica migrações 001 e 002 e atinge user_version = 2 com integridade', () async {
      final db = await LocalDatabase.open(
        path: dbPath,
        rawCipherKey: dummyKey,
        customFactory: databaseFactoryFfi,
      );

      final versionRows = await db.rawDatabase.rawQuery('PRAGMA user_version;');
      expect(versionRows.first['user_version'], equals(2));

      final migrations = await db.getAppliedMigrations();
      expect(migrations.length, equals(2));
      expect(migrations[0].version, equals(1));
      expect(migrations[0].checksum, equals(LocalDatabase.checksumMigration001));
      expect(migrations[1].version, equals(2));
      expect(migrations[1].checksum, equals(LocalDatabase.checksumMigration002));

      // Reabrir o banco não deve duplicar migrações
      await db.close();

      final reconnectedDb = await LocalDatabase.open(
        path: dbPath,
        rawCipherKey: dummyKey,
        customFactory: databaseFactoryFfi,
      );

      final reconnectedVersion = await reconnectedDb.rawDatabase.rawQuery('PRAGMA user_version;');
      expect(reconnectedVersion.first['user_version'], equals(2));
      final reconnectedMigrations = await reconnectedDb.getAppliedMigrations();
      expect(reconnectedMigrations.length, equals(2));

      await reconnectedDb.close();
    });

    test('enforça foreign_keys estritas no SQLite', () async {
      final db = await LocalDatabase.open(
        path: dbPath,
        rawCipherKey: dummyKey,
        customFactory: databaseFactoryFfi,
      );

      // Tentar inserir membro em conversa inexistente deve falhar devido a FK
      expect(
        () => db.rawDatabase.insert('members', {
          'conversation_id': 'id-inexistente',
          'member_key': 'key_abc',
          'device_id': 'dev_1',
          'role': 'member',
          'joined_epoch': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );

      await db.close();
    });
  });

  group('Repositórios de Domínio (Persistência Real vs MockData)', () {
    late Directory tempDir;
    late LocalDatabase db;
    late IdentityRepository idRepo;
    late ConversationRepository convRepo;
    late MessageRepository msgRepo;
    late OutboxRepository outboxRepo;
    late PreferencesRepository prefRepo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_repos_test_');
      final dbPath = '${tempDir.path}/nix_repos.db';
      final key = Uint8List.fromList(List.generate(32, (i) => (i + 1) % 256));

      db = await LocalDatabase.open(
        path: dbPath,
        rawCipherKey: key,
        customFactory: databaseFactoryFfi,
      );

      idRepo = IdentityRepository(db);
      convRepo = ConversationRepository(db);
      msgRepo = MessageRepository(db);
      outboxRepo = OutboxRepository(db);
      prefRepo = PreferencesRepository(db);
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('IdentityRepository e Perfil persistem dados reais', () async {
      final edBytes = Uint8List(32);
      final xBytes = Uint8List(32);

      await idRepo.createIdentity(
        id: 'id_local_01',
        publicId: 'NX-9999-ABCD',
        edPublic: edBytes,
        xPublic: xBytes,
        keyRef: 'key_ref_01',
      );

      final identity = await idRepo.getPrimaryIdentity();
      expect(identity, isNotNull);
      expect(identity!['public_id'], equals('NX-9999-ABCD'));

      await idRepo.saveProfile(
        identityId: 'id_local_01',
        displayName: 'Soberano Testador',
        bio: 'Validando migração de MockData para SQLite local.',
      );

      final profile = await idRepo.getProfile('id_local_01');
      expect(profile, isNotNull);
      expect(profile!['display_name'], equals('Soberano Testador'));
    });

    test('ConversationRepository e MessageRepository com busca FTS5', () async {
      final edBytes = Uint8List(32);
      final xBytes = Uint8List(32);

      await idRepo.createIdentity(
        id: 'id_user_02',
        publicId: 'NX-1111-2222',
        edPublic: edBytes,
        xPublic: xBytes,
        keyRef: 'key_ref_02',
      );

      await convRepo.createConversation(
        id: 'conv_alpha',
        kind: 'direct',
        ownerIdentityId: 'id_user_02',
        title: 'Conversa Secreta',
      );

      await msgRepo.insertMessage(
        id: 'msg_01',
        conversationId: 'conv_alpha',
        authorKey: 'auth_key_1',
        deviceId: 'dev_1',
        body: 'O protocolo Nix garante privacidade fail-closed sobre a rede Tor.',
      );

      await msgRepo.insertMessage(
        id: 'msg_02',
        conversationId: 'conv_alpha',
        authorKey: 'auth_key_1',
        deviceId: 'dev_1',
        body: 'Outra mensagem sobre criptografia de disco.',
      );

      final messages = await msgRepo.getMessagesForConversation('conv_alpha');
      expect(messages.length, equals(2));

      // Teste de busca FTS5 (tabela virtual vinculada por triggers)
      final searchResults = await msgRepo.searchMessages('fail-closed');
      expect(searchResults.length, equals(1));
      expect(searchResults.first['id'], equals('msg_01'));
    });

    test('OutboxRepository enfileira envelopes e deduplica recebimentos', () async {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);

      await outboxRepo.enqueue(
        id: 'outbox_env_01',
        destinationMailbox: 'mbx_destination_64hex',
        ciphertext: payload,
        expiresAt: DateTime.now().toUtc().millisecondsSinceEpoch + 600000,
      );

      final pending = await outboxRepo.getPendingEnvelopes();
      expect(pending.length, equals(1));
      expect(pending.first['transport_state'], equals('queued'));

      await outboxRepo.markEnvelopeAccepted('outbox_env_01', 'relay_receipt_uuid_123');
      final remaining = await outboxRepo.getPendingEnvelopes();
      expect(remaining.length, equals(0));

      // Deduplicação de recebimento (inbox_dedup)
      final hash = Uint8List(32);
      expect(await outboxRepo.isDuplicateEnvelope('mbx_1', 'deliv_1'), isFalse);

      await outboxRepo.recordDeduplication(
        mailboxId: 'mbx_1',
        deliveryId: 'deliv_1',
        payloadHash: hash,
        expiresAt: DateTime.now().toUtc().millisecondsSinceEpoch + 600000,
      );

      expect(await outboxRepo.isDuplicateEnvelope('mbx_1', 'deliv_1'), isTrue);
    });

    test('PreferencesRepository armazena opções tipadas em JSON', () async {
      await prefRepo.setOption('themeMode', 'dark');
      await prefRepo.setOption('notificationsEnabled', true);
      await prefRepo.setOption('relays', ['onion1.onion', 'onion2.onion']);

      expect(await prefRepo.getOption('themeMode'), equals('dark'));
      expect(await prefRepo.getOption('notificationsEnabled'), isTrue);
      expect(await prefRepo.getOption('relays'), equals(['onion1.onion', 'onion2.onion']));
    });
  });
}
