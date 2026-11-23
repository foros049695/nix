import 'dart:convert';
import '../engine/torrent_normalizer.dart';
import '../models/indexer_source_config.dart';
import '../models/torrent_record.dart';
import 'nix_indexer_adapter.dart';
import 'nyaa_rss_adapter.dart';

/// Adaptador oficial para a API REST do YTS (filmes em domínio aberto / metadados).
/// Extrai hashes, qualidade, seeders reais e tamanho exato em bytes.
class YtsApiAdapter implements NixIndexerAdapter {
  final TorrentHttpRequester? _requester;

  @override
  String get sourceId => 'yts';

  @override
  String get sourceName => 'YTS.mx';

  @override
  String get baseUrl => 'https://yts.mx/api/v2';

  @override
  IndexerSourceType get type => IndexerSourceType.api;

  const YtsApiAdapter({TorrentHttpRequester? requester}) : _requester = requester;

  @override
  Future<List<TorrentIndexRecord>> search(
    String query, {
    TorrentCategory? category,
    int limit = 25,
  }) async {
    final clean = query.trim();
    final encoded = Uri.encodeQueryComponent(clean);
    final uri = Uri.parse('$baseUrl/list_movies.json?query_term=$encoded&limit=$limit');
    return _fetchAndParse(uri, limit);
  }

  @override
  Future<List<TorrentIndexRecord>> fetchRecent({int limit = 25}) async {
    final uri = Uri.parse('$baseUrl/list_movies.json?sort_by=date_added&limit=$limit');
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
          'Accept': 'application/json',
        },
        timeout: const Duration(seconds: 25),
      );
      if (res.statusCode != 200) return const [];
      return parseJson(res.body, limit);
    } catch (_) {
      return const [];
    }
  }

  /// Analisador do JSON retornado pela API do YTS.
  List<TorrentIndexRecord> parseJson(String jsonStr, int limit) {
    final records = <TorrentIndexRecord>[];
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return const [];
      final status = decoded['status'];
      if (status != 'ok') return const [];

      final data = decoded['data'];
      if (data is! Map) return const [];
      final movies = data['movies'];
      if (movies is! List) return const [];

      final now = DateTime.now();

      for (final m in movies) {
        if (records.length >= limit) break;
        if (m is! Map) continue;

        final title = (m['title_long'] ?? m['title'] ?? 'Filme')?.toString() ?? 'Filme';
        final torrents = m['torrents'];
        if (torrents is! List) continue;

        for (final t in torrents) {
          if (records.length >= limit) break;
          if (t is! Map) continue;

          final rawHash = t['hash']?.toString();
          final infoHashV1 = TorrentNormalizer.normalizeInfoHashV1(rawHash);
          if (infoHashV1 == null) continue;

          final quality = t['quality']?.toString() ?? '';
          final type = t['type']?.toString() ?? '';
          final seeds = t['seeds'] as int?;
          final peers = t['peers'] as int?;
          final sizeBytes = t['size_bytes'] as int?;
          final dateUploaded = t['date_uploaded']?.toString();
          final pubDate = dateUploaded != null ? DateTime.tryParse(dateUploaded) : null;

          final releaseTitle = '$title [$quality] [$type]';
          final magnet = TorrentNormalizer.buildCanonicalMagnet(
            infoHashV1: infoHashV1,
            title: releaseTitle,
            trackers: const [
              'udp://open.demonii.com:1337/announce',
              'udp://tracker.openbittorrent.com:80',
              'udp://tracker.coppersurfer.tk:6969',
              'udp://glotorrents.pw:6969/announce',
              'udp://tracker.opentrackr.org:1337/announce',
            ],
          );

          records.add(TorrentIndexRecord(
            id: infoHashV1,
            sourceId: sourceId,
            sourceName: sourceName,
            sourceUrl: m['url']?.toString(),
            title: releaseTitle,
            normalizedTitle: TorrentNormalizer.normalizeTitle(title),
            category: TorrentCategory.movies,
            subcategory: quality.isNotEmpty ? quality : null,
            sizeBytes: sizeBytes,
            publicationDate: pubDate,
            infoHashV1: infoHashV1,
            magnetUri: magnet,
            seeders: seeds,
            leechers: peers,
            indexedAt: now,
            lastSeenAt: now,
            provenances: [
              TorrentSourceProvenance(
                sourceId: sourceId,
                sourceName: sourceName,
                sourceUrl: m['url']?.toString(),
                seeders: seeds,
                leechers: peers,
                observedAt: now,
              ),
            ],
          ));
        }
      }
    } catch (_) {
      return records;
    }
    return records;
  }
}
