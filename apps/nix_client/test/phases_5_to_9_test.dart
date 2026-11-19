import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:nix_client/core/archive/nix_archive_service.dart';
import 'package:nix_client/core/database/local_database.dart';
import 'package:nix_client/core/database/repositories.dart';
import 'package:nix_client/core/media/media_catalog_service.dart';
import 'package:nix_client/core/models/monero_order.dart';
import 'package:nix_client/core/offgrid/mbtiles_reader.dart';
import 'package:nix_client/core/p2p/monero_ad_verifier.dart';
import 'package:nix_client/core/security/key_vault.dart';
import 'package:nix_client/core/security/os_key_storage.dart';
import 'package:nix_client/core/security/seed_recovery.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fases 5 a 8: MBTiles, Monero Non-Custodial, Nix Archive e Nix Media', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_p5_p8_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Fase 5 MBTiles: lê metadados e tile binário localmente offline', () async {
      final mbtilesPath = '${tempDir.path}/region_sample.mbtiles';
      LocalDatabase.ensureSqliteInitialized();
      final db = await databaseFactoryFfiNoIsolate.openDatabase(mbtilesPath);
      await db.execute('CREATE TABLE metadata(name TEXT, value TEXT);');
      await db.execute(
          'CREATE TABLE tiles(zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);');
      await db.insert('metadata', {'name': 'name', 'value': 'Regiao Sul Offline'});
      await db.insert('tiles', {
        'zoom_level': 12,
        'tile_column': 1520,
        'tile_row': 2240,
        'tile_data': Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]),
      });
      await db.close();

      final reader = await MbtilesMapReader.openFile(mbtilesPath);
      final meta = await reader.readMetadata();
      expect(meta['name'], 'Regiao Sul Offline');
      final tile = await reader.getTile(zoom: 12, column: 1520, row: 2240);
      expect(tile, equals(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])));
      expect(await reader.getTile(zoom: 12, column: 0, row: 0), isNull);
      await reader.close();
    });

    test('Fase 6 Monero Non-Custodial: Ed25519 ad signing, replay protection & Seed A/B isolation', () async {
      final seedA = SeedRecoveryManager.generateMnemonic();
      final seedB = SeedRecoveryManager.generateMnemonic();
      MoneroIsolationPolicy.assertDistinctSeedDomains(
        seedAMnemonic: seedA,
        seedBMnemonic: seedB,
      );
      expect(
        () => MoneroIsolationPolicy.assertDistinctSeedDomains(
          seedAMnemonic: seedA,
          seedBMnemonic: seedA,
        ),
        throwsA(isA<MoneroSeedBoundaryException>()),
      );

      // Valida endpoint RPC Monero fail-closed
      MoneroIsolationPolicy.assertSafeWalletRpcUri(
        Uri.parse('http://127.0.0.1:18082/json_rpc'),
      );
      MoneroIsolationPolicy.assertSafeWalletRpcUri(
        Uri.parse('http://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.onion:18081/json_rpc'),
      );
      expect(
        () => MoneroIsolationPolicy.assertSafeWalletRpcUri(
          Uri.parse('http://node.clearnet.example:18081/json_rpc'),
        ),
        throwsA(isA<MoneroSeedBoundaryException>()),
      );

      final trader = await NixIdentity.generate();
      final signedAd = await SignedMoneroAd.createSigned(
        signer: trader,
        orderId: 'xmr_ord_01',
        traderName: 'VendedorSoberano',
        side: MoneroP2pSide.sell,
        fiatCurrency: 'BRL',
        pricePerXmr: 980.0,
        minFiatLimit: 200,
        maxFiatLimit: 2000,
        paymentMethod: 'PIX',
      );
      final wireJson = signedAd.toWireJson();
      final replayGuard = ReplayGuard();

      // Primeira verificação válida passa
      expect(
        await SignedMoneroAd.verifyWireJson(wireJson, replayGuard: replayGuard),
        isTrue,
      );
      // Replay do mesmo nonce deve ser bloqueado imediatamente
      expect(
        await SignedMoneroAd.verifyWireJson(wireJson, replayGuard: replayGuard),
        isFalse,
      );
      // Adulteração de preço invalida assinatura Ed25519
      final map = jsonDecode(wireJson) as Map<String, dynamic>;
      (map['payload'] as Map<String, dynamic>)['pricePerXmr'] = 10.0;
      expect(
        await SignedMoneroAd.verifyWireJson(
          jsonEncode(map),
          replayGuard: ReplayGuard(),
        ),
        isFalse,
      );
    });

    test('Fase 7 Nix Archive: canonical v1, HTML XSS strip, claims/refutations & tamper detection', () async {
      final vault = KeyVault(osKeyStorage: InMemoryOsKeyStorage());
      final key = await vault.initialize(
        passphrase: 'archive-test-passphrase',
        customPath: '${tempDir.path}/vault.json',
      );
      final db = await LocalDatabase.open(
        path: '${tempDir.path}/nix_archive.db',
        rawCipherKey: key,
      );

      final author = await NixIdentity.generate();
      final critic = await NixIdentity.generate();
      final archiveRepo = ArchiveRepository(db);
      final keyMatRepo = KeyMaterialRepository(db);
      final service = NixArchiveService(archiveRepo);

      await service.ensurePersonaRegistered(
        personaId: author.publicId,
        identity: author,
        keyMaterialRepo: keyMatRepo,
        keyRef: 'vault:author_1',
      );
      await service.ensurePersonaRegistered(
        personaId: critic.publicId,
        identity: critic,
        keyMaterialRepo: keyMatRepo,
        keyRef: 'vault:critic_1',
      );

      final dirtyHtml =
          '<p>Texto <b>auditado</b></p><script>alert(1)</script>'
          '<a href="javascript:steal()" onclick="evil()">link</a>'
          '<iframe src="https://evil.example"></iframe>';
      final artHash = await service.publishArticle(
        author: author,
        title: 'Relatorio Tecnico #1',
        rawHtmlBody: dirtyHtml,
        claims: [
          (claimId: 'C1', text: 'Todos os logs de IP foram removidos do relay.'),
        ],
      );
      expect(artHash.length, 64);
      expect(await service.verifyStoredObject(artHash), isTrue);

      final storedObj = await archiveRepo.getObject(artHash);
      final storedJson =
          utf8.decode(storedObj!['canonical_bytes'] as List<int>);
      expect(storedJson, isNot(contains('<script>')));
      expect(storedJson, isNot(contains('onclick=')));
      expect(storedJson, isNot(contains('javascript:')));
      expect(storedJson, isNot(contains('<iframe')));
      expect(storedJson, contains('<b>auditado</b>'));

      // Publica refutação ligada a (artHash, 'C1')
      final refHash = await service.publishRefutation(
        author: critic,
        targetHash: artHash,
        targetClaimId: 'C1',
        rationaleHtml: '<p>Contraprova com evidencia verificavel.</p>',
      );
      expect(await service.verifyStoredObject(refHash), isTrue);
      final refs = await archiveRepo.listRefutationsForTarget(artHash);
      expect(refs.length, 1);
      expect(refs.first['refutation_hash'], refHash);

      // Registra versão revisada superseding a anterior
      final v2Hash = await service.publishArticle(
        author: author,
        title: 'Relatorio Tecnico #1 (Revisao 2)',
        rawHtmlBody: '<p>Revisao completa.</p>',
        supersedesHash: artHash,
      );
      final v2Row = await archiveRepo.getObject(v2Hash);
      expect(v2Row!['supersedes_hash'], artHash);

      // Adulteração silenciosa no banco SQLite é detectada por SHA-256 / Ed25519
      await db.rawDatabase.rawUpdate(
        'UPDATE archive_objects SET canonical_bytes = ? WHERE hash = ?',
        [utf8.encode('{"schema":"tampered"}'), artHash],
      );
      expect(await service.verifyStoredObject(artHash), isFalse);
      await db.close();
    });

    test('Fase 8 Nix Media: lookup offline FTS5 separado e magnet gate fail-closed', () async {
      final vault = KeyVault(osKeyStorage: InMemoryOsKeyStorage());
      final key = await vault.initialize(
        passphrase: 'media-test-passphrase',
        customPath: '${tempDir.path}/media_vault.json',
      );
      final db = await LocalDatabase.open(
        path: '${tempDir.path}/nix_media.db',
        rawCipherKey: key,
      );
      final mediaService = MediaCatalogService(MediaRepository(db));

      await mediaService.saveOfflineCatalogEntry(
        id: 'repo_nix_core',
        kind: 'repository',
        title: 'Nix Encrypted Relay Core',
        metadata: {'language': 'Go', 'stars': 120},
      );
      final found = await mediaService.searchOfflineCatalog('Encrypted');
      expect(found.length, 1);
      expect(found.first['id'], 'repo_nix_core');

      const sampleMagnet =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=nix-sample';

      // Bloqueia em claro quando Tor estrito ativo sem opt-in isolado
      expect(
        () => MediaCatalogService.authorizeMagnetResolution(
          magnetUri: sampleMagnet,
          isFailClosedTorActive: true,
          explicitIsolatedTorrentOptIn: false,
          disableUdpDhtAndLsd: true,
        ),
        throwsA(isA<TorrentClearnetLeakBlockedException>()),
      );

      // Bloqueia mesmo com opt-in se DHT/LSD UDP não estiverem desativados
      expect(
        () => MediaCatalogService.authorizeMagnetResolution(
          magnetUri: sampleMagnet,
          isFailClosedTorActive: true,
          explicitIsolatedTorrentOptIn: true,
          disableUdpDhtAndLsd: false,
        ),
        throwsA(isA<TorrentClearnetLeakBlockedException>()),
      );

      // Aceita e retorna apenas o infohash isolado quando política estrita é cumprida
      final infoHash = MediaCatalogService.authorizeMagnetResolution(
        magnetUri: sampleMagnet,
        isFailClosedTorActive: true,
        explicitIsolatedTorrentOptIn: true,
        disableUdpDhtAndLsd: true,
      );
      expect(infoHash, '0123456789abcdef0123456789abcdef01234567');
      await db.close();
    });
  });
}
