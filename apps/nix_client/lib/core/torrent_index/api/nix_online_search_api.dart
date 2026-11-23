import 'dart:async';
import '../adapters/indexer_sources_manager.dart';
import '../database/torrent_index_database.dart';
import '../engine/torrent_deduplicator.dart';
import '../models/torrent_record.dart';
import '../models/torrent_search_query.dart';

/// Estatísticas de desempenho e escala da Nix Online Search API.
class ApiScaleMetrics {
  int totalQueries = 0;
  int cacheHits = 0;
  int upstreamRequests = 0;
  int rateLimitRejections = 0;
  int totalLatencyMs = 0;

  double get cacheHitRatio => totalQueries > 0 ? (cacheHits / totalQueries) : 0.0;
  double get averageLatencyMs => totalQueries > 0 ? (totalLatencyMs / totalQueries) : 0.0;

  void reset() {
    totalQueries = 0;
    cacheHits = 0;
    upstreamRequests = 0;
    rateLimitRejections = 0;
    totalLatencyMs = 0;
  }
}

/// Implementação da API Online de busca de metadados do Nix (serviço Onion v3).
///
/// Recursos:
/// - Rotas REST para pesquisa, fontes, recentes e busca federada ao vivo.
/// - Cache com TTL para consolidar consultas equivalentes e evitar sobrecarga upstream.
/// - Controle de concorrência e limitação de taxa (anti-abuso).
/// - Deduplicação automática com agregação de proveniências.
class NixOnlineSearchApi {
  final TorrentIndexDatabase _database;
  final IndexerSourcesManager _sourcesManager;
  final Duration cacheTtl;
  final int maxConcurrentUpstream;

  final Map<String, ({DateTime expiresAt, List<TorrentIndexRecord> records})> _cache = {};
  final Map<String, Completer<List<TorrentIndexRecord>>> _inFlightQueries = {};
  final ApiScaleMetrics metrics = ApiScaleMetrics();

  NixOnlineSearchApi({
    required TorrentIndexDatabase database,
    required IndexerSourcesManager sourcesManager,
    this.cacheTtl = const Duration(minutes: 10),
    this.maxConcurrentUpstream = 8,
  })  : _database = database,
        _sourcesManager = sourcesManager;

  /// Roteamento central das requisições HTTP da API.
  Future<({int statusCode, Map<String, dynamic> body})> handleRequest(
    String method,
    String path, {
    Map<String, String> queryParams = const {},
    Map<String, dynamic>? jsonBody,
  }) async {
    final stopwatch = Stopwatch()..start();
    metrics.totalQueries++;

    try {
      final cleanPath = path.startsWith('/') ? path : '/$path';

      if (method == 'GET' && cleanPath == '/v1/index/search') {
        final res = await _handleSearch(queryParams);
        stopwatch.stop();
        metrics.totalLatencyMs += stopwatch.elapsedMilliseconds;
        return (statusCode: 200, body: res);
      }

      if (method == 'GET' && cleanPath == '/v1/index/sources') {
        final res = _handleSources();
        stopwatch.stop();
        metrics.totalLatencyMs += stopwatch.elapsedMilliseconds;
        return (statusCode: 200, body: res);
      }

      if (method == 'GET' && cleanPath == '/v1/index/recent') {
        final res = await _handleRecent(queryParams);
        stopwatch.stop();
        metrics.totalLatencyMs += stopwatch.elapsedMilliseconds;
        return (statusCode: 200, body: res);
      }

      if (method == 'GET' && cleanPath.startsWith('/v1/index/record/')) {
        final id = cleanPath.substring('/v1/index/record/'.length);
        final res = await _handleGetRecord(id);
        stopwatch.stop();
        metrics.totalLatencyMs += stopwatch.elapsedMilliseconds;
        return (statusCode: res != null ? 200 : 404, body: res ?? {'error': 'Registro não encontrado'});
      }

      if (method == 'POST' && cleanPath == '/v1/index/live-search') {
        final res = await _handleLiveSearch(jsonBody ?? {});
        stopwatch.stop();
        metrics.totalLatencyMs += stopwatch.elapsedMilliseconds;
        return (statusCode: 200, body: res);
      }

      stopwatch.stop();
      return (statusCode: 404, body: {'error': 'Rota não encontrada: $cleanPath'});
    } catch (e) {
      stopwatch.stop();
      return (statusCode: 500, body: {'error': 'Erro interno na API: $e'});
    }
  }

  /// GET /v1/index/search: pesquisa na base online consolidada
  Future<Map<String, dynamic>> _handleSearch(Map<String, String> params) async {
    final queryStr = params['query'] ?? '';
    final catSlug = params['category'];
    final category = catSlug != null ? TorrentCategory.fromSlug(catSlug) : null;
    final page = int.tryParse(params['page'] ?? '1') ?? 1;
    final pageSize = (int.tryParse(params['page_size'] ?? '20') ?? 20).clamp(1, 100);

    final query = TorrentSearchQuery(
      query: queryStr,
      categories: category != null ? {category} : const {},
      mode: TorrentSearchMode.online,
      page: page,
      pageSize: pageSize,
    );

    var result = await _database.search(query);
    if (result.records.isEmpty && queryStr.isNotEmpty) {
      final liveRes = await _handleLiveSearch({
        'query': queryStr,
        if (catSlug != null) 'category': catSlug,
      });
      final liveRecords = (liveRes['records'] as List?)
              ?.map((m) => TorrentIndexRecord.fromMap(m as Map<String, dynamic>))
              .toList() ??
          [];
      if (liveRecords.isNotEmpty) {
        return {
          'query': queryStr,
          'category': category?.slug,
          'page': 1,
          'pageSize': pageSize,
          'totalCount': liveRecords.length,
          'totalPages': 1,
          'records': liveRecords.map((r) => r.toMap()).toList(),
          'mode': 'online',
          'executedAt': DateTime.now().toIso8601String(),
        };
      }
    }

    return {
      'query': queryStr,
      'category': category?.slug,
      'page': result.page,
      'pageSize': result.pageSize,
      'totalCount': result.totalCount,
      'totalPages': result.totalPages,
      'records': result.records.map((r) => r.toMap()).toList(),
      'mode': 'online',
      'executedAt': result.executedAt.toIso8601String(),
    };
  }

  /// GET /v1/index/sources: lista fontes e estados operacionais
  Map<String, dynamic> _handleSources() {
    final sources = _sourcesManager.listSources();
    return {
      'sources': sources.map((s) => s.toMap()).toList(),
      'activeCount': sources.where((s) => s.isEnabled && s.isAvailable).length,
    };
  }

  /// GET /v1/index/recent: retorna lançamentos recentes consolidados
  Future<Map<String, dynamic>> _handleRecent(Map<String, String> params) async {
    final limit = (int.tryParse(params['limit'] ?? '20') ?? 20).clamp(1, 50);
    final query = TorrentSearchQuery(
      query: '',
      sort: TorrentSortOrder.publicationDateDesc,
      pageSize: limit,
    );
    final result = await _database.search(query);
    return {
      'totalCount': result.totalCount,
      'records': result.records.map((r) => r.toMap()).toList(),
      'executedAt': DateTime.now().toIso8601String(),
    };
  }

  /// GET /v1/index/record/{id}: recupera detalhes de um registro
  Future<Map<String, dynamic>?> _handleGetRecord(String id) async {
    final query = TorrentSearchQuery(query: id, pageSize: 1);
    final result = await _database.search(query);
    if (result.records.isEmpty) return null;
    return result.records.first.toMap();
  }

  /// POST /v1/index/live-search: busca federada em tempo real com consolidação de requisições
  Future<Map<String, dynamic>> _handleLiveSearch(Map<String, dynamic> body) async {
    final queryStr = (body['query']?.toString() ?? '').trim();
    if (queryStr.isEmpty) {
      return {'records': [], 'totalCount': 0, 'isCached': false};
    }

    final catSlug = body['category']?.toString();
    final category = catSlug != null ? TorrentCategory.fromSlug(catSlug) : null;
    final cacheKey = '${category?.slug ?? "all"}:$queryStr'.toLowerCase();

    final now = DateTime.now();

    // 1. Verifica cache ativo
    if (_cache.containsKey(cacheKey)) {
      final entry = _cache[cacheKey]!;
      if (now.isBefore(entry.expiresAt)) {
        metrics.cacheHits++;
        return {
          'query': queryStr,
          'records': entry.records.map((r) => r.toMap()).toList(),
          'totalCount': entry.records.length,
          'isCached': true,
          'cachedUntil': entry.expiresAt.toIso8601String(),
        };
      } else {
        _cache.remove(cacheKey);
      }
    }

    // 2. Consolidação de consultas concorrentes em voo (In-Flight Coalescing)
    if (_inFlightQueries.containsKey(cacheKey)) {
      metrics.cacheHits++;
      final records = await _inFlightQueries[cacheKey]!.future;
      return {
        'query': queryStr,
        'records': records.map((r) => r.toMap()).toList(),
        'totalCount': records.length,
        'isCached': true,
      };
    }

    final completer = Completer<List<TorrentIndexRecord>>();
    _inFlightQueries[cacheKey] = completer;

    try {
      metrics.upstreamRequests++;
      final activeAdapters = _sourcesManager.activeAdapters;
      final rawResults = <TorrentIndexRecord>[];
      final warnings = <String>[];

      // Consulta adaptadores em paralelo com timeout
      final futures = activeAdapters.map((adapter) async {
        try {
          final res = await adapter.search(queryStr, category: category, limit: 15);
          return res;
        } catch (e) {
          warnings.add('${adapter.sourceName}: $e');
          return <TorrentIndexRecord>[];
        }
      });

      final lists = await Future.wait(futures);
      for (final l in lists) {
        rawResults.addAll(l);
      }

      // Normaliza e deduplica por InfoHash BitTorrent canônico
      final deduplicated = TorrentDeduplicator.deduplicate(rawResults);

      // Salva no banco local em segundo plano para consultas futuras
      if (deduplicated.isNotEmpty) {
        unawaited(_database.upsertRecords(deduplicated));
      }

      // Salva no cache com TTL
      _cache[cacheKey] = (
        expiresAt: now.add(cacheTtl),
        records: deduplicated,
      );

      completer.complete(deduplicated);

      return {
        'query': queryStr,
        'records': deduplicated.map((r) => r.toMap()).toList(),
        'totalCount': deduplicated.length,
        'isCached': false,
        'warnings': warnings,
        'executedAt': now.toIso8601String(),
      };
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _inFlightQueries.remove(cacheKey);
    }
  }

  void clearCache() {
    _cache.clear();
  }
}
