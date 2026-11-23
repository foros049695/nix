import '../engine/torrent_normalizer.dart';
import '../models/indexer_source_config.dart';
import '../models/torrent_record.dart';
import 'nix_indexer_adapter.dart';
import 'nyaa_rss_adapter.dart';

/// Adaptador soberano para indexadores Usenet compatíveis com o padrão Newznab / Torznab XML.
/// Suporta NZBHydra2, NzbPlanet, NZBFinder, usenet-crawler, altHUB, Spotweb e instâncias privadas.
class NewznabAdapter implements NixIndexerAdapter {
  final String id;
  final String name;
  final String url;
  final String? apiKey;
  final TorrentHttpRequester? _requester;

  @override
  String get sourceId => id;

  @override
  String get sourceName => name;

  @override
  String get baseUrl => url;

  @override
  IndexerSourceType get type => IndexerSourceType.torznab;

  const NewznabAdapter({
    required this.id,
    required this.name,
    required this.url,
    this.apiKey,
    TorrentHttpRequester? requester,
  }) : _requester = requester;

  @override
  Future<List<TorrentIndexRecord>> search(
    String query, {
    TorrentCategory? category,
    int limit = 25,
  }) async {
    final clean = query.trim();
    final encodedQ = Uri.encodeQueryComponent(clean);
    final keyParam = apiKey != null && apiKey!.isNotEmpty ? '&apikey=${Uri.encodeQueryComponent(apiKey!)}' : '';
    final catParam = category != null ? '&cat=${_mapCategoryToNewznab(category)}' : '';
    final targetUrl = '$baseUrl/api?t=search&q=$encodedQ$catParam$keyParam&o=xml';
    return _fetchAndParse(Uri.parse(targetUrl), limit);
  }

  @override
  Future<List<TorrentIndexRecord>> fetchRecent({int limit = 25}) async {
    final keyParam = apiKey != null && apiKey!.isNotEmpty ? '&apikey=${Uri.encodeQueryComponent(apiKey!)}' : '';
    final targetUrl = '$baseUrl/api?t=search$keyParam&o=xml';
    return _fetchAndParse(Uri.parse(targetUrl), limit);
  }

  @override
  Future<bool> testConnection() async {
    try {
      final keyParam = apiKey != null && apiKey!.isNotEmpty ? '&apikey=${Uri.encodeQueryComponent(apiKey!)}' : '';
      final capsUrl = '$baseUrl/api?t=caps$keyParam';
      if (_requester == null) return false;
      final res = await _requester!(
        'GET',
        Uri.parse(capsUrl),
        timeout: const Duration(seconds: 15),
      );
      if (res.statusCode == 200 && (res.body.contains('<caps') || res.body.contains('<server'))) {
        return true;
      }
      final testRes = await fetchRecent(limit: 1);
      return testRes.isNotEmpty;
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
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) NixNewznab/1.0',
          'Accept': 'application/xml, text/xml, */*',
        },
        timeout: const Duration(seconds: 25),
      );
      if (res.statusCode != 200) return const [];
      return parseNewznabXml(res.body, limit);
    } catch (_) {
      return const [];
    }
  }

  List<TorrentIndexRecord> parseNewznabXml(String xml, int limit) {
    final records = <TorrentIndexRecord>[];
    final itemPattern = RegExp(r'<item>([\s\S]*?)<\/item>', caseSensitive: false);
    final matches = itemPattern.allMatches(xml);

    for (final m in matches) {
      if (records.length >= limit) break;
      final block = m.group(1);
      if (block == null) continue;

      final titleMatch = RegExp(r'<title>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?<\/title>', caseSensitive: false).firstMatch(block);
      final rawTitle = titleMatch?.group(1)?.trim();
      if (rawTitle == null || rawTitle.isEmpty) continue;

      final encMatch = RegExp(r'<enclosure\s+url="([^"]+)"', caseSensitive: false).firstMatch(block);
      final downloadUrl = encMatch?.group(1)?.replaceAll('&amp;', '&');

      final sizeMatch = RegExp(r'<size>(\d+)<\/size>', caseSensitive: false).firstMatch(block) ??
          RegExp(r'<newznab:attr\s+name="size"\s+value="(\d+)"', caseSensitive: false).firstMatch(block) ??
          RegExp(r'<torznab:attr\s+name="size"\s+value="(\d+)"', caseSensitive: false).firstMatch(block);
      final sizeBytes = sizeMatch != null ? int.tryParse(sizeMatch.group(1)!) : null;

      final hashMatch = RegExp(r'<newznab:attr\s+name="infohash"\s+value="([0-9a-fA-F]{40})"', caseSensitive: false).firstMatch(block) ??
          RegExp(r'<torznab:attr\s+name="infohash"\s+value="([0-9a-fA-F]{40})"', caseSensitive: false).firstMatch(block);
      final infoHash = hashMatch != null ? TorrentNormalizer.normalizeInfoHashV1(hashMatch.group(1)!) : null;

      final pubDateMatch = RegExp(r'<pubDate>(.*?)<\/pubDate>', caseSensitive: false).firstMatch(block);
      DateTime? pubDate;
      if (pubDateMatch != null) {
        pubDate = DateTime.tryParse(pubDateMatch.group(1)!.trim());
      }

      final category = _inferCategory(rawTitle);
      final now = DateTime.now();

      records.add(TorrentIndexRecord(
        id: '${id}_${records.length}_${infoHash ?? rawTitle.hashCode.abs()}',
        sourceId: id,
        sourceName: name,
        sourceUrl: url,
        title: rawTitle,
        normalizedTitle: TorrentNormalizer.normalizeTitle(rawTitle),
        category: category,
        sizeBytes: sizeBytes,
        infoHashV1: infoHash,
        magnetUri: infoHash != null ? TorrentNormalizer.buildCanonicalMagnet(infoHashV1: infoHash, title: rawTitle) : null,
        torrentFileUrl: downloadUrl,
        publicationDate: pubDate,
        indexedAt: now,
        lastSeenAt: now,
      ));
    }

    return records;
  }

  static String _mapCategoryToNewznab(TorrentCategory cat) {
    switch (cat) {
      case TorrentCategory.movies:
        return '2000';
      case TorrentCategory.music:
        return '3000';
      case TorrentCategory.software:
      case TorrentCategory.games:
        return '4000';
      case TorrentCategory.tv:
      case TorrentCategory.anime:
        return '5000';
      case TorrentCategory.books:
      case TorrentCategory.manga:
        return '7000';
      default:
        return '';
    }
  }

  static TorrentCategory _inferCategory(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('1080p') || lower.contains('2160p') || lower.contains('bluray') || lower.contains('web-dl')) {
      return TorrentCategory.movies;
    }
    if (lower.contains('flac') || lower.contains('mp3') || lower.contains('lossless')) {
      return TorrentCategory.music;
    }
    if (lower.contains('epub') || lower.contains('pdf') || lower.contains('mobi')) {
      return TorrentCategory.books;
    }
    return TorrentCategory.other;
  }
}
