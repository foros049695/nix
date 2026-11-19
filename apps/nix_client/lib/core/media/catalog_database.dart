import 'dart:convert';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/local_database.dart';
import '../security/platform_runtime.dart';

/// Obra do catálogo cultural offline do Nix.
class CatalogWork {
  final String id;
  final String kind; // 'movie', 'series', 'anime', 'manga', 'book'
  final String title;
  final String? originalTitle;
  final String? creators;
  final String? genres;
  final int? releaseYear;
  final String? summary;
  final String? coverThumb;
  final Map<String, dynamic> externalIds;
  final int updatedAt;

  const CatalogWork({
    required this.id,
    required this.kind,
    required this.title,
    this.originalTitle,
    this.creators,
    this.genres,
    this.releaseYear,
    this.summary,
    this.coverThumb,
    this.externalIds = const {},
    required this.updatedAt,
  });

  factory CatalogWork.fromRow(Map<String, dynamic> row) {
    Map<String, dynamic> parsedIds = {};
    try {
      final raw = row['external_ids_json'];
      if (raw is String && raw.isNotEmpty) {
        parsedIds = jsonDecode(raw) as Map<String, dynamic>;
      }
    } catch (_) {}

    return CatalogWork(
      id: row['id'] as String,
      kind: row['kind'] as String,
      title: row['title'] as String,
      originalTitle: row['original_title'] as String?,
      creators: row['creators'] as String?,
      genres: row['genres'] as String?,
      releaseYear: row['release_year'] as int?,
      summary: row['summary'] as String?,
      coverThumb: row['cover_thumb'] as String?,
      externalIds: parsedIds,
      updatedAt: row['updated_at'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind,
        'title': title,
        'original_title': originalTitle,
        'creators': creators,
        'genres': genres,
        'release_year': releaseYear,
        'summary': summary,
        'cover_thumb': coverThumb,
        'external_ids_json': jsonEncode(externalIds),
        'updated_at': updatedAt,
      };
}

/// Banco de dados SQLite offline do Nix Media Index.
///
/// Arquitetura:
/// - Armazenamento de metadados públicos abertos (Wikidata, Open Library, Anime Offline DB).
/// - Isolamento estrito: dados do catálogo NÃO são cifrados com o cofre do usuário (pois são públicos e redistribuíveis).
/// - As preferências privadas, avaliações e histórico do usuário residem exclusivamente no banco cifrado `nix_local_v4.db` (SQLCipher).
/// - Busca FTS5 de alta velocidade 100% offline, sem contato de rede.
class CatalogDatabase {
  final Database _db;
  final String path;

  CatalogDatabase._(this._db, this.path);

  Database get rawDatabase => _db;

  static String getDefaultCatalogPath() {
    return NixPlatformPaths.resolveDataFile('nix_catalog_v1.db');
  }

  /// Abre ou cria o banco do catálogo.
  static Future<CatalogDatabase> open({
    String? path,
    bool inMemory = false,
    bool readOnly = false,
  }) async {
    LocalDatabase.ensureSqliteInitialized();
    final dbFactory = databaseFactoryFfi;

    final resolvedPath = inMemory ? inMemoryDatabasePath : (path ?? getDefaultCatalogPath());

    if (!inMemory && resolvedPath != inMemoryDatabasePath) {
      final file = File(resolvedPath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
    }

    final db = await dbFactory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: readOnly ? null : 1,
        readOnly: readOnly,
        onCreate: readOnly
            ? null
            : (db, version) async {
                await _createSchema(db);
              },
      ),
    );

    // Garante que o schema FTS5 esteja pronto caso a base tenha sido criada vazia
    if (!readOnly) {
      await _createSchema(db);
    }

    return CatalogDatabase._(db, resolvedPath);
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_works (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL CHECK(kind IN ('movie','film','series','anime','manga','book')),
        title TEXT NOT NULL,
        original_title TEXT,
        creators TEXT,
        genres TEXT,
        release_year INTEGER,
        summary TEXT,
        cover_thumb TEXT,
        external_ids_json TEXT NOT NULL DEFAULT '{}',
        updated_at INTEGER NOT NULL
      );
    ''');

    // FTS5 para busca unificada
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS catalog_search USING fts5(
        work_id UNINDEXED,
        title,
        original_title,
        creators,
        genres,
        summary
      );
    ''');

    // Triggers de sincronização com FTS5
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_catalog_works_ai AFTER INSERT ON catalog_works BEGIN
        INSERT INTO catalog_search(work_id, title, original_title, creators, genres, summary)
        VALUES (new.id, new.title, coalesce(new.original_title, ''), coalesce(new.creators, ''), coalesce(new.genres, ''), coalesce(new.summary, ''));
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_catalog_works_ad AFTER DELETE ON catalog_works BEGIN
        DELETE FROM catalog_search WHERE work_id = old.id;
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_catalog_works_au AFTER UPDATE ON catalog_works BEGIN
        DELETE FROM catalog_search WHERE work_id = old.id;
        INSERT INTO catalog_search(work_id, title, original_title, creators, genres, summary)
        VALUES (new.id, new.title, coalesce(new.original_title, ''), coalesce(new.creators, ''), coalesce(new.genres, ''), coalesce(new.summary, ''));
      END;
    ''');
  }

  Future<void> setMeta(String key, String value) async {
    await _db.insert(
      'catalog_meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getMeta(String key) async {
    final rows = await _db.query(
      'catalog_meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<int> getVersion() async {
    final raw = await getMeta('version');
    if (raw == null) return 0;
    return int.tryParse(raw) ?? 0;
  }

  Future<int> getEntryCount() async {
    final res = await _db.rawQuery('SELECT COUNT(*) as count FROM catalog_works;');
    if (res.isEmpty) return 0;
    return (res.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<bool> integrityCheck() async {
    try {
      final res = await _db.rawQuery('PRAGMA integrity_check;');
      if (res.isEmpty) return false;
      final val = res.first.values.first.toString();
      return val.toLowerCase() == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<void> upsertWork(CatalogWork work) async {
    await _db.insert(
      'catalog_works',
      work.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> batchUpsertWorks(List<CatalogWork> works) async {
    final batch = _db.batch();
    for (final w in works) {
      batch.insert(
        'catalog_works',
        w.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<CatalogWork?> getWork(String id) async {
    final rows = await _db.query(
      'catalog_works',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CatalogWork.fromRow(rows.first);
  }

  /// Busca offline de obras no catálogo via FTS5.
  /// Suporta busca por prefixo ('query*') e filtros combinados por kind, gênero e ano.
  Future<List<CatalogWork>> searchWorks({
    required String query,
    String? kind,
    String? genre,
    int? releaseYear,
    int limit = 50,
    int offset = 0,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      // Se a query de busca for vazia mas houver filtros, lista os itens filtrados
      return listWorks(
        kind: kind,
        genre: genre,
        releaseYear: releaseYear,
        limit: limit,
        offset: offset,
      );
    }

    // Normaliza query para FTS5 com prefix matching em cada termo
    final tokens = clean
        .replaceAll(RegExp(r'[^\w\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((t) => '"$t"*')
        .join(' ');

    if (tokens.isEmpty) return [];

    final conditions = <String>['catalog_search MATCH ?'];
    final args = <dynamic>[tokens];

    if (kind != null && kind.isNotEmpty) {
      conditions.add('w.kind = ?');
      args.add(kind);
    }
    if (genre != null && genre.isNotEmpty) {
      conditions.add('w.genres LIKE ?');
      args.add('%$genre%');
    }
    if (releaseYear != null) {
      conditions.add('w.release_year = ?');
      args.add(releaseYear);
    }

    args.add(limit);
    args.add(offset);

    final whereClause = conditions.join(' AND ');
    final sql = '''
      SELECT w.*
      FROM catalog_works w
      JOIN catalog_search cs ON w.id = cs.work_id
      WHERE $whereClause
      ORDER BY w.release_year DESC, w.title ASC
      LIMIT ? OFFSET ?;
    ''';

    final rows = await _db.rawQuery(sql, args);
    return rows.map((r) => CatalogWork.fromRow(r)).toList();
  }

  Future<List<CatalogWork>> listWorks({
    String? kind,
    String? genre,
    int? releaseYear,
    int limit = 50,
    int offset = 0,
  }) async {
    final conditions = <String>[];
    final args = <dynamic>[];

    if (kind != null && kind.isNotEmpty) {
      conditions.add('kind = ?');
      args.add(kind);
    }
    if (genre != null && genre.isNotEmpty) {
      conditions.add('genres LIKE ?');
      args.add('%$genre%');
    }
    if (releaseYear != null) {
      conditions.add('release_year = ?');
      args.add(releaseYear);
    }

    final whereClause = conditions.isNotEmpty ? conditions.join(' AND ') : null;

    final rows = await _db.query(
      'catalog_works',
      where: whereClause,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'release_year DESC, title ASC',
      limit: limit,
      offset: offset,
    );

    return rows.map((r) => CatalogWork.fromRow(r)).toList();
  }

  Future<void> close() async {
    await _db.close();
  }
}
