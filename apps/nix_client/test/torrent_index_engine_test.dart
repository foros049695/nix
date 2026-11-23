import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/torrent_index/engine/torrent_deduplicator.dart';
import 'package:nix_client/core/torrent_index/engine/torrent_normalizer.dart';
import 'package:nix_client/core/torrent_index/models/torrent_record.dart';

void main() {
  group('TorrentNormalizer', () {
    test('Valida e normaliza InfoHash v1 em hexadecimal de 40 caracteres', () {
      const validHash = '1234567890ABCDEF1234567890ABCDEF12345678';
      final normalized = TorrentNormalizer.normalizeInfoHashV1(validHash);
      expect(normalized, equals('1234567890abcdef1234567890abcdef12345678'));
    });

    test('Converte Base32 de 32 caracteres para Hex 40', () {
      // 32 caracteres RFC 4648 Base32
      const base32 = 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP';
      final hex = TorrentNormalizer.normalizeInfoHashV1(base32);
      expect(hex, isNotNull);
      expect(hex!.length, equals(40));
    });

    test('Rejeita InfoHash inválido', () {
      expect(TorrentNormalizer.normalizeInfoHashV1('curto'), isNull);
      expect(TorrentNormalizer.normalizeInfoHashV1('123456789012345678901234567890123456789Z'), isNull);
    });

    test('Normaliza títulos removendo pontos e underscores de releases', () {
      final raw = 'The.Godfather.1972.1080p.BluRay.x264';
      final clean = TorrentNormalizer.normalizeTitle(raw);
      expect(clean, equals('The Godfather 1972 1080p BluRay x264'));

      final under = 'Solaris_1972_Criterion_720p';
      expect(TorrentNormalizer.normalizeTitle(under), equals('Solaris 1972 Criterion 720p'));
    });

    test('Extrai InfoHash e dn de URI magnet', () {
      const magnet = 'magnet:?xt=urn:btih:3b24f5c697841c6f90d56c805eb3df90f2d655ea&dn=Ubuntu+22.04+LTS&tr=http%3A%2F%2Ftracker.org';
      final hash = TorrentNormalizer.extractInfoHashFromMagnet(magnet);
      expect(hash, equals('3b24f5c697841c6f90d56c805eb3df90f2d655ea'));

      final dn = TorrentNormalizer.extractDisplayNameFromMagnet(magnet);
      expect(dn, equals('Ubuntu 22.04 LTS'));
    });

    test('Constrói URI magnet canônica', () {
      final built = TorrentNormalizer.buildCanonicalMagnet(
        infoHashV1: '3B24F5C697841C6F90D56C805EB3DF90F2D655EA',
        title: 'Debian 12 Bookworm',
        trackers: const ['http://tracker.debian.org/announce'],
      );
      expect(built, startsWith('magnet:?xt=urn:btih:3b24f5c697841c6f90d56c805eb3df90f2d655ea'));
      expect(built, contains('&dn=Debian%2012%20Bookworm'));
      expect(built, contains('&tr=http%3A%2F%2Ftracker.debian.org%2Fannounce'));
    });
  });

  group('TorrentDeduplicator', () {
    test('Deduplica registros idênticos por InfoHash v1 e agrega proveniências', () {
      final now = DateTime.now();
      final recA = TorrentIndexRecord(
        id: 'rec_1',
        sourceId: 'nyaa',
        sourceName: 'Nyaa.si',
        sourceUrl: 'https://nyaa.si/view/100',
        title: 'Cowboy Bebop (1998) [1080p]',
        normalizedTitle: 'Cowboy Bebop (1998) [1080p]',
        category: TorrentCategory.anime,
        sizeBytes: 15000000000,
        infoHashV1: 'abcdef1234567890abcdef1234567890abcdef12',
        seeders: 80,
        leechers: 10,
        indexedAt: now,
        lastSeenAt: now,
      );

      final recB = TorrentIndexRecord(
        id: 'rec_2',
        sourceId: 'yts',
        sourceName: 'YTS.mx',
        sourceUrl: 'https://yts.mx/movies/cowboy-bebop',
        title: 'Cowboy Bebop The Movie 1080p',
        normalizedTitle: 'Cowboy Bebop The Movie 1080p',
        category: TorrentCategory.movies,
        sizeBytes: 15000000000,
        infoHashV1: 'abcdef1234567890abcdef1234567890abcdef12',
        seeders: 120,
        leechers: 15,
        indexedAt: now,
        lastSeenAt: now,
      );

      final merged = TorrentDeduplicator.deduplicate([recA, recB]);
      expect(merged.length, equals(1));

      final first = merged.first;
      expect(first.infoHashV1, equals('abcdef1234567890abcdef1234567890abcdef12'));
      // Proveniências preservadas para ambas as fontes
      expect(first.provenances.length, equals(2));
      expect(first.provenances.any((p) => p.sourceId == 'nyaa'), isTrue);
      expect(first.provenances.any((p) => p.sourceId == 'yts'), isTrue);

      // Seeders refletem o maior valor observado
      expect(first.seeders, equals(120));
    });

    test('Torrents com InfoHashes distintos NÃO são agrupados por semelhança de título', () {
      final now = DateTime.now();
      final rec1 = TorrentIndexRecord(
        id: '1',
        sourceId: 'src_a',
        sourceName: 'Fonte A',
        title: 'Solaris 1972 Remastered',
        normalizedTitle: 'Solaris 1972 Remastered',
        category: TorrentCategory.movies,
        infoHashV1: '1111111111111111111111111111111111111111',
        indexedAt: now,
        lastSeenAt: now,
      );

      final rec2 = TorrentIndexRecord(
        id: '2',
        sourceId: 'src_b',
        sourceName: 'Fonte B',
        title: 'Solaris 1972 Criterion',
        normalizedTitle: 'Solaris 1972 Criterion',
        category: TorrentCategory.movies,
        infoHashV1: '2222222222222222222222222222222222222222',
        indexedAt: now,
        lastSeenAt: now,
      );

      final result = TorrentDeduplicator.deduplicate([rec1, rec2]);
      expect(result.length, equals(2));
    });
  });
}
