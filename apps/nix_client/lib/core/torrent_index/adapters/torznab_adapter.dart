import '../engine/torrent_normalizer.dart';
import '../models/indexer_source_config.dart';
import '../models/torrent_record.dart';
import 'nix_indexer_adapter.dart';
import 'nyaa_rss_adapter.dart';

/// Adaptador para indexadores compatíveis com o padrão Torznab / Newznab XML.
/// Opcional: permite aos usuários integrar seus próprios servidores sem dependência obrigatória.
class TorznabAdapter implements NixIndexerAdapter {
  final String _id;
  final String _name;
  final String _url;
  final String? _apiKey;
  final TorrentHttpRequester? _requester;

  @override
  String get sourceId => _id;

  @override
  String get sourceName => _name;

  @override
  String get baseUrl => _url;

  @override
  IndexerSourceType get type => IndexerSourceType.torznab;

  const TorznabAdapter({
    String id = 'torznab_custom',
    String name = 'Torznab Padrão',
    required String url,
    String? apiKey,
    TorrentHttpRequester? requester,
  })  : _id = id,
        _name = name,
        _url = url,
        _apiKey = apiKey,
        _requester = requester;

  @override
  Future<List<TorrentIndexRecord>> search(
    String query, {
    TorrentCategory? category,
    int limit = 25,
  }) async {
    final clean = query.trim();
    final encoded = Uri.encodeQueryComponent(clean);
    final keyParam = (_apiKey != null && _apiKey!.isNotEmpty) ? '&apikey=$_apiKey' : '';
    final uri = Uri.parse('$baseUrl/api?t=search&q=$encoded$keyParam&limit=$limit');
    return _fetchAndParse(uri, limit);
  }

  @override
  Future<List<TorrentIndexRecord>> fetchRecent({int limit = 25}) async {
    final keyParam = (_apiKey != null && _apiKey!.isNotEmpty) ? '&apikey=$_apiKey' : '';
    final uri = Uri.parse('$baseUrl/api?t=search$keyParam&limit=$limit');
    return _fetchAndParse(uri, limit);
  }

  @override
  Future<bool> testConnection() async {
    try {
      final keyParam = (_apiKey != null && _apiKey!.isNotEmpty) ? '&apikey=$_apiKey' : '';
      final uri = Uri.parse('$baseUrl/api?t=caps$keyParam');
      if (_requester == null) return false;
      final res = await _requester!('GET', uri, timeout: const Duration(seconds: 15));
      return res.statusCode == 200 && res.body.contains('<caps>');
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
          'User-Agent': 'NixTorrentIndex/1.0',
          'Accept': 'application/rss+xml, application/xml, text/xml',
        },
        timeout: const Duration(seconds: 25),
      );
      if (res.statusCode != 200) return const [];
      return parseXml(res.body, limit);
    } catch (_) {
      return const [];
    }
  }

  List<TorrentIndexRecord> parseXml(String xml, int limit) {
    final records = <TorrentIndexRecord>[];
    final itemPattern = RegExp(r'<item>([\s\S]*?)<\/item>', caseSensitive: false);
    final matches = itemPattern.allMatches(xml);

    for (final match in matches) {
      if (records.length >= limit) break;
      final item = match.group(1);
      if (item == null) continue;

      final title = _extractTag(item, 'title');
      if (title == null || title.isEmpty) continue;

      final link = _extractTag(item, 'link');
      final guid = _extractTag(item, 'guid');
      final pubDateStr = _extractTag(item, 'pubDate');
      final pubDate = pubDateStr != null ? DateTime.tryParse(pubDateStr) : null;

      // Atributos Torznab
      final infoHashRaw = _extractTorznabAttr(item, 'infohash') ?? _extractTag(item, 'torznab:infohash');
      final infoHashV1 = TorrentNormalizer.normalizeInfoHashV1(infoHashRaw) ??
          TorrentNormalizer.extractInfoHashFromMagnet(link);

      final seedersStr = _extractTorznabAttr(item, 'seeders');
      final peersStr = _extractTorznabAttr(item, 'peers');
      final seeders = int.tryParse(seedersStr ?? '');
      final leechers = int.tryParse(peersStr ?? '');

      final sizeStr = _extractTorznabAttr(item, 'size') ?? _extractTag(item, 'size') ?? _extractEnclosureLength(item);
      final sizeBytes = int.tryParse(sizeStr ?? '');

      final magnetUrl = _extractTorznabAttr(item, 'magneturl') ?? ((link != null && link.startsWith('magnet:?')) ? link : null);

      final catRaw = _extractTorznabAttr(item, 'category');
      final category = _mapTorznabCategory(catRaw);

      final now = DateTime.now();
      records.add(TorrentIndexRecord(
        id: infoHashV1 ?? 'torznab_${guid ?? title.hashCode}',
        sourceId: sourceId,
        sourceName: sourceName,
        sourceUrl: guid ?? link,
        title: title,
        normalizedTitle: TorrentNormalizer.normalizeTitle(title),
        category: category,
        sizeBytes: sizeBytes,
        publicationDate: pubDate,
        infoHashV1: infoHashV1,
        magnetUri: magnetUrl,
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
      return match.group(1)!.trim().replaceAll('<![CDATA[', '').replaceAll(']]>', '');
    }
    return null;
  }

  static String? _extractTorznabAttr(String xml, String name) {
    final pattern = RegExp('name=["\']$name["\'][^>]*value=["\']([^"\']*)["\']', caseSensitive: false);
    final match = pattern.firstMatch(xml);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    final altPattern = RegExp('value=["\']([^"\']*)["\'][^>]*name=["\']$name["\']', caseSensitive: false);
    final altMatch = altPattern.firstMatch(xml);
    if (altMatch != null && altMatch.groupCount >= 1) {
      return altMatch.group(1);
    }
    return null;
  }

  static String? _extractEnclosureLength(String xml) {
    final pattern = RegExp('<enclosure[^>]*length=["\']([0-9]+)["\']', caseSensitive: false);
    final match = pattern.firstMatch(xml);
    return match?.group(1);
  }

  static TorrentCategory _mapTorznabCategory(String? catStr) {
    if (catStr == null) return TorrentCategory.other;
    final catInt = int.tryParse(catStr) ?? 0;
    if (catInt >= 2000 && catInt < 3000) return TorrentCategory.movies;
    if (catInt >= 5000 && catInt < 6000) return TorrentCategory.tv;
    if (catInt >= 3000 && catInt < 4000) return TorrentCategory.music;
    if (catInt >= 7000 && catInt < 8000) return TorrentCategory.books;
    if (catInt >= 4000 && catInt < 5000) return TorrentCategory.software;
    if (catInt >= 1000 && catInt < 2000) return TorrentCategory.games;
    return TorrentCategory.other;
  }
}
