import '../engine/torrent_normalizer.dart';
import '../models/indexer_source_config.dart';
import '../models/torrent_record.dart';
import 'nix_indexer_adapter.dart';

typedef TorrentHttpRequester = Future<({int statusCode, String body})> Function(
  String method,
  Uri uri, {
  Map<String, String>? headers,
  String? body,
  Duration? timeout,
});

/// Adaptador para o índice Nyaa via feed RSS oficial.
/// Extrai metadados reais: infoHash, seeders, leechers, tamanho em bytes e data de publicação.
class NyaaRssAdapter implements NixIndexerAdapter {
  final TorrentHttpRequester? _requester;

  @override
  String get sourceId => 'nyaa';

  @override
  String get sourceName => 'Nyaa.si';

  @override
  String get baseUrl => 'https://nyaa.si';

  @override
  IndexerSourceType get type => IndexerSourceType.rss;

  const NyaaRssAdapter({TorrentHttpRequester? requester}) : _requester = requester;

  @override
  Future<List<TorrentIndexRecord>> search(
    String query, {
    TorrentCategory? category,
    int limit = 25,
  }) async {
    final clean = query.trim();
    final encoded = Uri.encodeQueryComponent(clean);
    final uri = Uri.parse('$baseUrl/?page=rss&q=$encoded&c=0_0&f=0');
    return _fetchAndParse(uri, limit);
  }

  @override
  Future<List<TorrentIndexRecord>> fetchRecent({int limit = 25}) async {
    final uri = Uri.parse('$baseUrl/?page=rss&c=0_0&f=0');
    return _fetchAndParse(uri, limit);
  }

  @override
  Future<bool> testConnection() async {
    try {
      final records = await fetchRecent(limit: 1);
      return records.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<List<TorrentIndexRecord>> _fetchAndParse(Uri uri, int limit) async {
    if (_requester == null) return const [];
    try {
      final res = await _requester!(
        'GET',
        uri,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) NixTorrentIndex/1.0',
          'Accept': 'application/rss+xml, application/xml, text/xml',
        },
        timeout: const Duration(seconds: 25),
      );
      if (res.statusCode != 200) return const [];
      return parseRss(res.body, limit);
    } catch (_) {
      return const [];
    }
  }

  /// Analisador do XML RSS do Nyaa.
  List<TorrentIndexRecord> parseRss(String xmlContent, int limit) {
    final records = <TorrentIndexRecord>[];
    final itemPattern = RegExp(r'<item>([\s\S]*?)<\/item>', caseSensitive: false);
    final matches = itemPattern.allMatches(xmlContent);

    for (final match in matches) {
      if (records.length >= limit) break;
      final itemBlock = match.group(1);
      if (itemBlock == null) continue;

      final title = _extractTag(itemBlock, 'title');
      if (title == null || title.isEmpty) continue;

      final link = _extractTag(itemBlock, 'link');
      final guid = _extractTag(itemBlock, 'guid');
      final pubDateStr = _extractTag(itemBlock, 'pubDate');
      final infoHashRaw = _extractTag(itemBlock, 'nyaa:infoHash');
      final seedersStr = _extractTag(itemBlock, 'nyaa:seeders');
      final leechersStr = _extractTag(itemBlock, 'nyaa:leechers');
      final sizeStr = _extractTag(itemBlock, 'nyaa:size');
      final categoryId = _extractTag(itemBlock, 'nyaa:categoryId');

      final seeders = int.tryParse(seedersStr ?? '');
      final leechers = int.tryParse(leechersStr ?? '');
      final sizeBytes = _parseSizeBytes(sizeStr);
      final pubDate = pubDateStr != null ? DateTime.tryParse(pubDateStr) : null;
      final infoHashV1 = TorrentNormalizer.normalizeInfoHashV1(infoHashRaw);

      // Determina categoria canônica: 3_1 e 3_2 costumam ser literatura/mangá, restante anime/música
      var cat = TorrentCategory.anime;
      if (categoryId != null) {
        if (categoryId.startsWith('3_') || categoryId.contains('manga')) {
          cat = TorrentCategory.manga;
        } else if (categoryId.startsWith('2_') || categoryId.contains('audio')) {
          cat = TorrentCategory.music;
        }
      }

      String? magnet;
      if (infoHashV1 != null) {
        magnet = TorrentNormalizer.buildCanonicalMagnet(
          infoHashV1: infoHashV1,
          title: title,
          trackers: const [
            'http://nyaa.tracker.wf:7777/announce',
            'udp://open.stealth.si:80/announce',
            'udp://tracker.opentrackr.org:1337/announce',
          ],
        );
      } else if (link != null && link.startsWith('magnet:?')) {
        magnet = link;
      }

      final now = DateTime.now();
      records.add(TorrentIndexRecord(
        id: infoHashV1 ?? 'nyaa_${guid ?? title.hashCode}',
        sourceId: sourceId,
        sourceName: sourceName,
        sourceUrl: guid ?? link,
        title: title,
        normalizedTitle: TorrentNormalizer.normalizeTitle(title),
        category: cat,
        subcategory: categoryId,
        sizeBytes: sizeBytes,
        publicationDate: pubDate,
        infoHashV1: infoHashV1,
        magnetUri: magnet,
        torrentFileUrl: (link != null && !link.startsWith('magnet:?')) ? link : null,
        seeders: seeders,
        leechers: leechers,
        indexedAt: now,
        lastSeenAt: now,
        provenances: [
          TorrentSourceProvenance(
            sourceId: sourceId,
            sourceName: sourceName,
            sourceUrl: guid ?? link,
            seeders: seeders,
            leechers: leechers,
            observedAt: now,
          ),
        ],
      ));
    }

    return records;
  }

  static String? _extractTag(String xml, String tagName) {
    final pattern = RegExp('<$tagName(?:[^>]*)>([\\s\\S]*?)<\\/$tagName>', caseSensitive: false);
    final match = pattern.firstMatch(xml);
    if (match != null && match.groupCount >= 1) {
      var content = match.group(1)!.trim();
      if (content.startsWith('<![CDATA[') && content.endsWith(']]>')) {
        content = content.substring(9, content.length - 3).trim();
      }
      return _unescapeXml(content);
    }
    return null;
  }

  static String _unescapeXml(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  static int? _parseSizeBytes(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final clean = raw.trim().toUpperCase();
    final numPart = RegExp(r'^([0-9]+(?:\.[0-9]+)?)').firstMatch(clean)?.group(1);
    if (numPart == null) return null;
    final value = double.tryParse(numPart);
    if (value == null) return null;

    if (clean.contains('TIB') || clean.contains('TB')) {
      return (value * 1024 * 1024 * 1024 * 1024).round();
    }
    if (clean.contains('GIB') || clean.contains('GB')) {
      return (value * 1024 * 1024 * 1024).round();
    }
    if (clean.contains('MIB') || clean.contains('MB')) {
      return (value * 1024 * 1024).round();
    }
    if (clean.contains('KIB') || clean.contains('KB')) {
      return (value * 1024).round();
    }
    if (clean.contains('B')) {
      return value.round();
    }
    return null;
  }
}
