import 'package:flutter/foundation.dart';
import '../../core/media/catalog_database.dart';
import '../../core/media/media_catalog_service.dart';
import '../../core/media/media_index_updater.dart';

/// ViewModel desacoplado para o catálogo cultural offline, buscas FTS5, acervo pessoal e atualizações (Etapa 8).
class MediaViewModel extends ChangeNotifier {
  MediaCatalogService? _catalogService;
  CatalogDatabase? _catalogDatabase;
  CatalogUpdateManager? _catalogUpdateManager;

  List<CatalogWork> _searchResults = [];
  final Set<String> _savedAcervoIds = {};

  String _currentQuery = '';
  String? _currentKind;
  String? _currentGenre;
  int? _currentYear;

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _currentOffset = 0;
  String? _searchError;

  static const int defaultPageSize = 50;
  static const int maxMemoryItems = 500;

  MediaViewModel({
    MediaCatalogService? catalogService,
    CatalogDatabase? catalogDatabase,
    CatalogUpdateManager? updateManager,
    Set<String>? initialSavedIds,
  })  : _catalogService = catalogService,
        _catalogDatabase = catalogDatabase,
        _catalogUpdateManager = updateManager {
    if (initialSavedIds != null) {
      _savedAcervoIds.addAll(initialSavedIds);
    }
  }

  // Getters
  List<CatalogWork> get searchResults => List.unmodifiable(_searchResults);
  Set<String> get savedAcervoIds => Set.unmodifiable(_savedAcervoIds);
  String get currentQuery => _currentQuery;
  String? get currentKind => _currentKind;
  String? get currentGenre => _currentGenre;
  int? get currentYear => _currentYear;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  int get currentOffset => _currentOffset;
  String? get searchError => _searchError;
  int get resultCount => _searchResults.length;

  MediaCatalogService? get catalogService => _catalogService;
  CatalogDatabase? get catalogDatabase => _catalogDatabase;
  CatalogUpdateManager get updateManager =>
      _catalogUpdateManager ??= CatalogUpdateManager();

  void attachServices({
    MediaCatalogService? catalogService,
    CatalogDatabase? catalogDatabase,
    CatalogUpdateManager? updateManager,
  }) {
    if (catalogService != null) _catalogService = catalogService;
    if (catalogDatabase != null) _catalogDatabase = catalogDatabase;
    if (updateManager != null) _catalogUpdateManager = updateManager;
    notifyListeners();
  }

  bool isSaved(String id) => _savedAcervoIds.contains(id);

  void toggleSaveAcervoId(String id) {
    if (_savedAcervoIds.contains(id)) {
      _savedAcervoIds.remove(id);
    } else {
      _savedAcervoIds.add(id);
    }
    notifyListeners();
  }

  void setSavedAcervoIds(Iterable<String> ids) {
    _savedAcervoIds.clear();
    _savedAcervoIds.addAll(ids);
    notifyListeners();
  }

  /// Executa busca com paginação limpa e carregamento sob demanda.
  Future<void> search({
    required String query,
    String? kind,
    String? genre,
    int? releaseYear,
    bool refresh = true,
  }) async {
    final clean = query.trim();
    if (refresh) {
      _currentOffset = 0;
      _currentQuery = clean;
      _currentKind = kind;
      _currentGenre = genre;
      _currentYear = releaseYear;
      _searchResults = [];
      _isLoading = true;
      _searchError = null;
      notifyListeners();
    }

    try {
      List<CatalogWork> results = const [];
      if (_catalogDatabase != null) {
        results = await _catalogDatabase!.searchWorks(
          query: _currentQuery,
          kind: _currentKind,
          genre: _currentGenre,
          releaseYear: _currentYear,
          limit: defaultPageSize,
          offset: _currentOffset,
        );
      } else if (_catalogService != null) {
        results = await _catalogService!.searchCatalog(
          query: _currentQuery,
          kind: _currentKind,
          genre: _currentGenre,
          releaseYear: _currentYear,
          limit: defaultPageSize,
          offset: _currentOffset,
        );
      }

      if (refresh) {
        _searchResults = List.from(results);
      } else {
        _searchResults.addAll(results);
        // Otimização Etapa 8.2: Limite de memória para listas longas
        if (_searchResults.length > maxMemoryItems) {
          _searchResults = _searchResults.sublist(_searchResults.length - maxMemoryItems);
        }
      }

      _currentOffset += results.length;
      _hasMore = results.length >= defaultPageSize;
    } catch (e) {
      _searchError = e.toString();
      if (refresh) _searchResults = [];
    } finally {
      _isLoading = false;
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Carrega a próxima página de itens sob demanda.
  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();

    await search(
      query: _currentQuery,
      kind: _currentKind,
      genre: _currentGenre,
      releaseYear: _currentYear,
      refresh: false,
    );
  }

  void clearSearch() {
    _currentQuery = '';
    _currentKind = null;
    _currentGenre = null;
    _currentYear = null;
    _searchResults = [];
    _isLoading = false;
    _isLoadingMore = false;
    _hasMore = false;
    _currentOffset = 0;
    _searchError = null;
    notifyListeners();
  }
}
