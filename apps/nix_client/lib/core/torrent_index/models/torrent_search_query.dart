import 'torrent_record.dart';

/// Modos de pesquisa do Nix Torrent Index:
/// - `local`: Modo A — Pesquisa instantânea estritamente no banco SQLite local (offline, zero rede).
/// - `online`: Modo B — Consulta à API de índice Onion v3 do Nix via Tor.
/// - `liveFederated`: Modo C — Busca federada ao vivo nos conectores autorizados sob demanda.
enum TorrentSearchMode {
  local('local', 'Modo Local', 'Busca offline imediata no índice local SQLite FTS5'),
  online('online', 'Índice Online', 'Consulta ao índice centralizado Nix via Tor Onion v3'),
  liveFederated('liveFederated', 'Ao Vivo', 'Busca federada em tempo real nos indexadores autorizados');

  final String slug;
  final String label;
  final String description;
  const TorrentSearchMode(this.slug, this.label, this.description);
}

/// Critérios de ordenação dos resultados.
enum TorrentSortOrder {
  relevance('relevance', 'Relevância'),
  seedersDesc('seeders_desc', 'Mais Seeds'),
  publicationDateDesc('date_desc', 'Mais Recentes'),
  sizeAsc('size_asc', 'Menor Tamanho'),
  sizeDesc('size_desc', 'Maior Tamanho');

  final String slug;
  final String label;
  const TorrentSortOrder(this.slug, this.label);
}

/// Consulta estruturada de pesquisa no Nix Torrent Index.
class TorrentSearchQuery {
  final String query;
  final Set<TorrentCategory> categories;
  final Set<String> sources;
  final TorrentSearchMode mode;
  final TorrentSortOrder sort;
  final int page;
  final int pageSize;
  final int? minSizeBytes;
  final int? maxSizeBytes;
  final int? minSeeders;

  const TorrentSearchQuery({
    required this.query,
    this.categories = const {},
    this.sources = const {},
    this.mode = TorrentSearchMode.local,
    this.sort = TorrentSortOrder.relevance,
    this.page = 1,
    this.pageSize = 20,
    this.minSizeBytes,
    this.maxSizeBytes,
    this.minSeeders,
  });

  bool get isEmpty => query.trim().isEmpty && categories.isEmpty && sources.isEmpty;

  TorrentSearchQuery copyWith({
    String? query,
    Set<TorrentCategory>? categories,
    Set<String>? sources,
    TorrentSearchMode? mode,
    TorrentSortOrder? sort,
    int? page,
    int? pageSize,
    int? minSizeBytes,
    int? maxSizeBytes,
    int? minSeeders,
  }) {
    return TorrentSearchQuery(
      query: query ?? this.query,
      categories: categories ?? this.categories,
      sources: sources ?? this.sources,
      mode: mode ?? this.mode,
      sort: sort ?? this.sort,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      minSizeBytes: minSizeBytes ?? this.minSizeBytes,
      maxSizeBytes: maxSizeBytes ?? this.maxSizeBytes,
      minSeeders: minSeeders ?? this.minSeeders,
    );
  }
}

/// Resposta estruturada de uma pesquisa no Nix Torrent Index.
class TorrentSearchResult {
  final TorrentSearchQuery query;
  final List<TorrentIndexRecord> records;
  final int totalCount;
  final int page;
  final int pageSize;
  final TorrentSearchMode mode;
  final bool isCached;
  final List<String> observedSources;
  final List<String> warnings;
  final DateTime executedAt;

  const TorrentSearchResult({
    required this.query,
    required this.records,
    required this.totalCount,
    required this.page,
    required this.pageSize,
    required this.mode,
    this.isCached = false,
    this.observedSources = const [],
    this.warnings = const [],
    required this.executedAt,
  });

  int get totalPages => (totalCount / pageSize).ceil().clamp(1, 999999);
  bool get hasNextPage => page < totalPages;
  bool get hasPreviousPage => page > 1;

  factory TorrentSearchResult.empty(TorrentSearchQuery query) {
    return TorrentSearchResult(
      query: query,
      records: const [],
      totalCount: 0,
      page: query.page,
      pageSize: query.pageSize,
      mode: query.mode,
      executedAt: DateTime.now(),
    );
  }
}
