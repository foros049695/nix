import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/replication/replication_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('Real S3 & IPFS Replication Adapters & Persistent Outbox Queue (Etapa 5)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_real_rep_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('1. Adaptador S3 Real com assinatura AWS SigV4 sobre HTTP real', () async {
      final storage = <String, List<int>>{};
      String? lastAuthHeader;
      String? lastDateHeader;

      // Servidor HTTP local simulando MinIO / S3
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) async {
        lastAuthHeader = req.headers.value('Authorization');
        lastDateHeader = req.headers.value('x-amz-date');
        final key = req.uri.path.split('/').last;

        if (req.method == 'PUT') {
          final builder = BytesBuilder(copy: false);
          await for (final chunk in req) {
            builder.add(chunk);
          }
          storage[key] = builder.takeBytes();
          req.response.statusCode = 200;
          req.response.close();
        } else if (req.method == 'GET') {
          if (storage.containsKey(key)) {
            req.response.statusCode = 200;
            req.response.add(storage[key]!);
            req.response.close();
          } else {
            req.response.statusCode = 404;
            req.response.close();
          }
        } else if (req.method == 'HEAD') {
          req.response.statusCode = storage.containsKey(key) ? 200 : 404;
          req.response.close();
        } else if (req.method == 'DELETE') {
          storage.remove(key);
          req.response.statusCode = 204;
          req.response.close();
        }
      });

      final adapter = S3ReplicationAdapter(
        name: 'minio-test',
        endpoint: 'http://127.0.0.1:${server.port}',
        bucket: 'nix-public',
        accessKey: 'AKIA_NIX_DEV_TEST',
        secretKey: 'nix_secret_key_sigv4_1234567890',
        region: 'us-east-1',
        requireTls: false, // Permitido em loopback para testes locais
      );

      final payload = utf8.encode('Objeto Canônico Replicado no S3');
      final hash = std_crypto.sha256.convert(payload).toString();

      // PUT (storeObject)
      final stored = await adapter.storeObject(hash: hash, bytes: payload);
      expect(stored, isTrue);
      expect(storage.containsKey(hash), isTrue);
      expect(lastAuthHeader, contains('AWS4-HMAC-SHA256 Credential=AKIA_NIX_DEV_TEST'));
      expect(lastAuthHeader, contains('Signature='));
      expect(lastDateHeader, isNotNull);

      // HEAD (verifyObjectExists)
      final exists = await adapter.verifyObjectExists(hash);
      expect(exists, isTrue);
      final notExists = await adapter.verifyObjectExists('non_existent_hash');
      expect(notExists, isFalse);

      // GET (retrieveObject)
      final retrieved = await adapter.retrieveObject(hash);
      expect(retrieved, isNotNull);
      expect(retrieved, equals(payload));

      // DELETE (deleteObject)
      final deleted = await adapter.deleteObject(hash);
      expect(deleted, isTrue);
      expect(await adapter.verifyObjectExists(hash), isFalse);

      await server.close();
    });

    test('2. Adaptador IPFS Kubo Real com CIDv1 determinístico e RPC API', () async {
      final payload = utf8.encode('Conteúdo público arquivado no IPFS Kubo');
      final shaBytes = std_crypto.sha256.convert(payload).bytes;
      final hash = std_crypto.sha256.convert(payload).toString();

      // Validação de cálculo real de CIDv1
      final expectedCid = IpfsCidV1.computeCidV1Raw(shaBytes);
      expect(expectedCid.startsWith('bafk'), isTrue);
      expect(expectedCid.length, equals(59));

      final ipfsPins = <String>{};
      final ipfsStorage = <String, List<int>>{};

      // Servidor local simulando RPC Kubo (/api/v0/add, /api/v0/cat, /api/v0/pin)
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) async {
        if (req.uri.path == '/api/v0/add') {
          final builder = BytesBuilder(copy: false);
          await for (final chunk in req) {
            builder.add(chunk);
          }
          // Extrai corpo básico do multipart
          ipfsPins.add(expectedCid);
          ipfsStorage[expectedCid] = payload;

          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({
            'Name': hash,
            'Hash': expectedCid,
            'Size': payload.length.toString(),
          }));
          req.response.close();
        } else if (req.uri.path == '/api/v0/cat') {
          final arg = req.uri.queryParameters['arg'];
          if (ipfsStorage.containsKey(arg)) {
            req.response.statusCode = 200;
            req.response.add(ipfsStorage[arg]!);
            req.response.close();
          } else {
            req.response.statusCode = 404;
            req.response.close();
          }
        } else if (req.uri.path == '/api/v0/pin/ls') {
          final arg = req.uri.queryParameters['arg'];
          if (ipfsPins.contains(arg)) {
            req.response.statusCode = 200;
            req.response.write(jsonEncode({
              'Keys': {arg: {'Type': 'recursive'}}
            }));
            req.response.close();
          } else {
            req.response.statusCode = 500;
            req.response.write('Path is not pinned');
            req.response.close();
          }
        } else if (req.uri.path == '/api/v0/pin/rm') {
          final arg = req.uri.queryParameters['arg'];
          ipfsPins.remove(arg);
          req.response.statusCode = 200;
          req.response.write(jsonEncode({'Pins': [arg]}));
          req.response.close();
        }
      });

      final adapter = IpfsReplicationAdapter(
        name: 'kubo-test',
        endpoint: 'http://127.0.0.1:${server.port}',
        isRealHttp: true,
      );

      // storeObject (Add)
      final added = await adapter.storeObject(hash: hash, bytes: payload);
      expect(added, isTrue);
      expect(ipfsPins.contains(expectedCid), isTrue);

      // verifyObjectExists (Pin LS)
      final exists = await adapter.verifyObjectExists(hash);
      expect(exists, isTrue);

      // retrieveObject (Cat)
      final fetched = await adapter.retrieveObject(hash);
      expect(fetched, isNotNull);
      expect(fetched, equals(payload));

      // deleteObject (Pin RM)
      final deleted = await adapter.deleteObject(hash);
      expect(deleted, isTrue);
      expect(await adapter.verifyObjectExists(hash), isFalse);

      await server.close();
    });

    test('3. Fila persistente de replicação SQLite (Outbox Pattern) com retentativas e recuperação pós-reinício', () async {
      final dbPath = '${tempDir.path}/outbox_queue.db';
      var queueRepo = await ReplicationQueueRepository.open(path: dbPath);

      final mockS3 = S3ReplicationAdapter(
        name: 's3-mock',
        endpoint: 'https://s3.nix.mock/bucket',
      );
      final mockIpfs = IpfsReplicationAdapter(
        name: 'ipfs-mock',
        endpoint: 'http://127.0.0.1:5001',
      );

      var coordinator = NixReplicationCoordinator(
        adapters: [mockS3, mockIpfs],
        queueRepo: queueRepo,
      );

      final docBytes = utf8.encode('Artigo crítico que precisa ser persistido na fila');
      final hash = std_crypto.sha256.convert(docBytes).toString();

      // 1. Simula falha temporária (IPFS offline)
      mockIpfs.isOnline = false;

      final record = await coordinator.replicatePublicObject(
        objectHash: hash,
        kind: 'article',
        canonicalBytes: docBytes,
      );

      expect(record.status, equals(ReplicationStatus.partiallyReplicated));
      expect(await queueRepo.countPending(), equals(1));

      final pending = await queueRepo.getPendingItems(forceImmediate: true);
      expect(pending.length, equals(1));
      expect(pending.first.objectHash, equals(hash));
      expect(pending.first.retryCount, equals(1));
      expect(pending.first.nextRetryAt, greaterThan(0));

      // 2. Simula REINICIALIZAÇÃO DO APLICATIVO
      await queueRepo.close();

      // Reabre novo repositório apontando para o mesmo banco SQLite
      queueRepo = await ReplicationQueueRepository.open(path: dbPath);
      expect(await queueRepo.countPending(), equals(1));

      // Nó volta a ficar online
      mockIpfs.isOnline = true;

      coordinator = NixReplicationCoordinator(
        adapters: [mockS3, mockIpfs],
        queueRepo: queueRepo,
      );

      // Recupera e processa fila pendente
      final processed = await coordinator.recoverAndProcessQueue();
      expect(processed, equals(1));

      // Agora que todos os nós responderam, o item deve ser completado e removido do outbox
      expect(await queueRepo.countPending(), equals(0));

      final finalRecord = await queueRepo.getRecord(hash);
      expect(finalRecord, isNotNull);
      expect(finalRecord!.status, equals(ReplicationStatus.replicated));
      expect(finalRecord.replicaEndpoints.length, equals(2));

      await queueRepo.close();
    });

    test('4. Idempotência de uploads e limite de retentativas máximas', () async {
      final queueRepo = await ReplicationQueueRepository.open(inMemory: true);
      final offlineS3 = S3ReplicationAdapter(
        name: 's3-dead',
        endpoint: 'https://s3.dead.internal/bucket',
      )..isOnline = false;

      final coordinator = NixReplicationCoordinator(
        adapters: [offlineS3],
        queueRepo: queueRepo,
      );

      final bytes = utf8.encode('Dado para teste de esgotamento de retentativas');
      final hash = std_crypto.sha256.convert(bytes).toString();

      // Enfileira com maxRetries = 2
      await queueRepo.enqueue(
        objectHash: hash,
        kind: 'article',
        canonicalBytes: bytes,
        maxRetries: 2,
      );

      // Tentativa 1
      await coordinator.processOutbox(forceImmediate: true);
      var pending = await queueRepo.getPendingItems(forceImmediate: true);
      expect(pending.first.retryCount, equals(1));

      // Tentativa 2 (atinge limite)
      await coordinator.processOutbox(forceImmediate: true);

      // Não há mais itens pendentes elegíveis para retry
      expect(await queueRepo.countPending(), equals(0));

      final rec = await queueRepo.getRecord(hash);
      expect(rec?.status, equals(ReplicationStatus.failed));

      await queueRepo.close();
    });
  });
}
