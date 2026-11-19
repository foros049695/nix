import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:nix_client/core/media/catalog_database.dart';
import 'package:nix_client/core/media/media_index_updater.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Ed25519 ed;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nix_catalog_sec_test_');
    ed = Ed25519();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Etapa 1.2 — Segurança de Chaves, Rotação e Revogação do Catálogo', () {
    test('Rejeita chave pública de teste em modo estrito de produção', () async {
      final dummyBytes = [1, 2, 3, 4, 5, 6, 7, 8];
      final manifestWithTestKey = SignedCatalogManifest(
        version: 1,
        artifactName: 'catalog.db',
        sha256Hex: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        byteSize: dummyBytes.length,
        issuedAtUnix: 1000,
        entryCount: 1,
        signerEd25519Hex: CatalogPublisherKeyring.fixtureTestPublisherKeyHex,
        signatureHex: 'abcd' * 16,
        isProduction: true,
      );

      final prodKeyring = CatalogPublisherKeyring(
        trustedKeysHex: {CatalogPublisherKeyring.fixtureTestPublisherKeyHex},
        isProductionMode: true,
        allowTestFixtureKey: false,
      );

      expect(
        () => manifestWithTestKey.verifyWithKeyring(dummyBytes, prodKeyring),
        throwsA(isA<CatalogTestKeyRejectedException>()),
      );
    });

    test('Rejeita pacote assinado por chave de publicador revogada', () async {
      final publisherKey = await ed.newKeyPair();
      final publisherPub = await publisherKey.extractPublicKey();
      final pubHex = SignedCatalogManifest.bytesToHex(publisherPub.bytes);

      final dummyBytes = [10, 20, 30, 40];
      final manifest = await SignedCatalogManifest.signArtifact(
        signerKeyPair: publisherKey,
        version: 1,
        artifactName: 'catalog.db',
        artifactBytes: dummyBytes,
        entryCount: 1,
      );

      final keyring = CatalogPublisherKeyring(
        trustedKeysHex: {pubHex},
        revokedKeysHex: {pubHex},
      );

      expect(
        () => manifest.verifyWithKeyring(dummyBytes, keyring),
        throwsA(isA<CatalogKeyRevokedException>()),
      );
    });

    test('Rejeita publicador desconhecido fora do anel de chaves', () async {
      final publisherKey = await ed.newKeyPair();
      final rogueKey = await ed.newKeyPair();
      final publisherPub = await publisherKey.extractPublicKey();
      final pubHex = SignedCatalogManifest.bytesToHex(publisherPub.bytes);

      final dummyBytes = [10, 20, 30, 40];
      final manifestFromRogue = await SignedCatalogManifest.signArtifact(
        signerKeyPair: rogueKey,
        version: 1,
        artifactName: 'catalog.db',
        artifactBytes: dummyBytes,
        entryCount: 1,
      );

      final keyring = CatalogPublisherKeyring(trustedKeysHex: {pubHex});

      expect(
        () => manifestFromRogue.verifyWithKeyring(dummyBytes, keyring),
        throwsA(isA<CatalogUntrustedSignerException>()),
      );
    });

    test('Suporta rotação de chave criptográfica comprovada por assinatura', () async {
      final oldKey = await ed.newKeyPair();
      final newKey = await ed.newKeyPair();
      final oldPub = await oldKey.extractPublicKey();
      final newPub = await newKey.extractPublicKey();
      final oldPubHex = SignedCatalogManifest.bytesToHex(oldPub.bytes);
      final newPubHex = SignedCatalogManifest.bytesToHex(newPub.bytes);

      final keyring = CatalogPublisherKeyring(trustedKeysHex: {oldPubHex});
      expect(keyring.isKeyTrusted(oldPubHex), isTrue);
      expect(keyring.isKeyTrusted(newPubHex), isFalse);

      final dummyBytes = [1, 2, 3, 4, 5];
      final rotatedManifest = await SignedCatalogManifest.signArtifact(
        signerKeyPair: newKey,
        version: 2,
        artifactName: 'catalog.db',
        artifactBytes: dummyBytes,
        entryCount: 1,
        previousKeyPair: oldKey,
      );

      final isValid = await rotatedManifest.verifyWithKeyring(dummyBytes, keyring);
      expect(isValid, isTrue);
      expect(keyring.isKeyTrusted(newPubHex), isTrue, reason: 'Nova chave deve ter sido incorporada após prova de rotação');
    });

    test('Rejeita adulteração de bytes do catálogo (Tamper Detection)', () async {
      final publisherKey = await ed.newKeyPair();
      final publisherPub = await publisherKey.extractPublicKey();
      final pubHex = SignedCatalogManifest.bytesToHex(publisherPub.bytes);

      final dummyBytes = [100, 101, 102, 103];
      final manifest = await SignedCatalogManifest.signArtifact(
        signerKeyPair: publisherKey,
        version: 1,
        artifactName: 'catalog.db',
        artifactBytes: dummyBytes,
        entryCount: 1,
      );

      final tamperedBytes = [100, 101, 102, 99]; // último byte adulterado
      final keyring = CatalogPublisherKeyring(trustedKeysHex: {pubHex});

      final valid = await manifest.verifyWithKeyring(tamperedBytes, keyring);
      expect(valid, isFalse);
    });

    test('MediaIndexUpdater aplica pacote com Keyring e rejeita rollback', () async {
      final publisherKey = await ed.newKeyPair();
      final publisherPub = await publisherKey.extractPublicKey();
      final pubHex = SignedCatalogManifest.bytesToHex(publisherPub.bytes);

      final keyring = CatalogPublisherKeyring(trustedKeysHex: {pubHex});
      final targetDbPath = '${tempDir.path}/active_catalog.db';

      // Cria v1 inicial
      final dbV1 = await CatalogDatabase.open(path: targetDbPath);
      await dbV1.setMeta('version', '1');
      await dbV1.upsertWork(const CatalogWork(
        id: 'nix:work:1',
        kind: 'movie',
        title: 'Filme 1',
        updatedAt: 1,
      ));
      await dbV1.close();

      // Constrói v2
      final v2SourcePath = '${tempDir.path}/v2_src.db';
      final dbV2 = await CatalogDatabase.open(path: v2SourcePath);
      await dbV2.setMeta('version', '2');
      await dbV2.upsertWork(const CatalogWork(
        id: 'nix:work:2',
        kind: 'movie',
        title: 'Filme 2',
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

      final appliedDb = await MediaIndexUpdater.applySignedCatalogPackage(
        packageBytes: v2Bytes,
        manifest: manifestV2,
        keyring: keyring,
        targetDbPath: targetDbPath,
      );
      expect(await appliedDb.getVersion(), equals(2));
      await appliedDb.close();

      // Tentativa de rollback para v1 deve ser rejeitada
      final v1Bytes = await File(targetDbPath).readAsBytes();
      final manifestV1Rollback = await SignedCatalogManifest.signArtifact(
        signerKeyPair: publisherKey,
        version: 1,
        artifactName: 'active_catalog.db',
        artifactBytes: v1Bytes,
        entryCount: 1,
      );

      expect(
        () => MediaIndexUpdater.applySignedCatalogPackage(
          packageBytes: v1Bytes,
          manifest: manifestV1Rollback,
          keyring: keyring,
          targetDbPath: targetDbPath,
        ),
        throwsA(isA<CatalogRollbackRejectedException>()),
      );
    });
  });
}
