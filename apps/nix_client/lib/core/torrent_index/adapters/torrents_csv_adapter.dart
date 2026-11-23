import 'dart:convert';
import '../engine/torrent_normalizer.dart';
import '../models/indexer_source_config.dart';
import '../models/torrent_record.dart';
import 'nix_indexer_adapter.dart';
import 'nyaa_rss_adapter.dart';

/// Adaptador para o Torrents-CSV (índice aberto sem cloudflare/captcha com API JSON rápida).
class TorrentsCsvAdapter implements NixIndexerAdapter {
  final TorrentHttpRequester? _requester;

  @override
  String get sourceId => 'torrents_csv';

  @override
  String get sourceName => 'Torrents-CSV';

  @override
  String get baseUrl => 'https://torrents-csv.com/service';

  @override
  IndexerSourceType get type => IndexerSourceType.api;

  const TorrentsCsvAdapter({TorrentHttpRequester? requester}) : _requester = requester;

  @override
  Future<List<TorrentIndexRecord>> search(
    String query, {
    TorrentCategory? category,
    int limit = 25,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];
    final encoded = Uri.encodeQueryComponent(clean);
    final uri = Uri.parse('$baseUrl/search?q=$encoded&size=$limit');
    return _fetchAndParse(uri, limit, category);
  }

  @override
  Future<List<TorrentIndexRecord>> fetchRecent({int limit = 25}) async {
    final uri = Uri.parse('$baseUrl/search?q=&size=$limit');
    return _fetchAndParse(uri, limit, null);
  }

  @override
  Future<bool> testConnection() async {
    try {
      final records = await search('linux', limit: 2);
      return records.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<List<TorrentIndexRecord>> _fetchAndParse(Uri uri, int limit, TorrentCategory? requestedCat) async {
    if (_requester == null) return const [];
    try {
      final res = await _requester!(
        'GET',
        uri,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) NixTorrentIndex/1.0',
          'Accept': 'application/json',
        },
        timeout: const Duration(seconds: 25),
      );
      if (res.statusCode != 200) return const [];
      return parseJson(res.body, limit, requestedCat);
    } catch (_) {
      return const [];
    }
  }

  List<TorrentIndexRecord> parseJson(String jsonStr, int limit, [TorrentCategory? requestedCat]) {
    try {
      final decoded = json.decode(jsonStr);
      final list = (decoded is Map<String, dynamic>)
          ? (decoded['torrents'] as List?)
          : (decoded is List ? decoded : null);

      if (list == null) return const [];

      final results = <TorrentIndexRecord>[];
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final infoHashRaw = item['infohash']?.toString().trim() ?? '';
        final name = item['name']?.toString().trim() ?? '';

        if (infoHashRaw.isEmpty || name.isEmpty) continue;

        final normalizedHash = TorrentNormalizer.normalizeInfoHashV1(infoHashRaw);
        if (normalizedHash == null) continue;

        final seeders = int.tryParse(item['seeders']?.toString() ?? '0') ?? 0;
        final leechers = int.tryParse(item['leechers']?.toString() ?? '0') ?? 0;
        final sizeBytes = int.tryParse(item['size_bytes']?.toString() ?? '0');
        final createdUnix = int.tryParse(item['created_unix']?.toString() ?? '0');
        final pubDate = (createdUnix != null && createdUnix > 0)
            ? DateTime.fromMillisecondsSinceEpoch(createdUnix * 1000, isUtc: true)
            : null;

        final cat = requestedCat ?? _guessCategory(name);

        final magnet = TorrentNormalizer.buildCanonicalMagnet(
          infoHashV1: normalizedHash,
          title: name,
          trackers: const [
            'udp://tracker.opentrackr.org:1337/announce',
            'udp://open.stealth.si:80/announce',
            'udp://tracker.torrent.eu.org:451/announce',
          ],
        );

        results.add(TorrentIndexRecord(
          id: 'tcsv_${normalizedHash}_${results.length}',
          sourceId: sourceId,
          sourceName: sourceName,
          sourceUrl: 'https://torrents-csv.com',
          title: name,
          normalizedTitle: TorrentNormalizer.normalizeTitle(name),
          category: cat,
          sizeBytes: sizeBytes,
          seeders: seeders,
          leechers: leechers,
          infoHashV1: normalizedHash,
          magnetUri: magnet,
          publicationDate: pubDate,
          indexedAt: DateTime.now(),
          lastSeenAt: DateTime.now(),
        ));

        if (results.length >= limit) break;
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  TorrentCategory _guessCategory(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('1080p') || lower.contains('2160p') || lower.contains('bluray') || lower.contains('web-dl') || lower.contains('x264') || lower.contains('x265')) {
      if (lower.contains('s01') || lower.contains('s02') || lower.contains('season') || lower.contains('episode')) {
        return TorrentCategory.tv;
      }
      return TorrentCategory.movies;
    }
    if (lower.contains('flac') || lower.contains('mp3') || lower.contains('discography')) {
      return TorrentCategory.music;
    }
    if (lower.contains('epub') || lower.contains('pdf') || lower.contains('mobi')) {
      return TorrentCategory.books;
    }
    if (lower.contains('.iso') || lower.contains('.exe') || lower.contains('repack') || lower.contains('steam')) {
      return TorrentCategory.games;
    }
    return TorrentCategory.other;
  }
}
