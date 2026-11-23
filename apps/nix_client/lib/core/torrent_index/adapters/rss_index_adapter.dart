import '../engine/torrent_normalizer.dart';
import '../models/indexer_source_config.dart';
import '../models/torrent_record.dart';
import 'nix_indexer_adapter.dart';
import 'nyaa_rss_adapter.dart';

/// Adaptador genérico para feeds RSS 2.0 / Atom com enclosures ou links de torrents/magnets.
class RssIndexAdapter implements NixIndexerAdapter {
  final String _id;
  final String _name;
  final String _feedUrl;
  final TorrentCategory _defaultCategory;
  final TorrentHttpRequester? _requester;

  @override
  String get sourceId => _id;

  @override
  String get sourceName => _name;

  @override
  String get baseUrl => _feedUrl;

  @override
  IndexerSourceType get type => IndexerSourceType.rss;

  const RssIndexAdapter({
    String id = 'rss_custom',
    String name = 'Feed RSS Personalizado',
    required String feedUrl,
    TorrentCategory defaultCategory = TorrentCategory.other,
    TorrentHttpRequester? requester,
  })  : _id = id,
        _name = name,
        _feedUrl = feedUrl,
        _defaultCategory = defaultCategory,
        _requester = requester;

  @override
  Future<List<TorrentIndexRecord>> search(
    String query, {
    TorrentCategory? category,
    int limit = 25,
  }) async {
    // Para RSS estático, busca filtrando os itens retornados pelo feed
    final items = await fetchRecent(limit: 100);
    if (query.trim().isEmpty) return items.take(limit).toList();
    final lowerQ = query.trim().toLowerCase();
    return items
        .where((r) => r.title.toLowerCase().contains(lowerQ) || r.normalizedTitle.toLowerCase().contains(lowerQ))
        .take(limit)
        .toList();
  }

  @override
  Future<List<TorrentIndexRecord>> fetchRecent({int limit = 25}) async {
    if (_requester == null) return const [];
    try {
      final uri = Uri.parse(_feedUrl);
      final res = await _requester!(
        'GET',
        uri,
        headers: {
          'User-Agent': 'NixTorrentIndex/1.0',
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

  @override
  Future<bool> testConnection() async {
    try {
      final records = await fetchRecent(limit: 1);
      return records.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  List<TorrentIndexRecord> parseRss(String xml, int limit) {
    final records = <TorrentIndexRecord>[];
    final itemPattern = RegExp(r'<item>([\s\S]*?)<\/item>', caseSensitive: false);
    final matches = itemPattern.allMatches(xml);

    for (final m in matches) {
      if (records.length >= limit) break;
      final block = m.group(1);
      if (block == null) continue;

      final title = _extractTag(block, 'title');
      if (title == null || title.isEmpty) continue;

      final link = _extractTag(block, 'link');
      final guid = _extractTag(block, 'guid');
      final pubDateStr = _extractTag(block, 'pubDate');
      final pubDate = pubDateStr != null ? DateTime.tryParse(pubDateStr) : null;
      final magnetTag = _extractTag(block, 'torrent:magnetURI') ?? _extractTag(block, 'magnetURI');

      final encUrlMatch = RegExp('<enclosure[^>]*url=["\']([^"\']*)["\']', caseSensitive: false).firstMatch(block);
      final encLenMatch = RegExp('<enclosure[^>]*length=["\']([0-9]*)["\']', caseSensitive: false).firstMatch(block);
      final encUrl = encUrlMatch?.group(1);
      final encLen = int.tryParse(encLenMatch?.group(1) ?? '');

      final magnetUrl = magnetTag ?? ((link != null && link.startsWith('magnet:?')) ? link : null);
      final infoHashV1 = TorrentNormalizer.extractInfoHashFromMagnet(magnetUrl);

      final now = DateTime.now();
      records.add(TorrentIndexRecord(
        id: infoHashV1 ?? 'rss_${guid ?? title.hashCode}',
        sourceId: sourceId,
        sourceName: sourceName,
        sourceUrl: guid ?? link,
        title: title,
        normalizedTitle: TorrentNormalizer.normalizeTitle(title),
        category: _defaultCategory,
        sizeBytes: encLen,
        publicationDate: pubDate,
        infoHashV1: infoHashV1,
        magnetUri: magnetUrl,
        torrentFileUrl: encUrl ?? ((link != null && !link.startsWith('magnet:?')) ? link : null),
        indexedAt: now,
        lastSeenAt: now,
        provenances: [
          TorrentSourceProvenance(
            sourceId: sourceId,
            sourceName: sourceName,
            sourceUrl: guid ?? link,
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
      return match.group(1)!.trim().replaceAll('<![CDATA[', '').replaceAll(']]>', '');
    }
    return null;
  }
}
