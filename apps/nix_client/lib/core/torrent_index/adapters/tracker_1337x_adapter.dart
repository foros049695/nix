import '../engine/torrent_normalizer.dart';
import '../models/indexer_source_config.dart';
import '../models/torrent_record.dart';
import 'nix_indexer_adapter.dart';
import 'nyaa_rss_adapter.dart';

/// Adaptador para 1337x com detecção ética e fail-safe de proteções Cloudflare/anti-bot.
/// Regra inegociável do Projeto Nix: NUNCA contornar CAPTCHA ou proteções.
/// Caso detectada proteção, sinaliza indisponibilidade e status de autorização pendente.
class Tracker1337xAdapter implements NixIndexerAdapter {
  final String _mirrorUrl;
  final TorrentHttpRequester? _requester;
  bool _isAvailable = true;
  String? _statusMessage;

  @override
  String get sourceId => '1337x';

  @override
  String get sourceName => '1337x';

  @override
  String get baseUrl => _mirrorUrl;

  @override
  IndexerSourceType get type => IndexerSourceType.api;

  bool get isAvailable => _isAvailable;
  String? get statusMessage => _statusMessage;

  Tracker1337xAdapter({
    String mirrorUrl = 'https://1337x.to',
    TorrentHttpRequester? requester,
  })  : _mirrorUrl = mirrorUrl,
        _requester = requester;

  @override
  Future<List<TorrentIndexRecord>> search(
    String query, {
    TorrentCategory? category,
    int limit = 25,
  }) async {
    final clean = query.trim();
    final encoded = Uri.encodeComponent(clean);
    final uri = Uri.parse('$baseUrl/search/$encoded/1/');
    return _fetchAndParse(uri, limit);
  }

  @override
  Future<List<TorrentIndexRecord>> fetchRecent({int limit = 25}) async {
    final uri = Uri.parse('$baseUrl/trending');
    return _fetchAndParse(uri, limit);
  }

  @override
  Future<bool> testConnection() async {
    if (_requester == null) return false;
    try {
      final uri = Uri.parse(baseUrl);
      final res = await _requester!('GET', uri, timeout: const Duration(seconds: 15));
      if (_isCloudflareChallenge(res.statusCode, res.body)) {
        _isAvailable = false;
        _statusMessage = 'Protegido por Cloudflare/desafio de acesso. Requer espelho autorizado ou proxy.';
        return false;
      }
      _isAvailable = res.statusCode == 200;
      _statusMessage = _isAvailable ? 'Operacional' : 'Código HTTP ${res.statusCode}';
      return _isAvailable;
    } catch (e) {
      _isAvailable = false;
      _statusMessage = 'Falha de conexão: $e';
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
          'Accept': 'text/html,application/xhtml+xml,application/xml',
        },
        timeout: const Duration(seconds: 25),
      );

      // Verificação de proteções Cloudflare
      if (_isCloudflareChallenge(res.statusCode, res.body)) {
        _isAvailable = false;
        _statusMessage = 'Acesso bloqueado por desafio Cloudflare. Operação externa interrompida sem burlar proteções.';
        return const [];
      }

      if (res.statusCode != 200) {
        _statusMessage = 'Resposta inesperada HTTP ${res.statusCode}';
        return const [];
      }

      _isAvailable = true;
      _statusMessage = 'Operacional';
      return parseHtml(res.body, limit);
    } catch (e) {
      _statusMessage = 'Erro na consulta: $e';
      return const [];
    }
  }

  /// Detecta se a resposta é um desafio anti-bot Cloudflare/Turnstile.
  bool _isCloudflareChallenge(int statusCode, String body) {
    if (statusCode == 403 || statusCode == 503) {
      final lower = body.toLowerCase();
      if (lower.contains('cloudflare') ||
          lower.contains('challenge-platform') ||
          lower.contains('cf-browser-verification') ||
          lower.contains('just a moment...') ||
          lower.contains('turnstile')) {
        return true;
      }
    }
    return false;
  }

  /// Analisador para páginas HTML de listagem do 1337x (quando servidas por espelho autorizado sem bloqueio).
  List<TorrentIndexRecord> parseHtml(String html, int limit) {
    final records = <TorrentIndexRecord>[];
    // Linhas da tabela de resultados: <tr>...<td>...<a href="/torrent/...">...
    final rowPattern = RegExp(r'<tr>([\s\S]*?)<\/tr>', caseSensitive: false);
    final linkPattern = RegExp(r'<a href="(/torrent/[^"]+)"[^>]*>([^<]+)</a>', caseSensitive: false);
    final seedsPattern = RegExp(r'<td class="coll-2[^"]*">([0-9]+)</td>', caseSensitive: false);
    final leechPattern = RegExp(r'<td class="coll-3[^"]*">([0-9]+)</td>', caseSensitive: false);
    final sizePattern = RegExp(r'<td class="coll-4[^"]*">([0-9.]+\s*[KMGT]?B)', caseSensitive: false);

    final rows = rowPattern.allMatches(html);
    for (final r in rows) {
      if (records.length >= limit) break;
      final block = r.group(1);
      if (block == null) continue;

      final linkMatch = linkPattern.firstMatch(block);
      if (linkMatch == null) continue;

      final path = linkMatch.group(1)!;
      final rawTitle = linkMatch.group(2)!.trim();
      if (rawTitle.isEmpty) continue;

      final seeders = int.tryParse(seedsPattern.firstMatch(block)?.group(1) ?? '');
      final leechers = int.tryParse(leechPattern.firstMatch(block)?.group(1) ?? '');
      final sizeStr = sizePattern.firstMatch(block)?.group(1);
      final sizeBytes = _parseSizeBytes(sizeStr);

      final fullUrl = '$baseUrl$path';
      final now = DateTime.now();

      records.add(TorrentIndexRecord(
        id: '1337x_${path.hashCode}',
        sourceId: sourceId,
        sourceName: sourceName,
        sourceUrl: fullUrl,
        title: rawTitle,
        normalizedTitle: TorrentNormalizer.normalizeTitle(rawTitle),
        category: TorrentCategory.other,
        sizeBytes: sizeBytes,
        seeders: seeders,
        leechers: leechers,
        indexedAt: now,
        lastSeenAt: now,
        provenances: [
          TorrentSourceProvenance(
            sourceId: sourceId,
            sourceName: sourceName,
            sourceUrl: fullUrl,
            seeders: seeders,
            leechers: leechers,
            observedAt: now,
          ),
        ],
      ));
    }

    return records;
  }

  static int? _parseSizeBytes(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final clean = raw.trim().toUpperCase();
    final numPart = RegExp(r'^([0-9]+(?:\.[0-9]+)?)').firstMatch(clean)?.group(1);
    if (numPart == null) return null;
    final value = double.tryParse(numPart);
    if (value == null) return null;

    if (clean.contains('GB')) return (value * 1024 * 1024 * 1024).round();
    if (clean.contains('MB')) return (value * 1024 * 1024).round();
    if (clean.contains('KB')) return (value * 1024).round();
    if (clean.contains('TB')) return (value * 1024 * 1024 * 1024 * 1024).round();
    return value.round();
  }
}
