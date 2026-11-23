import '../engine/torrent_normalizer.dart';
import '../models/indexer_source_config.dart';
import '../models/torrent_record.dart';
import 'nix_indexer_adapter.dart';
import 'nyaa_rss_adapter.dart';

/// Adaptador para o buscador aberto Usenet Binsearch (https://binsearch.info).
/// Consulta e extrai registros binários públicos com títulos, tamanhos e identificadores.
class BinsearchAdapter implements NixIndexerAdapter {
  final TorrentHttpRequester? _requester;

  @override
  String get sourceId => 'binsearch';

  @override
  String get sourceName => 'Binsearch (Usenet)';

  @override
  String get baseUrl => 'https://binsearch.info';

  @override
  IndexerSourceType get type => IndexerSourceType.api;

  const BinsearchAdapter({TorrentHttpRequester? requester}) : _requester = requester;

  @override
  Future<List<TorrentIndexRecord>> search(
    String query, {
    TorrentCategory? category,
    int limit = 25,
  }) async {
    final clean = query.trim();
    final encoded = Uri.encodeQueryComponent(clean);
    final uri = Uri.parse('$baseUrl/?q=$encoded&max=$limit');
    return _fetchAndParse(uri, limit);
  }

  @override
  Future<List<TorrentIndexRecord>> fetchRecent({int limit = 25}) async {
    final uri = Uri.parse('$baseUrl/?max=$limit');
    return _fetchAndParse(uri, limit);
  }

  @override
  Future<bool> testConnection() async {
    try {
      if (_requester == null) return false;
      final res = await _requester!(
        'GET',
        Uri.parse(baseUrl),
        timeout: const Duration(seconds: 15),
      );
      return res.statusCode == 200 && res.body.contains('binsearch');
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
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) NixUsenetSearch/1.0',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
        timeout: const Duration(seconds: 25),
      );
      if (res.statusCode != 200) return const [];
      return parseBinsearchHtml(res.body, limit);
    } catch (_) {
      return const [];
    }
  }

  List<TorrentIndexRecord> parseBinsearchHtml(String html, int limit) {
    final records = <TorrentIndexRecord>[];
    // Extrai linhas da tabela de resultados
    final rowPattern = RegExp(r'<tr[^>]*>([\s\S]*?)<\/tr>', caseSensitive: false);
    final rows = rowPattern.allMatches(html);

    for (final row in rows) {
      if (records.length >= limit) break;
      final block = row.group(1);
      if (block == null || !block.contains('class="s"') && !block.contains('name="')) continue;

      // Extrai nome do release
      final titleMatch = RegExp(r'<span\s+class="s"[^>]*>([^<]+)<\/span>', caseSensitive: false).firstMatch(block) ??
          RegExp(r'<a\s+href="[^"]*view[^"]*"[^>]*>([^<]+)<\/a>', caseSensitive: false).firstMatch(block);
      final rawTitle = titleMatch?.group(1)?.trim();
      if (rawTitle == null || rawTitle.isEmpty) continue;

      // Extrai tamanho se disponível (ex: size: 4.2 GB)
      final sizeMatch = RegExp(r'size:\s*([\d\.]+)\s*(GB|MB|KB|B)', caseSensitive: false).firstMatch(block);
      int? sizeBytes;
      if (sizeMatch != null) {
        final numVal = double.tryParse(sizeMatch.group(1)!) ?? 0;
        final unit = sizeMatch.group(2)!.toUpperCase();
        if (unit == 'GB') {
          sizeBytes = (numVal * 1024 * 1024 * 1024).round();
        } else if (unit == 'MB') {
          sizeBytes = (numVal * 1024 * 1024).round();
        } else if (unit == 'KB') {
          sizeBytes = (numVal * 1024).round();
        } else {
          sizeBytes = numVal.round();
        }
      }

      final now = DateTime.now();
      records.add(TorrentIndexRecord(
        id: 'binsearch_${records.length}_${rawTitle.hashCode.abs()}',
        sourceId: sourceId,
        sourceName: sourceName,
        sourceUrl: baseUrl,
        title: rawTitle,
        normalizedTitle: TorrentNormalizer.normalizeTitle(rawTitle),
        category: TorrentCategory.other,
        sizeBytes: sizeBytes,
        indexedAt: now,
        lastSeenAt: now,
      ));
    }

    return records;
  }
}
