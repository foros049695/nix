import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:nix_client/state/nix_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone P0-5: Pipeline de Mensageria End-to-End, Outbox & Dedup', () {
    late Directory tempDir;
    late String dbPath;
    late String vaultPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_e2e_pipeline_test_');
      dbPath = '${tempDir.path}/nix_pipeline_test.db';
      vaultPath = '${tempDir.path}/vault_bootstrap.json';
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('NixState inicializa banco cifrado e persiste mensagens de saída na Outbox e no FTS5', () async {
      final nixState = NixState();

      // 1. Inicializa o cofre de chaves e o banco de dados SQLCipher
      final ok = await nixState.initializeEncryptedDatabase(
        passphrase: 'senha_ultra_segura_soberana_123',
        customDbPath: dbPath,
        customVaultPath: vaultPath,
      );
      expect(ok, isTrue);
      expect(nixState.isDatabaseReady, isTrue);

      // Garante identidade e conversa ativa
      await nixState.identityRepo!.createIdentity(
        id: nixState.userProfile.publicId,
        publicId: nixState.userProfile.publicId,
        edPublic: Uint8List(32),
        xPublic: Uint8List(32),
        keyRef: 'vault:identity_main',
      );

      await nixState.conversationRepo!.createConversation(
        id: 'conv_alice_bob',
        kind: 'direct',
        ownerIdentityId: nixState.userProfile.publicId,
        title: 'Alice & Bob E2EE',
      );

      // 2. Alice envia mensagem soberana
      final sent = await nixState.sendSovereignMessage(
        conversationId: 'conv_alice_bob',
        text: 'Encontrão no ponto seguro às 22h',
        recipientMailbox: 'mailbox_bob_blind_01',
      );
      expect(sent, isTrue);

      // 3. Valida gravação na tabela messages
      final storedMsgs = await nixState.messageRepo!.getMessagesForConversation('conv_alice_bob');
      expect(storedMsgs.length, equals(1));
      expect(storedMsgs.first['body'], equals('Encontrão no ponto seguro às 22h'));
      expect(storedMsgs.first['delivery_state'], equals('queued'));

      // 4. Valida busca textual via FTS5
      final searchResults = await nixState.messageRepo!.searchMessages('ponto seguro');
      expect(searchResults.length, equals(1));
      expect(searchResults.first['id'], equals(storedMsgs.first['id']));

      // 5. Valida enfileiramento na Outbox
      final pending = await nixState.outboxRepo!.getPendingEnvelopes();
      expect(pending.length, equals(1));
      expect(pending.first['destination_mailbox'], equals('mailbox_bob_blind_01'));
      expect(pending.first['transport_state'], equals('queued'));
      expect(pending.first['payload_hash'], isNotNull);

      // 6. Simula aceitação pelo relay
      final outboxId = pending.first['id'] as String;
      await nixState.outboxRepo!.markEnvelopeAccepted(outboxId, 'relay_env_9988');
      final pendingAfter = await nixState.outboxRepo!.getPendingEnvelopes();
      expect(pendingAfter, isEmpty);
    });

    test('processInboundEnvelope comuta atômico no inbox_dedup e rejeita ataques de replay', () async {
      final nixState = NixState();

      await nixState.initializeEncryptedDatabase(
        passphrase: 'senha_teste_inbox_dedup',
        customDbPath: dbPath,
        customVaultPath: vaultPath,
      );

      await nixState.identityRepo!.createIdentity(
        id: nixState.userProfile.publicId,
        publicId: nixState.userProfile.publicId,
        edPublic: Uint8List(32),
        xPublic: Uint8List(32),
        keyRef: 'vault:identity_main',
      );

      await nixState.conversationRepo!.createConversation(
        id: 'mailbox_alice_inbound',
        kind: 'direct',
        ownerIdentityId: nixState.userProfile.publicId,
        title: 'Canal Inbound Alice',
      );

      final sessionKey = SecretKeyData.random(length: 32);
      final rawPlaintext = utf8.encode(jsonEncode({
        'id': 'm_001',
        'sender': 'NIX-BOB-CARD-99',
        'text': 'Confirmo a entrega segura.',
        'ts': DateTime.now().millisecondsSinceEpoch,
      }));

      // Cifra com XChaCha20-Poly1305
      final sealed = await SealedEnvelope.seal(
        key: sessionKey,
        plaintext: rawPlaintext,
      );
      final ciphertext = sealed.encode();

      // 1. Processa envelope de entrada legítimo
      final firstAttempt = await nixState.processInboundEnvelope(
        mailboxId: 'mailbox_alice_inbound',
        deliveryId: 'delivery_uuid_1001',
        ciphertext: ciphertext,
        sessionKey: sessionKey,
      );
      expect(firstAttempt, isTrue);

      // Valida gravação no banco
      final msgs = await nixState.messageRepo!.getMessagesForConversation('mailbox_alice_inbound');
      expect(msgs.length, equals(1));
      expect(msgs.first['body'], equals('Confirmo a entrega segura.'));
      expect(msgs.first['delivery_state'], equals('received'));

      // 2. Simula ataque de Replay (adversário retransmite exatamente o mesmo envelope)
      final replayAttempt = await nixState.processInboundEnvelope(
        mailboxId: 'mailbox_alice_inbound',
        deliveryId: 'delivery_uuid_1001',
        ciphertext: ciphertext,
        sessionKey: sessionKey,
      );
      // Deve ser rejeitado imediatamente pelo gate inbox_dedup
      expect(replayAttempt, isFalse);

      // Nenhuma mensagem duplicada deve ter sido inserida
      final msgsAfterReplay = await nixState.messageRepo!.getMessagesForConversation('mailbox_alice_inbound');
      expect(msgsAfterReplay.length, equals(1));
    });
  });
}
