import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nix_client/core/database/local_database.dart';
import 'package:nix_client/core/database/repositories/catalog_repository.dart';
import 'package:nix_client/core/database/repositories/media_repository.dart';
import 'package:nix_client/core/media/catalog_database.dart';
import 'package:nix_client/core/media/media_catalog_service.dart';
import 'package:nix_client/core/media/media_index_updater.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Nix Media Index (Offline-First) Tests', () {
    late CatalogDatabase catalogDb;
    late CatalogRepository catalogRepo;
    late LocalDatabase localDb;
    late MediaRepository mediaRepo;
    late MediaCatalogService mediaService;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_media_test_');

      catalogDb = await CatalogDatabase.open(inMemory: true);
      catalogRepo = CatalogRepository(catalogDb);

      localDb = await LocalDatabase.open(
        path: inMemoryDatabasePath,
        requireEncryption: false,
      );
      mediaRepo = MediaRepository(localDb);
      mediaService = MediaCatalogService(mediaRepo, catalogRepo: catalogRepo);
    });

    tearDown(() async {
      await catalogDb.close();
      await localDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Indexa e busca obras em todas as 5 categorias culturais via FTS5', () async {
      final works = [
        CatalogWork(
          id: 'nix:work:movie:1',
          kind: 'movie',
          title: '2001: Uma Odisseia no Espaço',
          originalTitle: '2001: A Space Odyssey',
          creators: 'Stanley Kubrick',
          genres: 'Ficção Científica',
          releaseYear: 1968,
          summary: 'Viagem a Júpiter com o computador HAL 9000.',
          updatedAt: 1000,
        ),
        CatalogWork(
          id: 'nix:work:series:1',
          kind: 'series',
          title: 'Mr. Robot',
          originalTitle: 'Mr. Robot',
          creators: 'Sam Esmail',
          genres: 'Cyberpunk, Suspense, Hacker',
          releaseYear: 2015,
          summary: 'Elliot Alderson luta contra a E Corp.',
          updatedAt: 1000,
        ),
        CatalogWork(
          id: 'nix:work:anime:1',
          kind: 'anime',
          title: 'Serial Experiments Lain',
          originalTitle: 'シリアルエクスペリメンツレイン',
          creators: 'Chiaki J. Konaka',
          genres: 'Cyberpunk, Mistério',
          releaseYear: 1998,
          summary: 'A fronteira entre o mundo real e a Wired.',
          updatedAt: 1000,
        ),
        CatalogWork(
          id: 'nix:work:manga:1',
          kind: 'manga',
          title: 'Akira',
          originalTitle: 'アキラ',
          creators: 'Katsuhiro Otomo',
          genres: 'Cyberpunk, Ação',
          releaseYear: 1982,
          summary: 'Neo-Tóquio e os poderes psíquicos de Tetsuo.',
          updatedAt: 1000,
        ),
        CatalogWork(
          id: 'nix:work:book:1',
          kind: 'book',
          title: '1984',
          originalTitle: 'Nineteen Eighty-Four',
          creators: 'George Orwell',
          genres: 'Distopia, Política',
          releaseYear: 1949,
          summary: 'O Grande Irmão observa tudo na Oceânia.',
          updatedAt: 1000,
        ),
      ];

      await catalogRepo.batchUpsertWorks(works);

      expect(await catalogRepo.getEntryCount(), equals(5));

      // Busca por termo no título
      final searchSpace = await mediaService.searchCatalog(query: 'Odisseia');
      expect(searchSpace.length, equals(1));
      expect(searchSpace.first.id, equals('nix:work:movie:1'));

      final accented = await mediaService.searchCatalog(query: 'Espaço');
      expect(accented.single.id, 'nix:work:movie:1');
      final original = await mediaService.searchCatalog(query: 'シリアル');
      expect(original.single.id, 'nix:work:anime:1');

      // Busca por criador
      final searchKubrick = await mediaService.searchCatalog(query: 'Kubrick');
      expect(searchKubrick.length, equals(1));
      expect(searchKubrick.first.kind, equals('movie'));

      // Busca por prefixo FTS5
      final searchCyber = await mediaService.searchCatalog(query: 'Cyber');
      expect(searchCyber.length, equals(3)); // Mr. Robot, Lain, Akira

      // Busca com filtro por kind
      final searchAnimeCyber = await mediaService.searchCatalog(
        query: 'Cyber',
        kind: 'anime',
      );
      expect(searchAnimeCyber.length, equals(1));
      expect(searchAnimeCyber.first.title, contains('Lain'));

      // Busca por resumo
      final searchOrwell = await mediaService.searchCatalog(query: 'Grande Irmão');
      expect(searchOrwell.length, equals(1));
      expect(searchOrwell.first.kind, equals('book'));
    });

    test('Salva e remove obra no Acervo Pessoal privado (SQLCipher) com isolamento estrito', () async {
      final work = CatalogWork(
        id: 'nix:work:movie:matrix',
        kind: 'movie',
        title: 'Matrix',
        originalTitle: 'The Matrix',
        creators: 'Wachowski',
        genres: 'Cyberpunk, Ação',
        releaseYear: 1999,
        summary: 'Pílula vermelha ou azul.',
        updatedAt: 1000,
      );

      await catalogRepo.upsertWork(work);

      const identityId = 'ident_alice_local';
      const keyRef = 'key_ref_alice';

      // Cria key_material e identidade para satisfazer restrições de integridade relacional
      await localDb.rawDatabase.insert('key_material', {
        'id': keyRef,
        'purpose': 'identity_seed',
        'wrapped_bytes': Uint8List(32),
        'wrapping_key_ref': 'master_kdf',
        'format_version': 1,
        'created_at': 1000,
      });

      await localDb.rawDatabase.insert('identities', {
        'id': identityId,
        'public_id': 'NIX-ALICE-1234',
        'ed_public': Uint8List(32),
        'x_public': Uint8List(32),
        'key_ref': keyRef,
        'created_at': 1000,
      });

      // Salva no acervo pessoal
      await mediaService.saveToAcervo(
        identityId: identityId,
        work: work,
        status: 'watching',
        rating: 95,
        privateNotes: 'Reassistir em 4K no fim de semana.',
      );

      final userAcervo = await mediaService.listUserAcervo(identityId);
      expect(userAcervo.length, equals(1));
      expect(userAcervo.first['media_id'], equals('nix:work:movie:matrix'));
      expect(userAcervo.first['status'], equals('watching'));
      expect(userAcervo.first['rating'], equals(95));
      expect(userAcervo.first['progress_json'], contains('Reassistir em 4K'));

      // Remove do acervo pessoal
      await mediaService.removeFromAcervo(
        identityId: identityId,
        workId: 'nix:work:movie:matrix',
      );

      final userAcervoAfter = await mediaService.listUserAcervo(identityId);
      expect(userAcervoAfter, isEmpty);

      // Obra pública continua no catálogo intacta
      final publicWork = await mediaService.getCatalogWork('nix:work:movie:matrix');
      expect(publicWork, isNotNull);
      expect(publicWork!.title, equals('Matrix'));
    });

    test('Manifesto assinado Ed25519 valida pacote legítimo e rejeita dados adulterados', () async {
      final ed = Ed25519();
      final publisherKey = await ed.newKeyPair();
      final publisherPub = await publisherKey.extractPublicKey();

      final dummyCatalogBytes = List<int>.generate(256, (i) => (i * 7) % 256);

      final manifest = await SignedCatalogManifest.signArtifact(
        signerKeyPair: publisherKey,
        version: 2,
        artifactName: 'nix_catalog_v2.db',
        artifactBytes: dummyCatalogBytes,
        entryCount: 42,
      );

      // Validação do pacote legítimo
      final isValid = await manifest.verifyArtifactBytes(
        dummyCatalogBytes,
        trustedPublisherKey: publisherPub,
      );
      expect(isValid, isTrue);

      // Rejeição de pacote adulterado (1 byte alterado)
      final tamperedBytes = List<int>.from(dummyCatalogBytes);
      tamperedBytes[10] ^= 0xFF;
      final isTamperedValid = await manifest.verifyArtifactBytes(
        tamperedBytes,
        trustedPublisherKey: publisherPub,
      );
      expect(isTamperedValid, isFalse);

      // Rejeição de publicador incorreto / não confiável
      final rogueKey = await ed.newKeyPair();
      final roguePub = await rogueKey.extractPublicKey();
      final isRogueValid = await manifest.verifyArtifactBytes(
        dummyCatalogBytes,
        trustedPublisherKey: roguePub,
      );
      expect(isRogueValid, isFalse);
    });

    test('MediaIndexUpdater aplica pacote assinado, valida integridade e rejeita rollback', () async {
      final ed = Ed25519();
      final publisherKey = await ed.newKeyPair();
      final publisherPub = await publisherKey.extractPublicKey();

      final targetDbPath = '${tempDir.path}/active_catalog.db';

      // Cria base v1 inicial no caminho
      final dbV1 = await CatalogDatabase.open(path: targetDbPath);
      await dbV1.setMeta('version', '1');
      await dbV1.upsertWork(CatalogWork(
        id: 'nix:work:v1',
        kind: 'movie',
        title: 'Filme V1',
        updatedAt: 1,
      ));
      await dbV1.close();

      // Constrói arquivo para pacote v2 válido
      final v2SourcePath = '${tempDir.path}/v2_source.db';
      final dbV2 = await CatalogDatabase.open(path: v2SourcePath);
      await dbV2.setMeta('version', '2');
      await dbV2.upsertWork(CatalogWork(
        id: 'nix:work:v2',
        kind: 'movie',
        title: 'Filme V2 Super',
        updatedAt: 2,
      ));
      await dbV2.close();

      final v2Bytes = await File(v2SourcePath).readAsBytes();
      final manifestV2 = await SignedCatalogManifest.signArtifact(
        signerKeyPair: publisherKey,
        version: 2,
        artifactName: 'active_catalog.db',
        artifactBytes: v2Bytes,
        entryCount: 1,
      );

      // Aplica atualização para v2
      final updatedDb = await MediaIndexUpdater.applySignedCatalogPackage(
        packageBytes: v2Bytes,
        manifest: manifestV2,
        trustedPublisherKey: publisherPub,
        targetDbPath: targetDbPath,
      );

      expect(await updatedDb.getVersion(), equals(2));
      final workV2 = await updatedDb.getWork('nix:work:v2');
      expect(workV2, isNotNull);
      expect(workV2!.title, equals('Filme V2 Super'));
      await updatedDb.close();

      // Tentativa de rollback para v1 ou pacote com mesma versão v2 deve ser rejeitada
      final rollbackManifest = await SignedCatalogManifest.signArtifact(
        signerKeyPair: publisherKey,
        version: 1,
        artifactName: 'active_catalog.db',
        artifactBytes: v2Bytes,
        entryCount: 1,
      );

      expect(
        () => MediaIndexUpdater.applySignedCatalogPackage(
          packageBytes: v2Bytes,
          manifest: rollbackManifest,
          trustedPublisherKey: publisherPub,
          targetDbPath: targetDbPath,
        ),
        throwsA(isA<CatalogRollbackRejectedException>()),
      );
    });

    test('Seed Catalog embutido abre com sucesso e contém 25 obras verificadas nas 5 categorias', () async {
      final seedFile = File('${Directory.current.path}/assets/catalog/seed_catalog.db');
      expect(await seedFile.exists(), isTrue);

      final manifestFile = File(
        '${seedFile.parent.path}/seed_catalog_manifest.json',
      );
      final manifest = SignedCatalogManifest.fromJson(
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>,
      );
      final keyring = CatalogPublisherKeyring(
        trustedKeysHex: {CatalogPublisherKeyring.fixtureTestPublisherKeyHex},
        allowTestFixtureKey: true,
        isProductionMode: false,
      );
      expect(
        await manifest.verifyArtifactBytes(
          await seedFile.readAsBytes(),
          keyring: keyring,
        ),
        isTrue,
      );

      final seedDb = await CatalogDatabase.open(
        path: seedFile.absolute.path,
        readOnly: true,
      );
      final count = await seedDb.getEntryCount();
      expect(count, equals(25));

      final movies = await seedDb.searchWorks(query: '', kind: 'movie');
      expect(movies.length, equals(5));

      final series = await seedDb.searchWorks(query: '', kind: 'series');
      expect(series.length, equals(5));

      final animes = await seedDb.searchWorks(query: '', kind: 'anime');
      expect(animes.length, equals(5));

      final mangas = await seedDb.searchWorks(query: '', kind: 'manga');
      expect(mangas.length, equals(5));

      final books = await seedDb.searchWorks(query: '', kind: 'book');
      expect(books.length, equals(5));

      final matrixWork = await seedDb.searchWorks(query: 'Matrix');
      expect(matrixWork.length, equals(1));
      expect(matrixWork.first.releaseYear, equals(1999));

      await seedDb.close();
    });
  });
}
