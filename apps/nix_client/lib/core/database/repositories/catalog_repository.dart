import '../../media/catalog_database.dart';

/// Repositório para consulta ao catálogo público offline (Nix Media Index).
class CatalogRepository {
  final CatalogDatabase _catalogDb;

  CatalogRepository(this._catalogDb);

  CatalogDatabase get database => _catalogDb;

  Future<List<CatalogWork>> search({
    required String query,
    String? kind,
    String? genre,
    int? releaseYear,
    int limit = 50,
    int offset = 0,
  }) {
    return _catalogDb.searchWorks(
      query: query,
      kind: kind,
      genre: genre,
      releaseYear: releaseYear,
      limit: limit,
      offset: offset,
    );
  }

  Future<CatalogWork?> getWork(String id) {
    return _catalogDb.getWork(id);
  }

  Future<List<CatalogWork>> listWorks({
    String? kind,
    String? genre,
    int? releaseYear,
    int limit = 50,
    int offset = 0,
  }) {
    return _catalogDb.listWorks(
      kind: kind,
      genre: genre,
      releaseYear: releaseYear,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> getVersion() => _catalogDb.getVersion();

  Future<int> getEntryCount() => _catalogDb.getEntryCount();

  Future<bool> integrityCheck() => _catalogDb.integrityCheck();

  Future<void> upsertWork(CatalogWork work) => _catalogDb.upsertWork(work);

  Future<void> batchUpsertWorks(List<CatalogWork> works) =>
      _catalogDb.batchUpsertWorks(works);

  Future<void> setMeta(String key, String value) =>
      _catalogDb.setMeta(key, value);

  Future<String?> getMeta(String key) => _catalogDb.getMeta(key);
}
