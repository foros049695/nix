import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/torrent_index/database/torrent_index_database.dart';
import 'package:nix_client/core/torrent_index/models/torrent_record.dart';
import 'package:nix_client/core/torrent_index/models/torrent_search_query.dart';
import 'package:nix_client/core/torrent_index/updates/torrent_signed_index_package.dart';

void main() {
  group('TorrentIndexDatabase (SQLite FTS5)', () {
    late TorrentIndexDatabase db;

    setUp(() async {
      db = await TorrentIndexDatabase.open(inMemory: true);
    });

    tearDown(() async {
      await db.close();
    });

    test('Indexa e pesquisa registros com FTS5 e suporte a prefixos', () async {
      final now = DateTime.now();
      final records = [
        TorrentIndexRecord(
          id: 'rec_solaris',
          sourceId: 'yts',
          sourceName: 'YTS.mx',
          title: 'Solaris 1972 Andrei Tarkovsky',
          normalizedTitle: 'Solaris 1972 Andrei Tarkovsky',
          category: TorrentCategory.movies,
          sizeBytes: 2500000000,
          seeders: 120,
          leechers: 10,
          indexedAt: now,
          lastSeenAt: now,
        ),
        TorrentIndexRecord(
          id: 'rec_stalker',
          sourceId: 'yts',
          sourceName: 'YTS.mx',
          title: 'Stalker 1979 Sci-Fi Drama',
          normalizedTitle: 'Stalker 1979 Sci-Fi Drama',
          category: TorrentCategory.movies,
          sizeBytes: 3100000000,
          seeders: 85,
          leechers: 8,
          indexedAt: now,
          lastSeenAt: now,
        ),
        TorrentIndexRecord(
          id: 'rec_frieren',
          sourceId: 'nyaa',
          sourceName: 'Nyaa.si',
          title: 'Sousou no Frieren Episode 01',
          normalizedTitle: 'Sousou no Frieren Episode 01',
          category: TorrentCategory.anime,
          sizeBytes: 1400000000,
          seeders: 300,
          leechers: 25,
          indexedAt: now,
          lastSeenAt: now,
        ),
      ];

      await db.upsertRecords(records);
      final count = await db.getRecordCount();
      expect(count, equals(3));

      // Busca por prefixo "Sola"
      final searchRes = await db.search(const TorrentSearchQuery(query: 'Sola'));
      expect(searchRes.records.length, equals(1));
      expect(searchRes.records.first.id, equals('rec_solaris'));

      // Busca por categoria "anime"
      final animeRes = await db.search(const TorrentSearchQuery(
        query: '',
        categories: {TorrentCategory.anime},
      ));
      expect(animeRes.records.length, equals(1));
      expect(animeRes.records.first.id, equals('rec_frieren'));

      // Ordenação por mais seeds
      final sortRes = await db.search(const TorrentSearchQuery(
        query: '',
        sort: TorrentSortOrder.seedersDesc,
      ));
      expect(sortRes.records.first.id, equals('rec_frieren')); // 300 seeds
    });
  });

  group('TorrentSignedIndexPackage (Segurança e Rollback)', () {
    late TorrentIndexDatabase db;

    setUp(() async {
      db = await TorrentIndexDatabase.open(inMemory: true);
    });

    tearDown(() async {
      await db.close();
    });

    test('Verifica integridade SHA-256 e assinatura Ed25519', () async {
      final ed25519 = Ed25519();
      final keyPair = await ed25519.newKeyPair();
      final pubKey = await keyPair.extractPublicKey();
      final pubKeyHex = pubKey.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      const payloadString = '[{"id":"rec_pkg_1","sourceId":"src","sourceName":"Test","title":"Open Linux ISO","normalizedTitle":"Open Linux ISO","category":"software","indexedAt":"2026-11-23T00:00:00.000","lastSeenAt":"2026-11-23T00:00:00.000"}]';
      final payloadBytes = Uint8List.fromList(utf8.encode(payloadString));
      final payloadSha256 = std_crypto.sha256.convert(payloadBytes).toString();

      final sig = await ed25519.sign(payloadBytes, keyPair: keyPair);
      final signatureHex = sig.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final manifest = TorrentPackageManifest(
        version: 2,
        payloadSha256: payloadSha256,
        recordsCount: 1,
        publishedAt: DateTime.now(),
        signatureHex: signatureHex,
        signerPublicKeyHex: pubKeyHex,
      );

      // Aplica pacote versão 2
      await TorrentSignedIndexPackage.applyPackage(
        db: db,
        manifest: manifest,
        payloadBytes: payloadBytes,
        trustedPublicKeys: {pubKeyHex},
      );

      final count = await db.getRecordCount();
      expect(count, equals(1));
      expect(await db.getMeta('current_package_version'), equals('2'));

      // Tenta aplicar pacote versão 1 (Rollback deve ser rejeitado!)
      final rollbackManifest = TorrentPackageManifest(
        version: 1, // Menor que 2!
        payloadSha256: payloadSha256,
        recordsCount: 1,
        publishedAt: DateTime.now(),
        signatureHex: signatureHex,
        signerPublicKeyHex: pubKeyHex,
      );

      expect(
        () => TorrentSignedIndexPackage.applyPackage(
          db: db,
          manifest: rollbackManifest,
          payloadBytes: payloadBytes,
          trustedPublicKeys: {pubKeyHex},
        ),
        throwsA(isA<TorrentPackageRollbackException>()),
      );
    });
  });
}
