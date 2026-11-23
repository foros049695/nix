import '../engine/torrent_normalizer.dart';
import '../models/indexer_source_config.dart';
import '../models/torrent_record.dart';
import 'nix_indexer_adapter.dart';
import 'nyaa_rss_adapter.dart';

/// Adaptador para o Knaben (agregador público multi-tracker com ordenação por seeds).
class KnabenAdapter implements NixIndexerAdapter {
  final TorrentHttpRequester? _requester;

  @override
  String get sourceId => 'knaben';

  @override
  String get sourceName => 'Knaben';

  @override
  String get baseUrl => 'https://knaben.org';

  @override
  IndexerSourceType get type => IndexerSourceType.api;

  const KnabenAdapter({TorrentHttpRequester? requester}) : _requester = requester;

  @override
  Future<List<TorrentIndexRecord>> search(
    String query, {
    TorrentCategory? category,
    int limit = 25,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];
    final encoded = Uri.encodeComponent(clean);
    final uri = Uri.parse('$baseUrl/search/$encoded/0/1/seeders');
    return _fetchAndParse(uri, limit, category);
  }

  @override
  Future<List<TorrentIndexRecord>> fetchRecent({int limit = 25}) async {
    final uri = Uri.parse('$baseUrl/search//0/1/time');
    return _fetchAndParse(uri, limit, null);
  }

  @override
  Future<bool> testConnection() async {
    try {
      final records = await search('ubuntu', limit: 2);
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
          'Accept': 'text/html,application/xhtml+xml',
        },
        timeout: const Duration(seconds: 25),
      );
      if (res.statusCode != 200) return const [];
      return parseHtml(res.body, limit, requestedCat);
    } catch (_) {
      return const [];
    }
  }

  List<TorrentIndexRecord> parseHtml(String html, int limit, [TorrentCategory? requestedCat]) {
    try {
      final results = <TorrentIndexRecord>[];
      // Regex para capturar linhas da tabela com hash/magnet, título, tamanho em bytes e seeds
      final rowRegex = RegExp(r'<tr[^>]*>([\s\S]*?)<\/tr>', caseSensitive: false);
      final magnetRegex = RegExp(r'href="(magnet:\?xt=urn:btih:([^"&]+)[^"]*)"', caseSensitive: false);
      final titleRegex = RegExp(r'<a[^>]+title="([^"]+)"[^>]*href="magnet:', caseSensitive: false);
      final sizeBytesRegex = RegExp(r'title="(\d+)\s*Bytes"', caseSensitive: false);
      final dateRegex = RegExp(r'title="(\d{4}-\d{2}-\d{2}[^"]*)"', caseSensitive: false);
      final seedsRegex = RegExp(r'<td>(\d+)<\/td>', caseSensitive: false);

      for (final match in rowRegex.allMatches(html)) {
        final rowContent = match.group(1);
        if (rowContent == null) continue;

        final magMatch = magnetRegex.firstMatch(rowContent);
        if (magMatch == null) continue;

        final rawMagnet = magMatch.group(1)!;
        final rawHash = magMatch.group(2)!;
        final normalizedHash = TorrentNormalizer.normalizeInfoHashV1(rawHash);
        if (normalizedHash == null) continue;

        final titleMatch = titleRegex.firstMatch(rowContent);
        final title = titleMatch?.group(1) ?? 'Torrent $normalizedHash';

        final sizeMatch = sizeBytesRegex.firstMatch(rowContent);
        final sizeBytes = sizeMatch != null ? int.tryParse(sizeMatch.group(1)!) : null;

        final dateMatch = dateRegex.firstMatch(rowContent);
        DateTime? pubDate;
        if (dateMatch != null) {
          pubDate = DateTime.tryParse(dateMatch.group(1)!);
        }

        final seedMatches = seedsRegex.allMatches(rowContent).toList();
        int seeders = 0;
        int leechers = 0;
        if (seedMatches.isNotEmpty) {
          seeders = int.tryParse(seedMatches.last.group(1) ?? '0') ?? 0;
        }

        final cat = requestedCat ?? _guessCategory(title);

        results.add(TorrentIndexRecord(
          id: 'knaben_${normalizedHash}_${results.length}',
          sourceId: sourceId,
          sourceName: sourceName,
          sourceUrl: '$baseUrl/search',
          title: title,
          normalizedTitle: TorrentNormalizer.normalizeTitle(title),
          category: cat,
          sizeBytes: sizeBytes,
          seeders: seeders,
          leechers: leechers,
          infoHashV1: normalizedHash,
          magnetUri: rawMagnet,
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

  TorrentCategory _guessCategory(String title) {
    final lower = title.toLowerCase();
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
