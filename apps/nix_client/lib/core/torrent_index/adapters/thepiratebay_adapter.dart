import 'dart:convert';
import '../engine/torrent_normalizer.dart';
import '../models/indexer_source_config.dart';
import '../models/torrent_record.dart';
import 'nix_indexer_adapter.dart';
import 'nyaa_rss_adapter.dart';

/// Adaptador para o ThePirateBay via API oficial / apibay.org.
/// Suporta busca direta por palavras-chave com retorno JSON estruturado de seeds e infoHash.
class ThePirateBayAdapter implements NixIndexerAdapter {
  final TorrentHttpRequester? _requester;

  @override
  String get sourceId => 'thepiratebay';

  @override
  String get sourceName => 'ThePirateBay';

  @override
  String get baseUrl => 'https://apibay.org';

  @override
  IndexerSourceType get type => IndexerSourceType.api;

  const ThePirateBayAdapter({TorrentHttpRequester? requester}) : _requester = requester;

  @override
  Future<List<TorrentIndexRecord>> search(
    String query, {
    TorrentCategory? category,
    int limit = 25,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];
    final encoded = Uri.encodeQueryComponent(clean);
    String catParam = '';
    if (category != null) {
      switch (category) {
        case TorrentCategory.movies:
        case TorrentCategory.tv:
        case TorrentCategory.anime:
          catParam = '&cat=200';
          break;
        case TorrentCategory.music:
          catParam = '&cat=100';
          break;
        case TorrentCategory.games:
          catParam = '&cat=400';
          break;
        case TorrentCategory.software:
          catParam = '&cat=300';
          break;
        default:
          break;
      }
    }

    final uri = Uri.parse('$baseUrl/q.php?q=$encoded$catParam');
    return _fetchAndParse(uri, limit, category);
  }

  @override
  Future<List<TorrentIndexRecord>> fetchRecent({int limit = 25}) async {
    final uri = Uri.parse('$baseUrl/precompiled/data_top100_all.json');
    return _fetchAndParse(uri, limit, null);
  }

  @override
  Future<bool> testConnection() async {
    try {
      final records = await search('debian', limit: 2);
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
      if (decoded is! List) return const [];

      final results = <TorrentIndexRecord>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final infoHashRaw = item['info_hash']?.toString().trim() ?? '';
        final name = item['name']?.toString().trim() ?? '';

        if (infoHashRaw.isEmpty || infoHashRaw == '0000000000000000000000000000000000000000' || name == 'No results returned') {
          continue;
        }

        final normalizedHash = TorrentNormalizer.normalizeInfoHashV1(infoHashRaw);
        if (normalizedHash == null) continue;

        final seeders = int.tryParse(item['seeders']?.toString() ?? '0') ?? 0;
        final leechers = int.tryParse(item['leechers']?.toString() ?? '0') ?? 0;
        final sizeBytes = int.tryParse(item['size']?.toString() ?? '0');
        final addedSec = int.tryParse(item['added']?.toString() ?? '0');
        final pubDate = (addedSec != null && addedSec > 0)
            ? DateTime.fromMillisecondsSinceEpoch(addedSec * 1000, isUtc: true)
            : null;

        final rawCat = item['category']?.toString() ?? '';
        final cat = requestedCat ?? _mapCategory(rawCat);

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
          id: 'tpb_${normalizedHash}_${results.length}',
          sourceId: sourceId,
          sourceName: sourceName,
          sourceUrl: 'https://thepiratebay.org/description.php?id=${item["id"] ?? ""}',
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

  TorrentCategory _mapCategory(String raw) {
    if (raw.startsWith('1')) return TorrentCategory.music;
    if (raw.startsWith('2')) return TorrentCategory.movies;
    if (raw.startsWith('3')) return TorrentCategory.software;
    if (raw.startsWith('4')) return TorrentCategory.games;
    if (raw.startsWith('6')) return TorrentCategory.other;
    return TorrentCategory.other;
  }
}
