import 'dart:convert';
import 'package:nix_transport/nix_transport.dart';
import '../models/indexer_source_config.dart';
import '../models/torrent_record.dart';
import '../models/torrent_search_query.dart';

typedef OnlineApiRequestHandler = Future<({int statusCode, Map<String, dynamic> body})> Function(
  String method,
  String path, {
  Map<String, String> queryParams,
  Map<String, dynamic>? jsonBody,
});

/// Cliente online do Nix Torrent Index.
/// Conecta-se à API de busca remota via Tor Onion v3 (fail-closed) com isolamento estrito de circuito.
class TorrentOnlineClient {
  final String onionAddress;
  final int socksPort;
  final OnlineApiRequestHandler? _localApiHandler;

  const TorrentOnlineClient({
    this.onionAddress = 'nixsearch7k7u2b3s89h2f9v7x4b6p0o1w5e4r3t2y1u0i9o8p7a6s5d4.onion',
    this.socksPort = 9050,
    OnlineApiRequestHandler? localApiHandler,
  }) : _localApiHandler = localApiHandler;

  /// Pesquisa no índice online centralizado do Nix (Modo B).
  Future<TorrentSearchResult> searchOnline(
    TorrentSearchQuery query, {
    required bool userConsent,
    required bool isTorReady,
  }) async {
    _assertConsentAndTor(userConsent, isTorReady);

    final params = <String, String>{
      'query': query.query.trim(),
      'page': query.page.toString(),
      'page_size': query.pageSize.toString(),
      'sort': query.sort.slug,
    };
    if (query.categories.isNotEmpty) {
      params['category'] = query.categories.first.slug;
    }
    if (query.minSeeders != null && query.minSeeders! > 0) {
      params['min_seeds'] = query.minSeeders!.toString();
    }

    final response = await _request('GET', '/v1/index/search', queryParams: params);
    if (response.statusCode != 200) {
      throw Exception('Erro na consulta ao índice online (HTTP ${response.statusCode})');
    }

    final body = response.body;
    final rawList = body['records'] as List<dynamic>? ?? const [];
    final records = rawList
        .whereType<Map<String, dynamic>>()
        .map((m) => TorrentIndexRecord.fromMap(m))
        .toList();

    return TorrentSearchResult(
      query: query,
      records: records,
      totalCount: body['totalCount'] as int? ?? records.length,
      page: body['page'] as int? ?? query.page,
      pageSize: body['pageSize'] as int? ?? query.pageSize,
      mode: TorrentSearchMode.online,
      executedAt: DateTime.now(),
    );
  }

  /// Executa busca federada em tempo real nos conectores externos autorizados (Modo C).
  Future<TorrentSearchResult> searchLiveFederated(
    TorrentSearchQuery query, {
    required bool userConsent,
    required bool isTorReady,
  }) async {
    _assertConsentAndTor(userConsent, isTorReady);

    final payload = <String, dynamic>{
      'query': query.query.trim(),
      'sort': query.sort.slug,
    };
    if (query.categories.isNotEmpty) {
      payload['category'] = query.categories.first.slug;
    }
    if (query.minSeeders != null && query.minSeeders! > 0) {
      payload['min_seeds'] = query.minSeeders!;
    }

    final response = await _request('POST', '/v1/index/live-search', jsonBody: payload);
    if (response.statusCode != 200) {
      throw Exception('Erro na busca federada ao vivo (HTTP ${response.statusCode})');
    }

    final body = response.body;
    final rawList = body['records'] as List<dynamic>? ?? const [];
    final records = rawList
        .whereType<Map<String, dynamic>>()
        .map((m) => TorrentIndexRecord.fromMap(m))
        .toList();

    final rawWarnings = body['warnings'] as List<dynamic>? ?? const [];
    final warnings = rawWarnings.map((e) => e.toString()).toList();

    return TorrentSearchResult(
      query: query,
      records: records,
      totalCount: body['totalCount'] as int? ?? records.length,
      page: 1,
      pageSize: records.length,
      mode: TorrentSearchMode.liveFederated,
      isCached: body['isCached'] as bool? ?? false,
      warnings: warnings,
      executedAt: DateTime.now(),
    );
  }

  /// Recupera o estado operacional das fontes remotas.
  Future<List<TorrentIndexerSourceConfig>> fetchRemoteSources({
    required bool userConsent,
    required bool isTorReady,
  }) async {
    _assertConsentAndTor(userConsent, isTorReady);

    final response = await _request('GET', '/v1/index/sources');
    if (response.statusCode != 200) return const [];

    final rawList = response.body['sources'] as List<dynamic>? ?? const [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map((m) => TorrentIndexerSourceConfig.fromMap(m))
        .toList();
  }

  void _assertConsentAndTor(bool userConsent, bool isTorReady) {
    if (!userConsent) {
      throw StateError('A pesquisa online exige autorização explícita prévia do usuário.');
    }
    if (!isTorReady && _localApiHandler == null) {
      throw const TransportBlockedException(
        'Pesquisa externa bloqueada: o circuito Tor seguro não está ativo (fail-closed).',
      );
    }
  }

  Future<({int statusCode, Map<String, dynamic> body})> _request(
    String method,
    String path, {
    Map<String, String> queryParams = const {},
    Map<String, dynamic>? jsonBody,
  }) async {
    if (_localApiHandler != null) {
      return _localApiHandler!(method, path, queryParams: queryParams, jsonBody: jsonBody);
    }

    // Em produção via Tor SOCKS5 Onion v3
    final connector = Socks5Connector(
      proxyHost: '127.0.0.1',
      proxyPort: socksPort,
    );
    final queryString = queryParams.isNotEmpty
        ? '?${queryParams.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')}'
        : '';
    final uri = Uri.parse('http://$onionAddress$path$queryString');

    final res = await connector.httpRequest(
      method,
      uri,
      headers: const {
        'User-Agent': 'NixTorrentIndexClient/1.0',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonBody != null ? jsonEncode(jsonBody) : null,
      requireOnionV3: true,
      timeout: const Duration(seconds: 35),
    );

    try {
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      return (statusCode: res.statusCode, body: decoded);
    } catch (_) {
      return (statusCode: res.statusCode, body: <String, dynamic>{'raw': res.body});
    }
  }
}
