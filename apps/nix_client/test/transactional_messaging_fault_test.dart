import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/database/local_database.dart';
import 'package:nix_client/core/media/voice_note.dart';
import 'package:nix_client/core/messaging/sovereign_messenger.dart';
import 'package:nix_client/core/messaging/scheduled_messages.dart';
import 'package:nix_client/core/models/direct_message.dart';
import 'package:nix_client/core/models/member.dart';
import 'package:nix_client/core/security/key_vault.dart';
import 'package:nix_client/core/security/os_key_storage.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:nix_transport/nix_transport.dart';

/// Relay HTTP cego local e proxy SOCKS5 em loopback para testes de integração reais (Fases 3 e 4).
class _LocalBlindRelayAndSocksHarness {
  HttpServer? _relayServer;
  ServerSocket? _socksServer;
  bool failNextStoreRequest = false;
  bool requireWriteQuota = false;
  static const writeQuota = 'quota-from-local-harness';
  final Map<String, List<Map<String, dynamic>>> _mailboxes = {};
  int _envSeq = 0;

  int get relayPort => _relayServer!.port;
  int get socksPort => _socksServer!.port;

  Future<void> start() async {
    _relayServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _relayServer!.listen(_handleRelayHttp);

    _socksServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _socksServer!.listen(_handleSocksClient);
  }

  Future<void> stop() async {
    await _socksServer?.close();
    await _relayServer?.close(force: true);
  }

  Future<void> _handleRelayHttp(HttpRequest req) async {
    final path = req.uri.path;
    if (req.method == 'GET' && path == '/healthz') {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'status': 'ok'}));
      await req.response.close();
      return;
    }

    if (req.method == 'POST' &&
        path.startsWith('/v1/mailboxes/') &&
        path.endsWith('/envelopes')) {
      if (requireWriteQuota &&
          req.headers.value('X-Nix-Quota-Token') != writeQuota) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }
      if (failNextStoreRequest) {
        req.response.statusCode = HttpStatus.serviceUnavailable;
        req.response.write(jsonEncode({'error': 'relay_unavailable'}));
        await req.response.close();
        return;
      }
      final segments = req.uri.pathSegments;
      final mailboxId = segments[2];
      final bodyStr = await utf8.decoder.bind(req).join();
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;
      final payload = body['payload_b64'] as String;
      _envSeq++;
      final envId = 'relay_env_$_envSeq';
      final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      _mailboxes.putIfAbsent(mailboxId, () => []).add({
        'id': envId,
        'mailbox_id': mailboxId,
        'payload_b64': payload,
        'created_at': nowSec,
        'expires_at': nowSec + 604800,
      });
      req.response.statusCode = HttpStatus.accepted;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'status': 'accepted', 'id': envId}));
      await req.response.close();
      return;
    }

    if (req.method == 'GET' &&
        path.startsWith('/v1/mailboxes/') &&
        path.endsWith('/envelopes')) {
      final segments = req.uri.pathSegments;
      final mailboxId = segments[2];
      final list = _mailboxes[mailboxId] ?? const [];
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'envelopes': list}));
      await req.response.close();
      return;
    }

    if (req.method == 'POST' && path.endsWith('/ack')) {
      final segments = req.uri.pathSegments;
      final mailboxId = segments[2];
      final bodyStr = await utf8.decoder.bind(req).join();
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;
      final ids = (body['ids'] as List<dynamic>).cast<String>().toSet();
      final list = _mailboxes[mailboxId];
      var removed = 0;
      if (list != null) {
        final before = list.length;
        list.removeWhere((e) => ids.contains(e['id']));
        removed = before - list.length;
      }
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'deleted': removed}));
      await req.response.close();
      return;
    }

    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  void _handleSocksClient(Socket client) {
    final buffer = <int>[];
    var stage = 0;
    Socket? upstream;
    StreamSubscription<Uint8List>? sub;

    sub = client.listen(
      (chunk) async {
        if (stage == 2 && upstream != null) {
          upstream!.add(chunk);
          return;
        }
        buffer.addAll(chunk);
        if (stage == 0 && buffer.length >= 3) {
          final nMethods = buffer[1];
          if (buffer.length >= 2 + nMethods) {
            buffer.removeRange(0, 2 + nMethods);
            client.add(const [0x05, 0x00]);
            stage = 1;
          }
        }
        if (stage == 1 && buffer.length >= 5) {
          final atyp = buffer[3];
          int reqLen = 0;
          int targetPort = 0;
          if (atyp == 0x01 && buffer.length >= 10) {
            targetPort = (buffer[8] << 8) | buffer[9];
            reqLen = 10;
          } else if (atyp == 0x03) {
            final domainLen = buffer[4];
            if (buffer.length >= 5 + domainLen + 2) {
              targetPort =
                  (buffer[5 + domainLen] << 8) | buffer[5 + domainLen + 1];
              reqLen = 5 + domainLen + 2;
            }
          }
          if (reqLen > 0) {
            final remaining = buffer.sublist(reqLen);
            buffer.clear();
            try {
              upstream = await Socket.connect(
                InternetAddress.loopbackIPv4,
                targetPort == 80 ? relayPort : targetPort,
              );
              client.add(const [0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 0]);
              stage = 2;
              if (remaining.isNotEmpty) {
                upstream!.add(remaining);
              }
              upstream!.listen(
                (data) => client.add(data),
                onDone: () => client.close(),
                onError: (_) => client.destroy(),
              );
            } catch (_) {
              client.add(const [0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
              await client.close();
            }
          }
        }
      },
      onDone: () {
        upstream?.destroy();
        sub?.cancel();
      },
      onError: (_) {
        upstream?.destroy();
        sub?.cancel();
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fase 4: Consistência Transacional da Criptografia & Injeção de Falhas',
      () {
    late Directory tempDir;
    late _LocalBlindRelayAndSocksHarness harness;
    late LocalDatabase aliceDb;
    late LocalDatabase bobDb;
    late NixIdentity aliceId;
    late NixIdentity bobId;
    late SovereignMessenger aliceMessenger;
    late SovereignMessenger bobMessenger;
    late RelayClient relayClient;
    late MailboxCredentials aliceMailbox;
    late MailboxCredentials bobMailbox;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_phase4_fault_test_');
      harness = _LocalBlindRelayAndSocksHarness();
      await harness.start();

      aliceId = await NixIdentity.generate();
      bobId = await NixIdentity.generate();
      final aliceKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      final bobKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 33));

      aliceDb = await LocalDatabase.open(
        path: '${tempDir.path}/alice.db',
        rawCipherKey: aliceKey,
      );
      bobDb = await LocalDatabase.open(
        path: '${tempDir.path}/bob.db',
        rawCipherKey: bobKey,
      );

      aliceMessenger = SovereignMessenger(
        database: aliceDb,
        identity: aliceId,
        vaultMasterKey: aliceKey,
        storageRootDir: '${tempDir.path}/alice_objects',
      );
      bobMessenger = SovereignMessenger(
        database: bobDb,
        identity: bobId,
        vaultMasterKey: bobKey,
        storageRootDir: '${tempDir.path}/bob_objects',
      );

      await aliceMessenger.identityRepo.createIdentity(
        id: aliceId.publicId,
        publicId: aliceId.publicId,
        edPublic: Uint8List.fromList(aliceId.ed25519PublicKey.bytes),
        xPublic: Uint8List.fromList(aliceId.x25519PublicKey.bytes),
        keyRef: 'vault:alice',
      );
      await aliceMessenger.identityRepo.registerDevice(
        deviceId: 'dev_primary',
        identityId: aliceId.publicId,
        signingPublic: Uint8List.fromList(aliceId.ed25519PublicKey.bytes),
        grant: Uint8List(64),
      );
      await bobMessenger.identityRepo.createIdentity(
        id: bobId.publicId,
        publicId: bobId.publicId,
        edPublic: Uint8List.fromList(bobId.ed25519PublicKey.bytes),
        xPublic: Uint8List.fromList(bobId.x25519PublicKey.bytes),
        keyRef: 'vault:bob',
      );
      await bobMessenger.identityRepo.registerDevice(
        deviceId: 'dev_primary',
        identityId: bobId.publicId,
        signingPublic: Uint8List.fromList(bobId.ed25519PublicKey.bytes),
        grant: Uint8List(64),
      );

      aliceMailbox =
          SovereignMessenger.deriveMailboxCredentials(aliceId.publicId);
      bobMailbox = SovereignMessenger.deriveMailboxCredentials(bobId.publicId);

      relayClient = RelayClient(
        baseUri: Uri.parse(
          'http://gpoun4vo5v5h3cmcfdxtudm3nlzxri3qzjd7fhbvy6oep2ap67g4qvyd.onion:${harness.relayPort}',
        ),
        policy: TransportPolicy(
          mode: TransportMode.torFailClosed,
          socksHost: '127.0.0.1',
          socksPort: harness.socksPort,
        ),
      );

      // Handshake X3DH out-of-band entre Alice e Bob
      final bobSpk = await bobMessenger.provisionSignedPreKey();
      final bobCard = await bobMessenger.exportSignedCardJson(
        displayName: 'Bob',
        mailboxId: bobMailbox.mailboxId,
        preKeyBundle: bobSpk.bundle,
      );
      final aliceSpk = await aliceMessenger.provisionSignedPreKey();
      final aliceCard = await aliceMessenger.exportSignedCardJson(
        displayName: 'Alice',
        mailboxId: aliceMailbox.mailboxId,
        preKeyBundle: aliceSpk.bundle,
      );

      final importedBob =
          await aliceMessenger.importAndVerifyCardJson(rawJson: bobCard);
      await bobMessenger.importAndVerifyCardJson(rawJson: aliceCard);

      await aliceMessenger.establishInitiatorSession(
        conversationId: 'conv_fault_test',
        peerPublicId: bobId.publicId,
        peerDeviceId: 'dev_bob',
        peerBundle: importedBob.signedPreKeyBundle!,
        peerTitle: 'Bob',
        peerMailbox: bobMailbox.mailboxId,
      );
    });

    tearDown(() async {
      await aliceDb.close();
      await bobDb.close();
      await harness.stop();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Nota de voz no limite chega cifrada e cabe no envelope PostgreSQL', () async {
      final pcm = Uint8List(VoiceNote.maximumPcmBytes);
      pcm.setRange(2, 6, [3, 40, 95, 60]);
      final voice = VoiceNote.fromPcm(pcm);
      Future<void> enqueue(bool allowed) => aliceMessenger.enqueueVoiceNote(
        conversationId: 'conv_fault_test',
        senderMailbox: aliceMailbox.mailboxId,
        note: voice,
        mayEnqueue: () => allowed,
      );
      await expectLater(enqueue(false), throwsStateError);
      expect(await aliceMessenger.outboxRepo.getPendingEnvelopes(), isEmpty);
      await enqueue(true);
      final wire = (await aliceMessenger.outboxRepo.getPendingEnvelopes()).single;
      expect((wire['ciphertext'] as List<int>).length, lessThan(1024 * 1024));
      expect((await aliceMessenger.flushOutbox(relayClient: relayClient)).accepted, 1);
      final inbox = await bobMessenger.pollAndCommitInbox(
        creds: bobMailbox, relayClient: relayClient,
      );
      expect(inbox.errors, isEmpty);
      final message = inbox.committed.single;
      expect(message.text, isEmpty);
      expect(message.attachments.single.mimeType, VoiceNote.mimeType);
      final recovered = await bobMessenger.readVoiceNote(message.messageId, 0);
      expect(recovered!.durationMs, 12000);
      expect(recovered.pcm, orderedEquals(pcm));
    });

    test('Agendamento sobrevive a rollback e é enfileirado e entregue uma vez', () async {
      final now = DateTime.utc(2026, 11, 20, 12);
      final due = now.add(const Duration(minutes: 1));
      await aliceMessenger.scheduleDirectMessage(
        conversationId: 'conv_fault_test',
        text: 'entrega cifrada agendada',
        dueAt: due,
        recurrence: MessageRecurrence.once,
        now: now,
      );
      await aliceDb.close();
      aliceDb = await LocalDatabase.open(
        path: '${tempDir.path}/alice.db',
        rawCipherKey: aliceMessenger.vaultMasterKey,
      );
      final reopenedService = SovereignMessenger(
        database: aliceDb,
        identity: aliceId,
        vaultMasterKey: aliceMessenger.vaultMasterKey,
        storageRootDir: aliceMessenger.storageRootDir,
      );
      Future<int> enqueue(DateTime time, {bool fail = false}) =>
          reopenedService.enqueueDueScheduledMessages(
            now: time,
            senderMailbox: aliceMailbox.mailboxId,
            onFaultStage: fail ? (stage) {
              if (stage == MessagingFaultStage.duringOutboxInsert) {
                throw StateError('falha simulada');
              }
            } : null,
          );
      expect(await enqueue(now), 0);
      expect(await reopenedService.listScheduledMessages(), hasLength(1));
      await expectLater(enqueue(due, fail: true), throwsStateError);
      expect(await reopenedService.listScheduledMessages(), hasLength(1));
      expect(await reopenedService.outboxRepo.hasPendingScheduledEnvelopes(), isFalse);
      final concurrent = await Future.wait([enqueue(due), enqueue(due)]);
      expect(concurrent.reduce((a, b) => a + b), 1);
      expect(await reopenedService.listScheduledMessages(), isEmpty);
      expect(await reopenedService.outboxRepo.hasPendingScheduledEnvelopes(), isTrue);

      final blocked = await reopenedService.flushOutbox(
        relayClient: relayClient, maySend: () => false,
      );
      expect(blocked.accepted, 0);
      final sends = await Future.wait([
        reopenedService.flushOutbox(relayClient: relayClient),
        reopenedService.flushOutbox(relayClient: relayClient),
      ]);
      expect(sends.map((result) => result.accepted), [1, 0]);
      expect(await reopenedService.outboxRepo.hasPendingScheduledEnvelopes(), isFalse);
      final inbox = await bobMessenger.pollAndCommitInbox(
        creds: bobMailbox,
        relayClient: relayClient,
      );
      expect(inbox.errors, isEmpty);
      expect(inbox.committed.single.text, 'entrega cifrada agendada');
      expect(inbox.ackedCount, 1);
    });

    test('Recorrência pula ocorrências vencidas e permite cancelar a próxima', () async {
      final now = DateTime.utc(2026, 11, 20, 12);
      final due = now.add(const Duration(minutes: 1));
      final dispatch = due.add(const Duration(days: 3, hours: 1));
      await aliceMessenger.scheduleDirectMessage(
        conversationId: 'conv_fault_test',
        text: 'lembrete diário',
        dueAt: due,
        recurrence: MessageRecurrence.daily,
        now: now,
      );
      expect(await aliceMessenger.enqueueDueScheduledMessages(
        now: dispatch, senderMailbox: aliceMailbox.mailboxId,
      ), 1);
      final next = (await aliceMessenger.listScheduledMessages()).single;
      expect(next.dueAt, due.add(const Duration(days: 4)));
      expect(next.revision, 2);
      await aliceMessenger.cancelScheduledMessage(next);
      expect(await aliceMessenger.enqueueDueScheduledMessages(
        now: next.dueAt, senderMailbox: aliceMailbox.mailboxId,
      ), 0);
      expect(await aliceMessenger.outboxRepo.getPendingEnvelopes(), hasLength(1));
    });

    for (final stage in const [
      MessagingFaultStage.beforeSessionSave,
      MessagingFaultStage.afterSessionSave,
      MessagingFaultStage.afterMessageInsert,
      MessagingFaultStage.duringOutboxInsert,
    ]) {
      test(
          'Rollback atômico quando falha ocorre em ${stage.name}: '
          'nenhum avanço inconsistente do Double Ratchet nem perda silenciosa',
          () async {
        final sessionBefore = await aliceMessenger.sessionRepo
            .getSessionByConversation('conv_fault_test');
        expect(sessionBefore, isNotNull);
        final revBefore = sessionBefore!['revision'] as int;

        await expectLater(
          () => aliceMessenger.enqueueDirectMessage(
            conversationId: 'conv_fault_test',
            destinationMailbox: bobMailbox.mailboxId,
            senderMailbox: aliceMailbox.mailboxId,
            text: 'Mensagem abortada em ${stage.name}',
            onFaultStage: (s) {
              if (s == stage) {
                throw StateError('Injeção de falha simulada em ${stage.name}');
              }
            },
          ),
          throwsStateError,
        );

        // Verifica que nem a sessão avançou, nem restou mensagem órfã ou outbox parcial
        final sessionAfter = await aliceMessenger.sessionRepo
            .getSessionByConversation('conv_fault_test');
        expect(sessionAfter!['revision'], equals(revBefore));
        final msgsAfterFault = await aliceMessenger.messageRepo
            .getMessagesForConversation('conv_fault_test');
        expect(msgsAfterFault, isEmpty);
        final outboxAfterFault =
            await aliceMessenger.outboxRepo.getPendingEnvelopes();
        expect(outboxAfterFault, isEmpty);

        // Envio subsequente sem falha deve decifrar perfeitamente em Bob (ratchet intacto!)
        await aliceMessenger.enqueueDirectMessage(
          conversationId: 'conv_fault_test',
          destinationMailbox: bobMailbox.mailboxId,
          senderMailbox: aliceMailbox.mailboxId,
          text: 'Mensagem íntegra após rollback de ${stage.name}',
        );
        final flushRes =
            await aliceMessenger.flushOutbox(relayClient: relayClient);
        expect(flushRes.accepted, equals(1));

        final pollRes = await bobMessenger.pollAndCommitInbox(
          creds: bobMailbox,
          relayClient: relayClient,
        );
        expect(pollRes.errors, isEmpty);
        expect(pollRes.committed.length, equals(1));
        expect(
          pollRes.committed.first.text,
          equals('Mensagem íntegra após rollback de ${stage.name}'),
        );
      });
    }

    test(
        'Injeção de falha durante envio ao relay (duringRelaySend) e '
        'após aceitação remota antes da confirmação local (afterRemoteAcceptBeforeLocalConfirm)',
        () async {
      final enqueued = await aliceMessenger.enqueueDirectMessage(
        conversationId: 'conv_fault_test',
        destinationMailbox: bobMailbox.mailboxId,
        senderMailbox: aliceMailbox.mailboxId,
        text: 'Mensagem resiliente contra falhas de transporte e pós-aceitação',
      );

      // 1. Falha durante o envio ao relay (duringRelaySend)
      final flushFail1 = await aliceMessenger.flushOutbox(
        relayClient: relayClient,
        retryDelayMs: 0,
        onFaultStage: (s) {
          if (s == MessagingFaultStage.duringRelaySend) {
            throw const SocketException('Queda abrupta do circuito SOCKS5');
          }
        },
      );
      expect(flushFail1.accepted, equals(0));
      expect(flushFail1.failed, equals(1));

      final msgRows1 = await aliceDb.rawDatabase.query(
        'messages',
        where: 'id = ?',
        whereArgs: [enqueued.messageId],
      );
      expect(msgRows1.first['delivery_state'], equals('failed'));

      // 2. Falha após aceitação remota no relay e antes da confirmação local (afterRemoteAcceptBeforeLocalConfirm)
      // O relay já armazenou a primeira cópia do envelope, mas o cliente caiu antes de gravar 'accepted'.
      final flushFail2 = await aliceMessenger.flushOutbox(
        relayClient: relayClient,
        retryDelayMs: 0,
        onFaultStage: (s) {
          if (s == MessagingFaultStage.afterRemoteAcceptBeforeLocalConfirm) {
            throw StateError(
                'Crash simulado após HTTP 202 do relay e antes do commit local');
          }
        },
      );
      expect(flushFail2.accepted, equals(0));
      expect(flushFail2.failed, equals(1));

      // 3. Retentativa limpa: reenvia o mesmo ciphertext ao relay e confirma localmente como 'accepted'
      final flushOk = await aliceMessenger.flushOutbox(
        relayClient: relayClient,
        retryDelayMs: 0,
      );
      expect(flushOk.accepted, equals(1));
      expect(flushOk.failed, equals(0));

      final msgRows2 = await aliceDb.rawDatabase.query(
        'messages',
        where: 'id = ?',
        whereArgs: [enqueued.messageId],
      );
      expect(msgRows2.first['delivery_state'], equals('accepted'));

      // 4. Bob faz polling: existem 2 envelopes no relay com o mesmo msgId/ciphertext,
      // mas Bob deduplica o segundo pré-ratchet sem erro nem duplicação!
      final pollRes = await bobMessenger.pollAndCommitInbox(
        creds: bobMailbox,
        relayClient: relayClient,
      );
      expect(pollRes.errors, isEmpty);
      expect(pollRes.committed.length, equals(1));
      expect(pollRes.skippedDuplicateCount, equals(1));
      expect(
        pollRes.committed.first.text,
        equals(
            'Mensagem resiliente contra falhas de transporte e pós-aceitação'),
      );
    });
  });

  group(
      'Fase 3: Integração Real da Mensageria em Duas Instâncias Independentes de NixState',
      () {
    late Directory tempDir;
    late _LocalBlindRelayAndSocksHarness harness;
    late RelayClient relayClient;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('nix_phase3_two_clients_');
      harness = _LocalBlindRelayAndSocksHarness();
      await harness.start();
      relayClient = RelayClient(
        baseUri: Uri.parse(
          'http://gpoun4vo5v5h3cmcfdxtudm3nlzxri3qzjd7fhbvy6oep2ap67g4qvyd.onion:${harness.relayPort}',
        ),
        policy: TransportPolicy(
          mode: TransportMode.torFailClosed,
          socksHost: '127.0.0.1',
          socksPort: harness.socksPort,
        ),
      );
    });

    tearDown(() async {
      await harness.stop();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    for (final reciprocalInvite in [false, true]) {
      test(
          'Duas instâncias trocam mensagens E2EE (convite recíproco: $reciprocalInvite) '
          'e syncWithRelay, diferenciam Mensagens Salvas e recuperam pendências após reinício',
          () async {
        final aliceVaultPath = '${tempDir.path}/alice_vault.json';
        final aliceDbPath = '${tempDir.path}/alice.db';
        final bobVaultPath = '${tempDir.path}/bob_vault.json';
        final bobDbPath = '${tempDir.path}/bob.db';

        final aliceState = NixState(
          loadMockData: false,
          keyVault: KeyVault(osKeyStorage: InMemoryOsKeyStorage()),
        );
        final bobState = NixState(
          loadMockData: false,
          keyVault: KeyVault(osKeyStorage: InMemoryOsKeyStorage()),
        );

        expect(
          await aliceState.initializeEncryptedDatabase(
            passphrase: 'Alice-Sovereign-Passphrase-2026!',
            customDbPath: aliceDbPath,
            customVaultPath: aliceVaultPath,
          ),
          isTrue,
        );
        expect(
          await bobState.initializeEncryptedDatabase(
            passphrase: 'Bob-Sovereign-Passphrase-2026!',
            customDbPath: bobDbPath,
            customVaultPath: bobVaultPath,
          ),
          isTrue,
        );

        final identities = [
          await NixIdentity.generate(),
          await NixIdentity.generate()
        ]..sort((first, second) => first.publicId.compareTo(second.publicId));
        final aliceIdentity = identities.first;
        final bobIdentity = identities.last;
        MailboxCredentials credentials(NixIdentity identity) =>
            MailboxCredentials(
              mailboxId:
                  SovereignMessenger.deriveMailboxCredentials(identity.publicId)
                      .mailboxId,
              readToken: 'read-from-local-harness',
              writeQuotaToken: _LocalBlindRelayAndSocksHarness.writeQuota,
            );
        harness.requireWriteQuota = reciprocalInvite;
        await aliceState.persistPrimaryIdentity(
          identity: aliceIdentity,
          displayName: 'Alice Soberana',
        );
        await bobState.persistPrimaryIdentity(
          identity: bobIdentity,
          displayName: 'Bob Soberano',
        );

        aliceState.configureRelayTransport(
          relayClient: relayClient,
          mailboxCredentials: credentials(aliceIdentity),
        );
        bobState.configureRelayTransport(
          relayClient: relayClient,
          mailboxCredentials: credentials(bobIdentity),
        );

        // 1. Mensagens Salvas: cofre local, não enfileira na Outbox nem usa relay
        aliceState.openSavedMessages();
        await aliceState
            .sendDirectMessage('Nota privada somente no cofre local');
        expect(aliceState.selectedDm!.isSavedMessages, isTrue);
        final lastSaved = aliceState.selectedDm!.messages.last;
        expect(lastSaved.deliveryState, equals('saved'));
        expect(await aliceState.outboxRepo!.getPendingEnvelopes(), isEmpty);

        // 2. Tentativa de envio remoto SEM sessão criptográfica deve falhar visivelmente (isVerified=false, state='failed')
        const unverifiedThread = DirectMessageThread(
          id: 'conv_unverified_peer',
          peerName: 'Par Sem Handshake',
          peerPublicId: 'NIX-0000-0000-0000-0000',
          statusText: 'Sem sessão',
          isOnline: false,
          isVerified: false,
          trustLevel: NixTrustLevel.level1Red,
          messages: const [],
        );
        aliceState.directMessages.add(unverifiedThread);
        aliceState.selectDirectMessage(unverifiedThread);
        await aliceState.sendDirectMessage('Tentativa sem sessão X3DH');
        final failedNoSessionMsg = aliceState.selectedDm!.messages.last;
        expect(failedNoSessionMsg.deliveryState, equals('failed'));
        expect(failedNoSessionMsg.isVerified, isFalse);
        expect(aliceState.lastMessagingError, isNotNull);

        final bobCardJson = await bobState.exportLocalSignedCardJson();
        final aliceCardJson = await aliceState.exportLocalSignedCardJson();
        final conversationId = reciprocalInvite
            ? SovereignMessenger.invitationConversationId(
                aliceIdentity.publicId, bobIdentity.publicId)
            : 'conv_alice_bob_ui';
        if (reciprocalInvite) {
          // Reemitir o convite antes da primeira mensagem não pode invalidar o anterior.
          await bobState.exportLocalSignedCardJson();
          await bobState.addNewContact(
              publicId: aliceCardJson, nickname: 'Alice local');
          expect(bobState.selectedDm!.hasActiveSession, isFalse);
          expect(bobState.selectedDm!.peerName, 'Alice local');
          await aliceState.addNewContact(publicId: bobCardJson);
          await aliceState.addNewContact(publicId: bobCardJson);
          expect(aliceState.selectedDm!.hasActiveSession, isTrue);
        } else {
          await bobState.importPeerCardOnly(aliceCardJson,
              conversationId: conversationId);
          final thread = await aliceState.importPeerCardAndEstablishSession(
            bobCardJson,
            conversationId: conversationId,
          );
          expect(thread.hasActiveSession, isTrue);
        }

        // 4. Alice envia mensagem pelo fluxo de UI (NixState.sendDirectMessage) -> relay aceita ('accepted')
        await aliceState.sendDirectMessage(
            'Olá Bob! Mensagem enviada pela UI via SovereignMessenger.');
        final aliceSentMsg = aliceState.selectedDm!.messages.last;
        expect(aliceSentMsg.deliveryState, equals('accepted'));
        expect(aliceSentMsg.isVerified, !reciprocalInvite);
        expect(aliceState.lastMessagingError, isNull);

        // 5. Bob sincroniza com o relay (NixState.syncWithRelay) -> recebe e autentica ('delivered')
        final bobSync1 = await bobState.syncWithRelay();
        expect(bobSync1.receivedInbox, equals(1));
        final bobThread = bobState.directMessages.firstWhere(
          (d) => d.id == conversationId,
        );
        expect(bobThread.messages.length, equals(1));
        expect(
          bobThread.messages.first.text,
          equals('Olá Bob! Mensagem enviada pela UI via SovereignMessenger.'),
        );
        expect(bobThread.messages.first.deliveryState, equals('delivered'));
        expect(bobThread.messages.first.isVerified, !reciprocalInvite);

        // 6. Bob responde pela UI para Alice
        bobState.selectDirectMessage(bobThread);
        await bobState
            .sendDirectMessage('Confirmado Alice! Ratchet bidirecional ativo.');
        expect(bobState.selectedDm!.messages.last.deliveryState,
            equals('accepted'));

        final aliceSync1 = await aliceState.syncWithRelay();
        expect(aliceSync1.receivedInbox, equals(1));
        expect(
          aliceState.selectedDm!.messages.last.text,
          equals('Confirmado Alice! Ratchet bidirecional ativo.'),
        );
        expect(aliceState.selectedDm!.messages.last.deliveryState,
            equals('delivered'));

        // 7. Recuperação de mensagens pendentes após falha de relay e reinicialização completa do cliente
        harness.failNextStoreRequest = true;
        await aliceState
            .sendDirectMessage('Mensagem pendente durante queda do relay');
        expect(aliceState.selectedDm!.messages.last.deliveryState,
            equals('failed'));
        expect(aliceState.lastMessagingError, isNotNull);

        // Encerra a instância de Alice e abre uma nova instância independente sobre o mesmo banco/vault
        aliceState.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final aliceRestarted = NixState(
          loadMockData: false,
          keyVault: KeyVault(osKeyStorage: InMemoryOsKeyStorage()),
        );
        await aliceRestarted.unlockWithPassphrase(
          'Alice-Sovereign-Passphrase-2026!',
          customDbPath: aliceDbPath,
          customVaultPath: aliceVaultPath,
        );
        aliceRestarted.configureRelayTransport(
          relayClient: relayClient,
          mailboxCredentials: credentials(aliceIdentity),
        );

        final recoveredThread = aliceRestarted.directMessages.firstWhere(
          (d) => d.id == conversationId,
        );
        expect(
          recoveredThread.messages.any(
            (m) =>
                m.text == 'Mensagem pendente durante queda do relay' &&
                m.deliveryState == 'failed',
          ),
          isTrue,
        );

        // Restaura o relay e sincroniza a instância reiniciada
        harness.failNextStoreRequest = false;
        // Zera next_attempt_at na outbox para retentativa imediata em laboratório
        await aliceRestarted.localDatabase!.rawDatabase.rawUpdate(
          'UPDATE outbox SET next_attempt_at = 0 WHERE transport_state = ?',
          ['failed'],
        );
        final retrySync = await aliceRestarted.syncWithRelay();
        expect(retrySync.acceptedOutbox, equals(1));

        final bobSync2 = await bobState.syncWithRelay();
        expect(bobSync2.receivedInbox, equals(1));
        final bobThreadAfterRecovery = bobState.directMessages.firstWhere(
          (d) => d.id == conversationId,
        );
        expect(
          bobThreadAfterRecovery.messages.last.text,
          equals('Mensagem pendente durante queda do relay'),
        );

        aliceRestarted.dispose();
        bobState.dispose();
      });
    }
  });
}
