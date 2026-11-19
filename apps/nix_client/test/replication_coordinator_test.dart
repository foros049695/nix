import 'dart:convert';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/replication/replication_coordinator.dart';

void main() {
  group('Nix Distributed Replication Coordinator Tests (Fase 20)', () {
    late S3ReplicationAdapter s3Node1;
    late S3ReplicationAdapter s3Node2;
    late IpfsReplicationAdapter ipfsNode;
    late NixReplicationCoordinator coordinator;

    setUp(() {
      s3Node1 = S3ReplicationAdapter(
        name: 'minio-primary',
        endpoint: 'https://s3-node1.nix.internal/bucket',
      );
      s3Node2 = S3ReplicationAdapter(
        name: 'minio-secondary',
        endpoint: 'https://s3-node2.nix.internal/bucket',
      );
      ipfsNode = IpfsReplicationAdapter(
        name: 'kubo-gateway',
        endpoint: 'http://127.0.0.1:5001/api/v0',
      );

      coordinator = NixReplicationCoordinator(
        adapters: [s3Node1, s3Node2, ipfsNode],
      );
    });

    test('Replicação bem-sucedida em múltiplos nós (S3 + IPFS) transiciona para REPLICATED', () async {
      final articleBytes = utf8.encode(jsonEncode({
        'schema': 'nix.archive.article.v1',
        'title': 'Descentralização Real',
        'bodyHtml': '<p>O poder dos sistemas descentralizados.</p>',
      }));
      final hash = std_crypto.sha256.convert(articleBytes).toString();

      final record = await coordinator.replicatePublicObject(
        objectHash: hash,
        kind: 'article',
        canonicalBytes: articleBytes,
      );

      expect(record.status, equals(ReplicationStatus.replicated));
      expect(record.replicaEndpoints.length, equals(3));
      expect(record.replicaEndpoints, contains('https://s3-node1.nix.internal/bucket'));
      expect(record.replicaEndpoints, contains('https://s3-node2.nix.internal/bucket'));
      expect(record.replicaEndpoints, contains('http://127.0.0.1:5001/api/v0'));

      // Recupera e valida integridade a partir de réplica
      final fetched = await coordinator.fetchVerifiedObject(hash);
      expect(fetched, isNotNull);
      expect(fetched, equals(articleBytes));
    });

    test('Barreira de privacidade bloqueia sumariamente rascunhos e dados locais', () async {
      final draftBytes = utf8.encode('Rascunho de artigo secreto que não deve sair do cofre');
      final draftHash = std_crypto.sha256.convert(draftBytes).toString();

      // Tentativa de replicar 'draft'
      expect(
        () => coordinator.replicatePublicObject(
          objectHash: draftHash,
          kind: 'draft',
          canonicalBytes: draftBytes,
        ),
        throwsA(isA<ReplicationPrivacyBarrierException>()),
      );

      // Tentativa de replicar chave privada ou outro dado não canônico
      expect(
        () => coordinator.replicatePublicObject(
          objectHash: draftHash,
          kind: 'private_key',
          canonicalBytes: draftBytes,
        ),
        throwsA(isA<ReplicationPrivacyBarrierException>()),
      );
    });

    test('Validação de integridade rejeita bytes que não coincidem com o hash', () async {
      final validBytes = utf8.encode('Conteúdo legítimo');
      final validHash = std_crypto.sha256.convert(validBytes).toString();

      final corruptedBytes = utf8.encode('Conteúdo fraudado');

      expect(
        () => coordinator.replicatePublicObject(
          objectHash: validHash,
          kind: 'article',
          canonicalBytes: corruptedBytes,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('Tolerância a falhas: nó offline transiciona para PARTIALLY_REPLICATED e DEGRADED', () async {
      final packageBytes = utf8.encode('Pacote de catálogo assinado');
      final hash = std_crypto.sha256.convert(packageBytes).toString();

      // Simula queda de 1 nó (IPFS offline)
      ipfsNode.isOnline = false;

      final record1 = await coordinator.replicatePublicObject(
        objectHash: hash,
        kind: 'catalog_package',
        canonicalBytes: packageBytes,
      );

      // 2 de 3 nós responderam: parcialmente replicado
      expect(record1.status, equals(ReplicationStatus.partiallyReplicated));
      expect(record1.replicaEndpoints.length, equals(2));

      // Simula queda de mais um nó (apenas 1 de 3 ativo)
      s3Node2.isOnline = false;
      final health = await coordinator.checkReplicationHealth(hash);
      expect(health?.status, equals(ReplicationStatus.degraded));

      // Simula queda de todos os nós
      s3Node1.isOnline = false;
      final healthFailed = await coordinator.checkReplicationHealth(hash);
      expect(healthFailed?.status, equals(ReplicationStatus.failed));
    });
  });
}
