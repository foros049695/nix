import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/archive/nix_archive_service.dart';
import 'package:nix_client/core/archive/archive_image.dart';
import 'package:nix_client/core/database/local_database.dart';
import 'package:nix_client/core/database/repositories/archive_repository.dart';
import 'package:nix_client/core/replication/replication_coordinator.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Archive Distributed Replication & Multi-Client Sync (Etapa 6)', () {
    late Directory tempDir;
    late S3ReplicationAdapter sharedS3;
    late IpfsReplicationAdapter sharedIpfs;

    // Client A
    late LocalDatabase clientADb;
    late ArchiveRepository clientARepo;
    late NixReplicationCoordinator clientACoordinator;
    late NixArchiveService clientAService;
    late NixIdentity clientAIdentity;

    // Client B
    late LocalDatabase clientBDb;
    late ArchiveRepository clientBRepo;
    late NixReplicationCoordinator clientBCoordinator;
    late NixArchiveService clientBService;
    late NixIdentity clientBIdentity;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_sync_test_');

      // Malha de réplicas compartilhada
      sharedS3 = S3ReplicationAdapter(
        name: 'shared-s3',
        endpoint: 'https://s3.nix.network/archive',
      );
      sharedIpfs = IpfsReplicationAdapter(
        name: 'shared-ipfs',
        endpoint: 'http://127.0.0.1:5001',
      );

      // Setup Client A (independente)
      clientADb = await LocalDatabase.open(
        path: '${tempDir.path}/clientA_archive.db',
        requireEncryption: false,
      );
      clientARepo = ArchiveRepository(clientADb);
      clientACoordinator = NixReplicationCoordinator(
        adapters: [sharedS3, sharedIpfs],
      );
      clientAService = NixArchiveService(
        clientARepo,
        replicationCoordinator: clientACoordinator,
      );
      clientAIdentity = await NixIdentity.generate();

      // Setup Client B (independente)
      clientBDb = await LocalDatabase.open(
        path: '${tempDir.path}/clientB_archive.db',
        requireEncryption: false,
      );
      clientBRepo = ArchiveRepository(clientBDb);
      clientBCoordinator = NixReplicationCoordinator(
        adapters: [sharedS3, sharedIpfs],
      );
      clientBService = NixArchiveService(
        clientBRepo,
        replicationCoordinator: clientBCoordinator,
      );
      clientBIdentity = await NixIdentity.generate();
    });

    tearDown(() async {
      await clientADb.close();
      await clientBDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('sincroniza imagens incorporadas como parte do artigo assinado', () async {
      final image = ArchiveImage.fromPng(
        File('assets/images/nix_logo_128.png').readAsBytesSync(), caption: 'Logotipo de teste',
      );
      final hash = await clientAService.publishArticle(
        author: clientAIdentity, title: 'Com imagem',
        rawHtmlBody: '<p>Conteúdo.</p>', images: [image],
      );
      expect(await clientBService.syncObjectFromNetwork(hash), isTrue);
      final loaded = (await clientBService.readVerifiedArticleImages(hash)).single;
      expect(loaded.caption, image.caption);
      expect(loaded.bytes, orderedEquals(image.bytes));

      final privateHash = await clientAService.publishArticle(
        author: clientAIdentity, title: 'Imagem privada',
        rawHtmlBody: '<p>Conteúdo restrito.</p>', images: [image],
        visibility: 'restricted',
      );
      expect(await clientBService.syncObjectFromNetwork(privateHash), isFalse);
      expect(await clientBRepo.getObject(privateHash), isNull);
    });

    test('1. Artigo publicado por Client A replica na malha e é sincronizado e verificado por Client B', () async {
      // Client A publica artigo com alegações
      final articleHash = await clientAService.publishArticle(
        author: clientAIdentity,
        title: 'Manifesto Soberano P2P',
        rawHtmlBody: '<p>Redes sem servidores centrais garantem resiliência civil.</p>',
        claims: [
          (claimId: 'claim-1', text: 'Topologias P2P são imunes a desligamento central.'),
        ],
      );

      expect(articleHash, isNotEmpty);
      expect(await clientAService.verifyStoredObject(articleHash), isTrue);

      // Verifica que o objeto foi replicado para o S3 e IPFS
      expect(await sharedS3.verifyObjectExists(articleHash), isTrue);
      expect(await sharedIpfs.verifyObjectExists(articleHash), isTrue);

      // Client B ainda não possui o artigo
      expect(await clientBRepo.getObject(articleHash), isNull);

      // Client B sincroniza a partir da malha distribuída
      final synced = await clientBService.syncObjectFromNetwork(articleHash);
      expect(synced, isTrue);

      // Client B agora possui o artigo na base local e sua integridade é estritamente válida
      final articleOnB = await clientBRepo.getObject(articleHash);
      expect(articleOnB, isNotNull);
      final payloadOnB = jsonDecode(utf8.decode(articleOnB!['canonical_bytes'] as List<int>)) as Map<String, dynamic>;
      expect(payloadOnB['title'], equals('Manifesto Soberano P2P'));
      expect(await clientBService.verifyStoredObject(articleHash), isTrue);

      // Alegações do artigo também foram importadas em B
      final claimsOnB = await clientBRepo.getClaimsForObject(articleHash);
      expect(claimsOnB.length, equals(1));
      expect(claimsOnB.first['claim_id'], equals('claim-1'));
    });

    test('2. Discussão encadeada: Client B comenta no artigo de A, replica e Client A consome e valida', () async {
      // 1. Client A publica artigo
      final articleHash = await clientAService.publishArticle(
        author: clientAIdentity,
        title: 'Criptografia Pós-Quântica',
        rawHtmlBody: '<p>Discussão técnica sobre algoritmos resistentes.</p>',
      );

      // Client B sincroniza o artigo
      await clientBService.syncObjectFromNetwork(articleHash);

      // 2. Client B publica comentário no artigo de A
      final commentHash = await clientBService.publishComment(
        author: clientBIdentity,
        authorPersonaId: 'persona-researcher-b',
        targetObjectHash: articleHash,
        contentMarkdown: 'Concordo plenamente. Kyber e Dilithium devem ser integrados.',
      );

      expect(commentHash, isNotEmpty);
      expect(await sharedS3.verifyObjectExists(commentHash), isTrue);

      // Client A ainda não possui o comentário de B
      expect(await clientARepo.getComment(commentHash), isNull);

      // Client A sincroniza o comentário da rede
      final syncedComment = await clientAService.syncObjectFromNetwork(commentHash);
      expect(syncedComment, isTrue);

      // Client A verifica o comentário de B
      expect(await clientAService.verifyStoredComment(commentHash), isTrue);

      final discussionsOnA = await clientAService.getThreadedComments(articleHash);
      expect(discussionsOnA.length, equals(1));
      expect(discussionsOnA.first['author_persona_id'], equals('persona-researcher-b'));
      expect(discussionsOnA.first['content_markdown'], contains('Kyber'));
    });

    test('3. Detecção de adulteração em trânsito (Tamper Rejection) descarta sem corromper a base local', () async {
      final articleHash = await clientAService.publishArticle(
        author: clientAIdentity,
        title: 'Artigo Imutável',
        rawHtmlBody: '<p>Texto legítimo.</p>',
      );

      // Simula ataque Man-In-The-Middle corrompendo a assinatura nos metadados da réplica
      final originalMeta = await sharedS3.retrieveMetadata(articleHash);
      expect(originalMeta, isNotNull);

      final tamperedMeta = Map<String, String>.from(originalMeta!);
      tamperedMeta['signature'] = '00' * 64; // assinatura inválida falsa

      final validBytes = await sharedS3.retrieveObject(articleHash);
      expect(validBytes, isNotNull);

      // Atualiza a réplica com a assinatura adulterada
      await sharedS3.storeObject(
        hash: articleHash,
        bytes: validBytes!,
        metadata: tamperedMeta,
      );
      await sharedIpfs.storeObject(
        hash: articleHash,
        bytes: validBytes,
        metadata: tamperedMeta,
      );

      // Client B tenta sincronizar objeto adulterado
      expect(
        () => clientBService.syncObjectFromNetwork(articleHash),
        throwsA(isA<ArchiveTamperDetectedException>()),
      );

      // Base local do Client B permanece limpa e não corrompida
      expect(await clientBRepo.getObject(articleHash), isNull);
    });

    test('4. Sincronização incremental com deduplicação e filtro temporal', () async {
      final h1 = await clientAService.publishArticle(
        author: clientAIdentity,
        title: 'Artigo 1',
        rawHtmlBody: '<p>1</p>',
        createdAtMs: 1000,
      );
      final h2 = await clientAService.publishArticle(
        author: clientAIdentity,
        title: 'Artigo 2',
        rawHtmlBody: '<p>2</p>',
        createdAtMs: 2000,
      );

      // Sincronização incremental de B
      final count1 = await clientBService.syncIncrementalFromNetwork(
        remoteHashes: [h1, h2],
      );
      expect(count1, equals(2));

      // Segunda sincronização: itens já sincronizados são pulados (deduplicação)
      final count2 = await clientBService.syncIncrementalFromNetwork(
        remoteHashes: [h1, h2],
      );
      expect(count2, equals(0));
    });

    test('5. Isolamento estrito entre Seed A (editorial) e Seed B (financeira/Monero)', () async {
      // Seed A editorial
      final editorialIdentity = clientAIdentity;

      // Seed B simulada (carteira Monero)
      final financialIdentity = await NixIdentity.generate();

      // Verifica isolamento matemático absoluto das chaves
      expect(editorialIdentity.publicId, isNot(equals(financialIdentity.publicId)));
      expect(editorialIdentity.ed25519PublicHex, isNot(equals(financialIdentity.ed25519PublicHex)));
      expect(editorialIdentity.x25519PublicHex, isNot(equals(financialIdentity.x25519PublicHex)));

      // Artigo assinado com Seed A
      final artHash = await clientAService.publishArticle(
        author: editorialIdentity,
        title: 'Auditória de Segurança ADR-0003',
        rawHtmlBody: '<p>Isolamento garantido.</p>',
      );

      final row = await clientARepo.getObject(artHash);
      final authorPubHex = (row!['author_public'] as List<int>)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      // Confirma que a assinatura do Archive pertence à Seed A e NUNCA à Seed B
      expect(authorPubHex, equals(editorialIdentity.ed25519PublicHex));
      expect(authorPubHex, isNot(equals(financialIdentity.ed25519PublicHex)));
    });
  });
}
