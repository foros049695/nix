import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/media/catalog_database.dart';
import 'package:nix_client/core/media/media_index_updater.dart';
import 'package:nix_transport/nix_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('MediaIndexUpdater & CatalogUpdateManager (Etapa 4)', () {
    late Directory tempDir;
    late String catalogPath;
    late String historyPath;
    late KeyPair validKeyPair;
    late KeyPair rogueKeyPair;
    late String validPubHex;
    late String roguePubHex;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_updater_test_');
      catalogPath = '${tempDir.path}/test_catalog.db';
      historyPath = '${tempDir.path}/catalog_history.json';

      final ed = Ed25519();
      validKeyPair = await ed.newKeyPair();
      rogueKeyPair = await ed.newKeyPair();

      final validPub = await validKeyPair.extractPublicKey() as SimplePublicKey;
      final roguePub = await rogueKeyPair.extractPublicKey() as SimplePublicKey;
      validPubHex = SignedCatalogManifest.bytesToHex(validPub.bytes);
      roguePubHex = SignedCatalogManifest.bytesToHex(roguePub.bytes);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Future<List<int>> createValidCatalogBytes({required int version, required int count}) async {
      final dbPath = '${tempDir.path}/temp_build_v$version.db';
      final db = await CatalogDatabase.open(path: dbPath);
      await db.rawDatabase.execute(
        "INSERT OR REPLACE INTO catalog_meta (key, value) VALUES ('version', '$version');",
      );
      for (int i = 0; i < count; i++) {
        await db.rawDatabase.execute(
          "INSERT OR REPLACE INTO catalog_works (id, kind, title, updated_at) "
          "VALUES ('nix:work:movie:$i', 'movie', 'Title $i', 1000);",
        );
      }
      await db.close();
      final bytes = await File(dbPath).readAsBytes();
      await File(dbPath).delete();
      return bytes;
    }

    test('1. Consulta versão instalada (0 quando ausente, versão gravada quando existente)', () async {
      final mgr = CatalogUpdateManager(
        targetDbPath: catalogPath,
        historyFilePath: historyPath,
        transportPolicy: const TransportPolicy(mode: TransportMode.loopbackTest),
      );

      expect(await mgr.getInstalledVersion(), equals(0));

      final v1Bytes = await createValidCatalogBytes(version: 1, count: 5);
      await File(catalogPath).writeAsBytes(v1Bytes);

      expect(await mgr.getInstalledVersion(), equals(1));
    });

    test('2. Política Tor Fail-Closed bloqueia destinos clearnet sem vazamento de rede', () async {
      final mgr = CatalogUpdateManager(
        targetDbPath: catalogPath,
        historyFilePath: historyPath,
        transportPolicy: const TransportPolicy(mode: TransportMode.torFailClosed),
      );

      // Tenta consultar URL clearnet
      final clearnetUri = Uri.parse('http://example.com/manifest.json');
      expect(
        () => mgr.checkForUpdate(manifestUri: clearnetUri),
        throwsA(isA<TransportBlockedException>()),
      );
    });

    test('3. Rejeita publicador revogado ou desconhecido no checkForUpdate', () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      final v2Bytes = await createValidCatalogBytes(version: 2, count: 10);

      // Assinado por rogue key
      final rogueManifest = await SignedCatalogManifest.signArtifact(
        signerKeyPair: rogueKeyPair,
        version: 2,
        artifactName: 'test_catalog.db',
        artifactBytes: v2Bytes,
        entryCount: 10,
      );

      server.listen((req) {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(rogueManifest.toJson()));
        req.response.close();
      });

      final keyring = CatalogPublisherKeyring(
        trustedKeysHex: {validPubHex},
        revokedKeysHex: {roguePubHex},
      );

      final mgr = CatalogUpdateManager(
        keyring: keyring,
        targetDbPath: catalogPath,
        historyFilePath: historyPath,
        transportPolicy: const TransportPolicy(mode: TransportMode.loopbackTest),
      );

      // Deve falhar pois a chave rogue está revogada
      await expectLater(
        mgr.checkForUpdate(manifestUri: Uri.parse('http://127.0.0.1:${server.port}/manifest.json')),
        throwsA(isA<CatalogKeyRevokedException>()),
      );

      await server.close();
    });

    test('4. Fluxo completo de download, validação, troca atômica e histórico', () async {
      // 1. Instala versão 1 inicial
      final v1Bytes = await createValidCatalogBytes(version: 1, count: 5);
      await File(catalogPath).writeAsBytes(v1Bytes);

      // 2. Prepara pacote versão 2
      final v2Bytes = await createValidCatalogBytes(version: 2, count: 25);
      final manifestV2 = await SignedCatalogManifest.signArtifact(
        signerKeyPair: validKeyPair,
        version: 2,
        artifactName: 'test_catalog.db',
        artifactBytes: v2Bytes,
        entryCount: 25,
      );

      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) {
        if (req.uri.path.endsWith('manifest.json')) {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(manifestV2.toJson()));
          req.response.close();
        } else if (req.uri.path.endsWith('.db')) {
          req.response.headers.contentType = ContentType.binary;
          req.response.add(v2Bytes);
          req.response.close();
        }
      });

      final keyring = CatalogPublisherKeyring(trustedKeysHex: {validPubHex});
      final mgr = CatalogUpdateManager(
        keyring: keyring,
        targetDbPath: catalogPath,
        historyFilePath: historyPath,
        transportPolicy: const TransportPolicy(mode: TransportMode.loopbackTest),
      );

      // Consulta atualização
      final detected = await mgr.checkForUpdate(
        manifestUri: Uri.parse('http://127.0.0.1:${server.port}/manifest.json'),
      );
      expect(detected, isNotNull);
      expect(detected!.version, equals(2));
      expect(detected.entryCount, equals(25));

      // Baixa e aplica atualização
      final updatedDb = await mgr.downloadAndApplyUpdate(
        manifest: detected,
        packageUri: Uri.parse('http://127.0.0.1:${server.port}/test_catalog.db'),
      );

      expect(await updatedDb.getVersion(), equals(2));
      final works = await updatedDb.searchWorks(query: 'Title', limit: 50);
      expect(works.length, equals(25));
      await updatedDb.close();

      // Verifica versão instalada
      expect(await mgr.getInstalledVersion(), equals(2));

      // Verifica histórico gravado
      final history = await mgr.getVersionHistory();
      expect(history.length, equals(1));
      expect(history.first.version, equals(2));
      expect(history.first.status, equals('success'));

      // Verifica que agora está atualizado
      final checkAgain = await mgr.checkForUpdate(
        manifestUri: Uri.parse('http://127.0.0.1:${server.port}/manifest.json'),
      );
      expect(checkAgain, isNull);
      expect(mgr.currentProgress.stage, equals(CatalogUpdateStage.upToDate));

      await server.close();
    });

    test('5. Rejeição de adulteração e recuperação da versão anterior (Rollback)', () async {
      // 1. Instala versão 1 inicial
      final v1Bytes = await createValidCatalogBytes(version: 1, count: 5);
      await File(catalogPath).writeAsBytes(v1Bytes);

      // 2. Prepara pacote versão 2 com dados adulterados (hash inválido)
      final v2Bytes = await createValidCatalogBytes(version: 2, count: 10);
      final manifestV2 = await SignedCatalogManifest.signArtifact(
        signerKeyPair: validKeyPair,
        version: 2,
        artifactName: 'test_catalog.db',
        artifactBytes: v2Bytes,
        entryCount: 10,
      );

      // Adultera os bytes enviados
      final corruptedBytes = List<int>.from(v2Bytes);
      corruptedBytes[100] ^= 0xFF;

      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) {
        if (req.uri.path.endsWith('.db')) {
          req.response.headers.contentType = ContentType.binary;
          req.response.add(corruptedBytes);
          req.response.close();
        }
      });

      final keyring = CatalogPublisherKeyring(trustedKeysHex: {validPubHex});
      final mgr = CatalogUpdateManager(
        keyring: keyring,
        targetDbPath: catalogPath,
        historyFilePath: historyPath,
        transportPolicy: const TransportPolicy(mode: TransportMode.loopbackTest),
      );

      await expectLater(
        mgr.downloadAndApplyUpdate(
          manifest: manifestV2,
          packageUri: Uri.parse('http://127.0.0.1:${server.port}/test_catalog.db'),
        ),
        throwsA(isA<CatalogIntegrityVerificationException>()),
      );

      // O banco original v1 deve permanecer íntegro e inalterado
      expect(await mgr.getInstalledVersion(), equals(1));

      await server.close();
    });

    test('6. Cancelamento de atualização e limpeza de arquivos temporários', () async {
      final mgr = CatalogUpdateManager(
        targetDbPath: catalogPath,
        historyFilePath: historyPath,
        transportPolicy: const TransportPolicy(mode: TransportMode.loopbackTest),
      );

      // Cria arquivos órfãos .incoming e .bak
      final incFile = File('$catalogPath.incoming');
      final bakFile = File('$catalogPath.bak');
      await incFile.writeAsBytes([1, 2, 3, 4, 5]);
      await bakFile.writeAsBytes([6, 7, 8, 9, 10]);

      expect(incFile.existsSync(), isTrue);
      expect(bakFile.existsSync(), isTrue);

      final freed = await mgr.cleanupStorage();
      expect(freed, equals(10));
      expect(incFile.existsSync(), isFalse);
      expect(bakFile.existsSync(), isFalse);

      // Testa cancelamento
      mgr.cancel();
      expect(mgr.currentProgress.stage, equals(CatalogUpdateStage.cancelled));
    });
  });
}
