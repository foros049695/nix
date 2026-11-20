import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:nix_client/core/database/local_database.dart';
import 'package:nix_client/core/messaging/sovereign_messenger.dart';
import 'package:nix_client/core/security/key_vault.dart';
import 'package:nix_client/core/security/os_key_storage.dart';
import 'package:nix_client/core/security/seed_recovery.dart';
import 'package:nix_transport/nix_transport.dart';

/// Relay HTTP em memória fiel à API `/v1/mailboxes/...` do `services/nix_relay` Go,
/// servida atrás de um proxy SOCKS5 local real para validar Gate 3 ponta a ponta.
class _HarnessRelayAndSocks {
  late final HttpServer _relayHttp;
  late final ServerSocket _socks5;
  final Map<String, List<Map<String, dynamic>>> mailboxes = {};
  final Map<String, String> mailboxTokens = {};
  int envSeq = 0;
  bool failNextPost = false;
  bool shuffleNextFetch = false;

  int get socksPort => _socks5.port;
  int get relayPort => _relayHttp.port;

  Future<void> start() async {
    _relayHttp = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _relayHttp.listen(_handleRelayHttp);

    _socks5 = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _socks5.listen(_handleSocksClient);
  }

  Future<void> stop() async {
    await _socks5.close();
    await _relayHttp.close(force: true);
  }

  Future<void> _handleRelayHttp(HttpRequest req) async {
    final segments = req.uri.pathSegments;
    if (req.uri.path == '/healthz') {
      req.response.statusCode = 200;
      req.response.write('{"status":"ok"}');
      await req.response.close();
      return;
    }

    if (segments.length == 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'mailboxes') {
      final mbox = segments[2];
      final action = segments[3];

      if (action == 'envelopes' && req.method == 'POST') {
        if (failNextPost) {
          failNextPost = false;
          req.response.statusCode = 503;
          req.response.write('{"error":"simulated_relay_outage"}');
          await req.response.close();
          return;
        }
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        final id = 'env_${++envSeq}';
        final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
        final ttl = (body['ttl_seconds'] as num?)?.toInt() ?? 604800;
        mailboxes.putIfAbsent(mbox, () => []).add({
          'id': id,
          'payload_b64': body['payload_b64'],
          'created_at': now,
          'expires_at': now + ttl,
        });
        req.response.statusCode = 201;
        req.response.write(jsonEncode({'id': id}));
        await req.response.close();
        return;
      }

      if (action == 'envelopes' && req.method == 'GET') {
        final auth = req.headers.value('authorization') ?? '';
        final expected = 'Bearer ${mailboxTokens[mbox] ?? ''}';
        if (auth != expected) {
          req.response.statusCode = 403;
          req.response.write('{"error":"forbidden"}');
          await req.response.close();
          return;
        }
        var items = List<Map<String, dynamic>>.from(mailboxes[mbox] ?? const []);
        if (shuffleNextFetch && items.length >= 2) {
          shuffleNextFetch = false;
          items = items.reversed.toList();
        }
        req.response.statusCode = 200;
        req.response.write(jsonEncode({'envelopes': items}));
        await req.response.close();
        return;
      }

      if (action == 'ack' && req.method == 'POST') {
        final auth = req.headers.value('authorization') ?? '';
        final expected = 'Bearer ${mailboxTokens[mbox] ?? ''}';
        if (auth != expected) {
          req.response.statusCode = 403;
          await req.response.close();
          return;
        }
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        final ids = (body['ids'] as List<dynamic>).cast<String>().toSet();
        final list = mailboxes[mbox] ?? [];
        final before = list.length;
        list.removeWhere((e) => ids.contains(e['id']));
        final deleted = before - list.length;
        req.response.statusCode = 200;
        req.response.write(jsonEncode({'deleted': deleted}));
        await req.response.close();
        return;
      }
    }

    req.response.statusCode = 404;
    await req.response.close();
  }

  Future<void> _handleSocksClient(Socket client) async {
    Socket? target;
    try {
      final buf = <int>[];
      final completer = Completer<void>();
      late StreamSubscription<Uint8List> sub;
      int stage = 0; // 0 = greeting, 1 = connect req

      sub = client.listen(
        (chunk) async {
          buf.addAll(chunk);
          if (stage == 0 && buf.length >= 2) {
            final nMethods = buf[1];
            if (buf.length >= 2 + nMethods) {
              buf.removeRange(0, 2 + nMethods);
              stage = 1;
              client.add([0x05, 0x00]); // no auth
            }
          }
          if (stage == 1 && buf.length >= 5) {
            final atyp = buf[3];
            String? host;
            int headerLen = 0;
            if (atyp == 0x01 && buf.length >= 10) {
              host = '${buf[4]}.${buf[5]}.${buf[6]}.${buf[7]}';
              headerLen = 10;
            } else if (atyp == 0x03) {
              final dLen = buf[4];
              if (buf.length >= 5 + dLen + 2) {
                host = utf8.decode(buf.sublist(5, 5 + dLen));
                headerLen = 5 + dLen + 2;
              }
            }
            if (host != null) {
              final port = (buf[headerLen - 2] << 8) | buf[headerLen - 1];
              final leftover = buf.sublist(headerLen);
              stage = 2;
              sub.pause();

              // Roteia destinos `.onion` de teste para o relay local na porta de teste
              final dialHost =
                  host.endsWith('.onion') ? '127.0.0.1' : host;
              target = await Socket.connect(dialHost, port);
              client.add([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 0]);
              if (leftover.isNotEmpty) target!.add(leftover);

              sub.onData((more) => target?.add(more));
              sub.onDone(() => target?.close());
              sub.resume();
              target!.listen(client.add, onDone: () => client.close());
              if (!completer.isCompleted) completer.complete();
            }
          }
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future;
    } catch (_) {
      await target?.close();
      await client.close();
    }
  }
}

Uint8List _buildPngWithMetadataChunks() {
  // IHDR mínimo de 13 bytes + tEXt secreto + eXIf simulado + IDAT falso + IEND
  List<int> chunk(String type, List<int> data) {
    final bd = ByteData(4)..setUint32(0, data.length, Endian.big);
    return [
      ...bd.buffer.asUint8List(),
      ...type.codeUnits,
      ...data,
      0x00, 0x00, 0x00, 0x00, // CRC espaço teste do stripper estrutural
    ];
  }

  return Uint8List.fromList([
    137, 80, 78, 71, 13, 10, 26, 10,
    ...chunk('IHDR', List<int>.filled(13, 1)),
    ...chunk('tEXt', utf8.encode('Author=RealSecretGPSLocation')),
    ...chunk('eXIf', utf8.encode('GPS=23.5505S,46.6333W')),
    ...chunk('IDAT', List<int>.generate(256, (i) => i & 0xFF)),
    ...chunk('IEND', const []),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Gate 3 E2EE: Alice & Bob via SOCKS5, Double Ratchet, Dedup, Chunks & Grupos', () {
    late Directory tempDir;
    late _HarnessRelayAndSocks harness;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_gate3_');
      harness = _HarnessRelayAndSocks();
      await harness.start();
      harness.mailboxTokens['mbox_alice'] = 'tok_alice_read';
      harness.mailboxTokens['mbox_bob'] = 'tok_bob_read';
    });

    tearDown(() async {
      await harness.stop();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Fluxo completo: OOB Card, key change warning, Double Ratchet out-of-order, commit-before-ACK, retry, chunks, grupos e TTL', () async {
      final aliceVault = KeyVault(osKeyStorage: InMemoryOsKeyStorage());
      final aliceKey = await aliceVault.initialize(
        passphrase: 'alice-strong-passphrase',
        customPath: '${tempDir.path}/alice_vault.json',
      );
      final aliceDb = await LocalDatabase.open(
        path: '${tempDir.path}/alice.db',
        rawCipherKey: aliceKey,
      );
      final aliceId = await SeedRecoveryManager.deriveIdentityFromMnemonic(
        SeedRecoveryManager.generateMnemonic(),
      );
      final aliceMessenger = SovereignMessenger(
        database: aliceDb,
        identity: aliceId,
        vaultMasterKey: aliceKey,
        storageRootDir: '${tempDir.path}/alice_storage',
      );
      await aliceMessenger.keyMaterialRepo.storeKeyMaterial(
        id: 'vault:identity_main',
        purpose: 'identity_seed_a',
        wrappedBytes: Uint8List.fromList([1]),
        wrappingKeyRef: 'keyvault:master',
      );
      await aliceMessenger.database.rawDatabase.insert('identities', {
        'id': aliceId.publicId,
        'public_id': aliceId.publicId,
        'ed_public': aliceId.ed25519PublicKey.bytes,
        'x_public': aliceId.x25519PublicKey.bytes,
        'key_ref': 'vault:identity_main',
        'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      });
      await aliceMessenger.database.rawDatabase.insert('devices', {
        'id': 'dev_primary',
        'identity_id': aliceId.publicId,
        'signing_public': aliceId.ed25519PublicKey.bytes,
        'grant': Uint8List(64),
        'added_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      });

      final bobVault = KeyVault(osKeyStorage: InMemoryOsKeyStorage());
      final bobKey = await bobVault.initialize(
        passphrase: 'bob-strong-passphrase',
        customPath: '${tempDir.path}/bob_vault.json',
      );
      final bobDb = await LocalDatabase.open(
        path: '${tempDir.path}/bob.db',
        rawCipherKey: bobKey,
      );
      final bobId = await SeedRecoveryManager.deriveIdentityFromMnemonic(
        SeedRecoveryManager.generateMnemonic(),
      );
      final bobMessenger = SovereignMessenger(
        database: bobDb,
        identity: bobId,
        vaultMasterKey: bobKey,
        storageRootDir: '${tempDir.path}/bob_storage',
      );
      await bobMessenger.keyMaterialRepo.storeKeyMaterial(
        id: 'vault:identity_main',
        purpose: 'identity_seed_a',
        wrappedBytes: Uint8List.fromList([1]),
        wrappingKeyRef: 'keyvault:master',
      );
      await bobMessenger.database.rawDatabase.insert('identities', {
        'id': bobId.publicId,
        'public_id': bobId.publicId,
        'ed_public': bobId.ed25519PublicKey.bytes,
        'x_public': bobId.x25519PublicKey.bytes,
        'key_ref': 'vault:identity_main',
        'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      });
      await bobMessenger.database.rawDatabase.insert('devices', {
        'id': 'dev_primary',
        'identity_id': bobId.publicId,
        'signing_public': bobId.ed25519PublicKey.bytes,
        'grant': Uint8List(64),
        'added_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      });

      final aliceSpk = await aliceMessenger.provisionSignedPreKey();
      final bobSpk = await bobMessenger.provisionSignedPreKey();

      // 1. Troca OOB de Card IDs assinados Ed25519 + detecção de mudança de chave
      final aliceCardJson = await aliceMessenger.exportSignedCardJson(
        displayName: 'Alice',
        mailboxId: 'mbox_alice',
        preKeyBundle: aliceSpk.bundle,
      );
      final bobCardJson = await bobMessenger.exportSignedCardJson(
        displayName: 'Bob',
        mailboxId: 'mbox_bob',
        preKeyBundle: bobSpk.bundle,
      );

      final aliceImportsBob = await aliceMessenger.importAndVerifyCardJson(
        rawJson: bobCardJson,
      );
      expect(aliceImportsBob.status, equals(CardImportStatus.importedVerified));

      final bobImportsAlice = await bobMessenger.importAndVerifyCardJson(
        rawJson: aliceCardJson,
      );
      expect(bobImportsAlice.status, equals(CardImportStatus.importedVerified));

      // Se atacante tentar substituir Card ID com mesmo publicId mas outra X25519, gera alerta de mudança!
      final fakeBobMap = jsonDecode(bobCardJson) as Map<String, dynamic>;
      final spoofedIdentity = await SeedRecoveryManager.deriveIdentityFromMnemonic(
        SeedRecoveryManager.generateMnemonic(),
      );
      final fakePayload = Map<String, dynamic>.from(fakeBobMap['payload'] as Map);
      fakePayload['x25519'] = List.filled(32, 0xAA)
          .map((e) => e.toRadixString(16).padLeft(2, '0'))
          .join();
      fakePayload['ed25519'] = spoofedIdentity.ed25519PublicHex;
      fakePayload['publicId'] = bobId.publicId;
      // mesmo assinando com chave do impostor, issuer diverge ou chave mudou -> rejeição ou alerta
      final impostorRecord = await aliceMessenger.importAndVerifyCardJson(
        rawJson: jsonEncode({
          ...fakeBobMap,
          'issuer': spoofedIdentity.ed25519PublicHex,
          'payload': fakePayload,
        }),
      );
      expect(impostorRecord.status, equals(CardImportStatus.invalidSignatureOrExpired));

      // Testa mudança real com assinatura consistente mas publicId existente alterado no DB -> keyChangedWarning
      final legitOtherId = await SeedRecoveryManager.deriveIdentityFromMnemonic(
        SeedRecoveryManager.generateMnemonic(),
      );
      await bobMessenger.contactRepo.upsertContact(
        id: legitOtherId.publicId,
        edPublic: Uint8List(32),
        xPublic: Uint8List(32),
        fingerprint: legitOtherId.publicId,
        displayName: 'Contato Anterior',
        verification: 'verified',
      );
      final legitOtherMessenger = SovereignMessenger(
        database: bobDb,
        identity: legitOtherId,
        vaultMasterKey: bobKey,
      );
      final selfBundle = await SignedPreKeyBundle.create(
        owner: legitOtherId,
        signedPreKeyPair: await X25519().newKeyPair(),
      );
      final validChangedCard = await legitOtherMessenger.exportSignedCardJson(
        displayName: 'Carol Rotacionada',
        mailboxId: 'mbox_carol',
        preKeyBundle: selfBundle,
      );
      final keyChangeRes = await bobMessenger.importAndVerifyCardJson(
        rawJson: validChangedCard,
      );
      expect(keyChangeRes.status, equals(CardImportStatus.keyChangedWarning));
      expect((await bobMessenger.contactRepo.getContact(legitOtherId.publicId))!['verification'], 'changed');

      // 2. Transporte Tor-mode (SOCKS5 obrigatório apontando para .onion de teste)
      final onionUri = Uri.parse(
        'http://xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.onion:${harness.relayPort}',
      );
      final torClient = RelayClient(
        baseUri: onionUri,
        policy: TransportPolicy(
          mode: TransportMode.torFailClosed,
          socksPort: harness.socksPort,
        ),
      );
      expect(await torClient.checkHealth(), isTrue);

      // 3. Sessão X3DH + Double Ratchet: Alice (Offline Bob) + Outbox retry após 503
      const convId = 'conv_alice_bob_e2ee';
      await aliceMessenger.establishInitiatorSession(
        conversationId: convId,
        peerPublicId: bobId.publicId,
        peerDeviceId: 'dev_primary',
        peerBundle: aliceImportsBob.signedPreKeyBundle!,
        peerTitle: 'Bob',
      );

      // Prepara anexo multi-chunk + PNG com EXIF para envio E2EE
      final rawPng = _buildPngWithMetadataChunks();
      final pngAscii = utf8.decode(rawPng, allowMalformed: true);
      expect(pngAscii, contains('RealSecretGPSLocation'));

      final attachment = await aliceMessenger.prepareEncryptedAttachment(
        fileName: 'foto_campo.png',
        mimeType: 'image/png',
        rawBytes: rawPng,
        chunkSize: 120, // força múltiplos chunks
      );
      expect(attachment.chunkCiphertextsBase64.length, greaterThan(1));

      await aliceMessenger.enqueueDirectMessage(
        conversationId: convId,
        destinationMailbox: 'mbox_bob',
        senderMailbox: 'mbox_alice',
        text: 'Relatorio de campo via Onion',
        ephemeralTtlSeconds: 2,
        attachments: [attachment],
      );

      // Simula falha transitória 503 no relay e depois sucesso determinístico na retentativa
      harness.failNextPost = true;
      final firstFlush = await aliceMessenger.flushOutbox(
        relayClient: torClient,
        retryDelayMs: 0,
      );
      expect(firstFlush.accepted, 0);
      expect(firstFlush.failed, 1);

      final secondFlush = await aliceMessenger.flushOutbox(
        relayClient: torClient,
      );
      expect(secondFlush.accepted, 1);
      expect(secondFlush.failed, 0);

      // 4. Bob busca no relay simulando queda ANTES do ACK (commit-before-ACK)
      const bobCreds = MailboxCredentials(
        mailboxId: 'mbox_bob',
        readToken: 'tok_bob_read',
      );
      final crashPoll = await bobMessenger.pollAndCommitInbox(
        creds: bobCreds,
        relayClient: torClient,
        simulateCrashBeforeAck: true,
      );
      expect(crashPoll.committed.length, 1);
      expect(crashPoll.ackedCount, 0);
      expect(crashPoll.committed.first.text, 'Relatorio de campo via Onion');
      expect(crashPoll.committed.first.expiresAtMs, isNotNull);

      // Valida reassembly & zero EXIF na ponta do Bob!
      final reassembledPng = await bobMessenger.decryptAndReassembleAttachment(
        crashPoll.committed.first.attachments.single,
      );
      final cleanAscii = utf8.decode(reassembledPng, allowMalformed: true);
      expect(cleanAscii, isNot(contains('RealSecretGPSLocation')));
      expect(cleanAscii, isNot(contains('23.5505S')));

      final receivedId = crashPoll.committed.first.messageId;
      final preview = await bobMessenger.readImageAttachment(receivedId, 0);
      expect(preview, orderedEquals(reassembledPng));
      final attachmentRow = (await bobMessenger.objectChunkRepo
              .getAttachmentsForMessage(receivedId))
          .single;
      final sealedManifest = await File(attachmentRow['encrypted_path'] as String).readAsBytes();
      expect(String.fromCharCodes(sealedManifest.take(5)), 'NXAM1');
      expect(utf8.decode(sealedManifest, allowMalformed: true), isNot(contains('objectKey')));

      // Replay / nova consulta pós-queda: DB já tem inbox_dedup, não duplica e agora faz ACK
      final recoveryPoll = await bobMessenger.pollAndCommitInbox(
        creds: bobCreds,
        relayClient: torClient,
      );
      expect(recoveryPoll.committed, isEmpty);
      expect(recoveryPoll.skippedDuplicateCount, 1);
      expect(recoveryPoll.ackedCount, 1);

      // 5. Bob responde para Alice (avanço real do DH Ratchet)
      await bobMessenger.enqueueDirectMessage(
        conversationId: convId,
        destinationMailbox: 'mbox_alice',
        senderMailbox: 'mbox_bob',
        text: 'Confirmado Alice, chave avançada!',
      );
      await bobMessenger.flushOutbox(relayClient: torClient);

      const aliceCreds = MailboxCredentials(
        mailboxId: 'mbox_alice',
        readToken: 'tok_alice_read',
      );
      final alicePoll = await aliceMessenger.pollAndCommitInbox(
        creds: aliceCreds,
        relayClient: torClient,
      );
      expect(alicePoll.committed.length, 1);
      expect(alicePoll.committed.first.text, 'Confirmado Alice, chave avançada!');

      // 6. Entrega fora de ordem (3 mensagens embaralhadas no relay)
      await aliceMessenger.enqueueDirectMessage(
        conversationId: convId,
        destinationMailbox: 'mbox_bob',
        senderMailbox: 'mbox_alice',
        text: 'Ordem-1',
      );
      await aliceMessenger.enqueueDirectMessage(
        conversationId: convId,
        destinationMailbox: 'mbox_bob',
        senderMailbox: 'mbox_alice',
        text: 'Ordem-2',
      );
      await aliceMessenger.enqueueDirectMessage(
        conversationId: convId,
        destinationMailbox: 'mbox_bob',
        senderMailbox: 'mbox_alice',
        text: 'Ordem-3',
      );
      await aliceMessenger.flushOutbox(relayClient: torClient);

      harness.shuffleNextFetch = true;
      final outOfOrderPoll = await bobMessenger.pollAndCommitInbox(
        creds: bobCreds,
        relayClient: torClient,
      );
      expect(outOfOrderPoll.errors, isEmpty);
      expect(
        outOfOrderPoll.committed.map((m) => m.text).toSet(),
        equals({'Ordem-3', 'Ordem-2', 'Ordem-1'}),
      );

      // 7. Sincronismo de expiração efêmera (TTL 2s nas duas pontas)
      final futureClock =
          DateTime.now().toUtc().millisecondsSinceEpoch + 10000;
      final aliceSwept = await aliceMessenger.messageRepo.sweepExpiredMessages(
        nowMs: futureClock,
      );
      final bobSwept = await bobMessenger.messageRepo.sweepExpiredMessages(
        nowMs: futureClock,
      );
      expect(aliceSwept, 1);
      expect(bobSwept, 1);

      // O mesmo envelope da outbox chega ao banco por BLE, sem relay.
      final nearby = await aliceMessenger.enqueueDirectMessage(
        conversationId: convId,
        destinationMailbox: bobCreds.mailboxId,
        senderMailbox: aliceCreds.mailboxId,
        text: 'Mensagem de proximidade',
      );
      final rows = await aliceMessenger.outboxRepo.getPendingEnvelopes();
      final row = rows.singleWhere((r) => r['id'] == nearby.outboxId);
      final expiry = row['expires_at'] as int;
      final sealed = await aliceMessenger.sealNearbyDelivery(
        peerPublicId: bobId.publicId,
        mailboxId: bobCreds.mailboxId,
        deliveryId: nearby.outboxId,
        wireBytes: row['ciphertext'] as Uint8List,
        expiresAtMs: expiry,
      );
      expect(
        utf8.decode(sealed, allowMalformed: true),
        isNot(contains(aliceId.publicId)),
      );
      final senderMesh = BluetoothMeshManager(localCardId: aliceId.publicId);
      final receiverMesh = BluetoothMeshManager(localCardId: bobId.publicId);
      addTearDown(senderMesh.dispose);
      addTearDown(receiverMesh.dispose);
      senderMesh.setMeshEnabled(true);
      receiverMesh.setMeshEnabled(true);
      senderMesh.registerDiscoveredPeer(
        deviceAddress: 'bob',
        peerCardId: bobId.publicId,
        rssi: -42,
      );
      senderMesh.onTransmitPacket = (_, bytes) async {
        receiverMesh.handleIncomingPacket('alice', bytes);
        return true;
      };
      final frameFuture = receiverMesh.onEnvelopeReceived.first;
      expect(
        await senderMesh.broadcastEnvelope(
          recipientCardId: bobCreds.mailboxId,
          payload: sealed,
          targetDeviceAddress: 'bob',
          deliveryId: nearby.outboxId,
          expiresAtMs: expiry,
        ),
        1,
      );
      final frame = await frameFuture;
      Future<PollCommitResult> commitFrame(int expiresAtMs) =>
          bobMessenger.commitNearbyDelivery(
            mailboxId: frame['destinationMailbox'] as String,
            deliveryId: frame['deliveryId'] as String,
            ciphertext: frame['ciphertext'] as Uint8List,
            expiresAtMs: expiresAtMs,
          );
      await expectLater(commitFrame(expiry + 1), throwsA(isA<Exception>()));
      final receivedNearby = await commitFrame(frame['expiresAt'] as int);
      expect(receivedNearby.errors, isEmpty);
      expect(receivedNearby.committed.single.text, 'Mensagem de proximidade');
      expect((await commitFrame(expiry)).skippedDuplicateCount, 1);

      // 8. Grupos E2EE Sender Keys + Rotação de Época ao remover membro
      final carolVault = KeyVault(osKeyStorage: InMemoryOsKeyStorage());
      final carolKey = await carolVault.initialize(
        passphrase: 'carol-strong-pass',
        customPath: '${tempDir.path}/carol_vault.json',
      );
      final carolDb = await LocalDatabase.open(
        path: '${tempDir.path}/carol.db',
        rawCipherKey: carolKey,
      );
      final carolId = await SeedRecoveryManager.deriveIdentityFromMnemonic(
        SeedRecoveryManager.generateMnemonic(),
      );
      final carolMessenger = SovereignMessenger(
        database: carolDb,
        identity: carolId,
        vaultMasterKey: carolKey,
      );

      const groupId = 'grp_celula_norte';
      final members = [
        (publicId: aliceId.publicId, x25519PublicKey: aliceId.x25519PublicKey),
        (publicId: bobId.publicId, x25519PublicKey: bobId.x25519PublicKey),
        (publicId: carolId.publicId, x25519PublicKey: carolId.x25519PublicKey),
      ];
      final ep1 = await aliceMessenger.createOrRotateGroupEpoch(
        groupId: groupId,
        title: 'Celula Norte',
        activeMembers: members,
      );
      expect(ep1.epoch, 1);

      await bobMessenger.acceptGroupSenderKeyDistribution(
        groupId: groupId,
        expectedEpoch: 1,
        senderPublicId: aliceId.publicId,
        recipientIdentity: bobId,
        distributionEnvelope: ep1.keyDistributionEnvelopes[bobId.publicId]!,
      );
      await carolMessenger.acceptGroupSenderKeyDistribution(
        groupId: groupId,
        expectedEpoch: 1,
        senderPublicId: aliceId.publicId,
        recipientIdentity: carolId,
        distributionEnvelope: ep1.keyDistributionEnvelopes[carolId.publicId]!,
      );

      final grpMsg1 = await aliceMessenger.encryptGroupMessage(
        groupId: groupId,
        epoch: 1,
        text: 'Briefing epoca 1',
      );
      expect(await bobMessenger.decryptGroupMessage(grpMsg1), 'Briefing epoca 1');
      expect(await carolMessenger.decryptGroupMessage(grpMsg1), 'Briefing epoca 1');

      // Remove Carol e rotaciona para Época 2
      final ep2 = await aliceMessenger.createOrRotateGroupEpoch(
        groupId: groupId,
        title: 'Celula Norte',
        activeMembers: members,
        removeMemberPublicId: carolId.publicId,
      );
      expect(ep2.epoch, 2);
      expect(ep2.keyDistributionEnvelopes.containsKey(carolId.publicId), isFalse);

      await bobMessenger.acceptGroupSenderKeyDistribution(
        groupId: groupId,
        expectedEpoch: 2,
        senderPublicId: aliceId.publicId,
        recipientIdentity: bobId,
        distributionEnvelope: ep2.keyDistributionEnvelopes[bobId.publicId]!,
      );

      final grpMsg2 = await aliceMessenger.encryptGroupMessage(
        groupId: groupId,
        epoch: 2,
        text: 'Segredo pos-remocao epoca 2',
      );
      expect(await bobMessenger.decryptGroupMessage(grpMsg2), 'Segredo pos-remocao epoca 2');
      await expectLater(
        carolMessenger.decryptGroupMessage(grpMsg2),
        throwsA(isA<StateError>()),
      );

      await aliceDb.close();
      await bobDb.close();
      await carolDb.close();
    });
  });
}
