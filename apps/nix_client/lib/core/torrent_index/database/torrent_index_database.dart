import 'dart:convert';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../database/local_database.dart';
import '../../security/platform_runtime.dart';
import '../models/torrent_record.dart';
import '../models/torrent_search_query.dart';

/// Banco de dados SQLite offline independente do Nix Torrent Index.
///
/// Arquitetura:
/// - Armazenamento de metadados de torrents com banco dedicado `torrent_index_v1.db`.
/// - Não polui o catálogo cultural público (`nix_catalog_v1.db`) nem o banco cifrado do usuário (`nix_local_v4.db`).
/// - Indexação textual de alta velocidade via SQLite FTS5 com suporte a buscas por prefixo e filtros combinados.
class TorrentIndexDatabase {
  final Database _db;
  final String path;

  TorrentIndexDatabase._(this._db, this.path);

  Database get rawDatabase => _db;

  static final _factory = createDatabaseFactoryFfi(ffiInit: LocalDatabase.ensureSqliteInitialized);

  static String getDefaultPath() {
    return NixPlatformPaths.resolveDataFile('torrent_index_v1.db');
  }

  /// Abre ou cria o banco do índice de torrents.
  static Future<TorrentIndexDatabase> open({
    String? path,
    bool inMemory = false,
    bool readOnly = false,
  }) async {
    final resolvedPath = inMemory ? inMemoryDatabasePath : (path ?? getDefaultPath());

    if (!inMemory && resolvedPath != inMemoryDatabasePath) {
      final file = File(resolvedPath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
    }

    final db = await _factory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: 1,
        readOnly: readOnly,
        singleInstance: false,
        onCreate: readOnly ? null : (db, version) async {
          await _createSchema(db);
        },
      ),
    );

    if (!readOnly) {
      await db.transaction(_createSchema);
    }
    return TorrentIndexDatabase._(db, resolvedPath);
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS torrent_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS torrent_records (
        id TEXT PRIMARY KEY,
        info_hash_v1 TEXT,
        info_hash_v2 TEXT,
        source_id TEXT NOT NULL,
        source_name TEXT NOT NULL,
        source_url TEXT,
        title TEXT NOT NULL,
        normalized_title TEXT NOT NULL,
        category TEXT NOT NULL,
        subcategory TEXT,
        size_bytes INTEGER,
        publication_date TEXT,
        magnet_uri TEXT,
        torrent_file_url TEXT,
        seeders INTEGER,
        leechers INTEGER,
        language TEXT,
        description TEXT,
        tags_json TEXT NOT NULL DEFAULT '[]',
        trust_metadata TEXT,
        indexed_at TEXT NOT NULL,
        last_seen_at TEXT NOT NULL,
        provenances_json TEXT NOT NULL DEFAULT '[]'
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_torrent_hash_v1 ON torrent_records(info_hash_v1);
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_torrent_category_seeders ON torrent_records(category, seeders DESC);
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_torrent_pub_date ON torrent_records(publication_date DESC);
    ''');

    // Tabela virtual FTS5 para busca textual ultra-rápida
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS torrent_search USING fts5(
        record_id UNINDEXED,
        title,
        normalized_title,
        description,
        tags
      );
    ''');

    // Triggers automáticos para manter o FTS5 sincronizado com torrent_records
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_torrent_records_ai AFTER INSERT ON torrent_records BEGIN
        INSERT INTO torrent_search(record_id, title, normalized_title, description, tags)
        VALUES (new.id, new.title, new.normalized_title, coalesce(new.description, ''), new.tags_json);
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_torrent_records_ad AFTER DELETE ON torrent_records BEGIN
        DELETE FROM torrent_search WHERE record_id = old.id;
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_torrent_records_au AFTER UPDATE ON torrent_records BEGIN
        DELETE FROM torrent_search WHERE record_id = old.id;
        INSERT INTO torrent_search(record_id, title, normalized_title, description, tags)
        VALUES (new.id, new.title, new.normalized_title, coalesce(new.description, ''), new.tags_json);
      END;
    ''');
  }

  /// Insere ou atualiza múltiplos registros em lote (transação atômica).
  Future<void> upsertRecords(List<TorrentIndexRecord> records) async {
    if (records.isEmpty) return;
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final rec in records) {
        batch.insert(
          'torrent_records',
          {
            'id': rec.id,
            'info_hash_v1': rec.infoHashV1,
            'info_hash_v2': rec.infoHashV2,
            'source_id': rec.sourceId,
            'source_name': rec.sourceName,
            'source_url': rec.sourceUrl,
            'title': rec.title,
            'normalized_title': rec.normalizedTitle,
            'category': rec.category.slug,
            'subcategory': rec.subcategory,
            'size_bytes': rec.sizeBytes,
            'publication_date': rec.publicationDate?.toIso8601String(),
            'magnet_uri': rec.magnetUri,
            'torrent_file_url': rec.torrentFileUrl,
            'seeders': rec.seeders,
            'leechers': rec.leechers,
            'language': rec.language,
            'description': rec.description,
            'tags_json': jsonEncode(rec.tags),
            'trust_metadata': rec.trustMetadata,
            'indexed_at': rec.indexedAt.toIso8601String(),
            'last_seen_at': rec.lastSeenAt.toIso8601String(),
            'provenances_json': jsonEncode(rec.provenances.map((p) => p.toMap()).toList()),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Executa pesquisa no catálogo local (Modo A).
  Future<TorrentSearchResult> search(TorrentSearchQuery query) async {
    final cleanQuery = query.query.trim();
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    // Filtros de categoria
    if (query.categories.isNotEmpty) {
      final placeholders = query.categories.map((_) => '?').join(',');
      whereClauses.add('category IN ($placeholders)');
      whereArgs.addAll(query.categories.map((c) => c.slug));
    }

    // Filtros de fontes
    if (query.sources.isNotEmpty) {
      final placeholders = query.sources.map((_) => '?').join(',');
      whereClauses.add('source_id IN ($placeholders)');
      whereArgs.addAll(query.sources);
    }

    // Filtro de tamanho
    if (query.minSizeBytes != null) {
      whereClauses.add('size_bytes >= ?');
      whereArgs.add(query.minSizeBytes!);
    }
    if (query.maxSizeBytes != null) {
      whereClauses.add('size_bytes <= ?');
      whereArgs.add(query.maxSizeBytes!);
    }

    // Filtro de seeders mínimos
    if (query.minSeeders != null && query.minSeeders! > 0) {
      whereClauses.add('seeders >= ?');
      whereArgs.add(query.minSeeders!);
    }

    String orderBy;
    switch (query.sort) {
      case TorrentSortOrder.seedersDesc:
        orderBy = 'seeders DESC, last_seen_at DESC';
        break;
      case TorrentSortOrder.publicationDateDesc:
        orderBy = 'publication_date DESC, last_seen_at DESC';
        break;
      case TorrentSortOrder.sizeAsc:
        orderBy = 'size_bytes ASC';
        break;
      case TorrentSortOrder.sizeDesc:
        orderBy = 'size_bytes DESC';
        break;
      case TorrentSortOrder.relevance:
        orderBy = cleanQuery.isNotEmpty ? 'rank' : 'seeders DESC, last_seen_at DESC';
        break;
    }

    final offset = (query.page - 1) * query.pageSize;
    final limit = query.pageSize;

    List<Map<String, dynamic>> rows;
    int totalCount = 0;

    if (cleanQuery.isEmpty) {
      // Sem termo textual: consulta direta à tabela principal
      final whereSql = whereClauses.isNotEmpty ? 'WHERE ${whereClauses.join(' AND ')}' : '';
      final countRes = await _db.rawQuery('SELECT COUNT(*) as count FROM torrent_records $whereSql', whereArgs);
      totalCount = (countRes.firstOrNull?['count'] as int?) ?? 0;

      rows = await _db.rawQuery(
        'SELECT * FROM torrent_records $whereSql ORDER BY $orderBy LIMIT ? OFFSET ?',
        [...whereArgs, limit, offset],
      );
    } else {
      // Com termo textual: utiliza a tabela virtual FTS5
      final ftsQuery = _buildFtsQuery(cleanQuery);
      final wherePart = whereClauses.isNotEmpty ? 'AND ${whereClauses.join(' AND ')}' : '';

      final countSql = '''
        SELECT COUNT(*) as count
        FROM torrent_search s
        JOIN torrent_records r ON r.id = s.record_id
        WHERE torrent_search MATCH ? $wherePart
      ''';
      final countRes = await _db.rawQuery(countSql, [ftsQuery, ...whereArgs]);
      totalCount = (countRes.firstOrNull?['count'] as int?) ?? 0;

      final selectSql = '''
        SELECT r.*, s.rank
        FROM torrent_search s
        JOIN torrent_records r ON r.id = s.record_id
        WHERE torrent_search MATCH ? $wherePart
        ORDER BY $orderBy
        LIMIT ? OFFSET ?
      ''';
      rows = await _db.rawQuery(selectSql, [ftsQuery, ...whereArgs, limit, offset]);
    }

    final records = rows.map(_recordFromRow).toList();
    return TorrentSearchResult(
      query: query,
      records: records,
      totalCount: totalCount,
      page: query.page,
      pageSize: query.pageSize,
      mode: TorrentSearchMode.local,
      executedAt: DateTime.now(),
    );
  }

  /// Constrói consulta FTS5 segura com prefixos de token (*).
  static String _buildFtsQuery(String text) {
    // Sanitiza caracteres especiais do FTS5
    final sanitized = text.replaceAll(RegExp(r'["\*\^:]'), ' ').trim();
    final tokens = sanitized.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    if (tokens.isEmpty) return '""';
    return tokens.map((t) => '"$t"*').join(' ');
  }

  static TorrentIndexRecord _recordFromRow(Map<String, dynamic> row) {
    List<TorrentSourceProvenance> provenances = [];
    try {
      final rawProv = row['provenances_json'];
      if (rawProv is String && rawProv.isNotEmpty) {
        final decoded = jsonDecode(rawProv) as List<dynamic>;
        provenances = decoded
            .whereType<Map<String, dynamic>>()
            .map((m) => TorrentSourceProvenance.fromMap(m))
            .toList();
      }
    } catch (_) {}

    List<String> tags = [];
    try {
      final rawTags = row['tags_json'];
      if (rawTags is String && rawTags.isNotEmpty) {
        tags = (jsonDecode(rawTags) as List<dynamic>).map((e) => e.toString()).toList();
      }
    } catch (_) {}

    return TorrentIndexRecord(
      id: row['id'] as String,
      sourceId: row['source_id'] as String,
      sourceName: row['source_name'] as String,
      sourceUrl: row['source_url'] as String?,
      title: row['title'] as String,
      normalizedTitle: row['normalized_title'] as String,
      category: TorrentCategory.fromSlug(row['category'] as String?),
      subcategory: row['subcategory'] as String?,
      sizeBytes: row['size_bytes'] as int?,
      publicationDate: row['publication_date'] != null
          ? DateTime.tryParse(row['publication_date'] as String)
          : null,
      infoHashV1: row['info_hash_v1'] as String?,
      infoHashV2: row['info_hash_v2'] as String?,
      magnetUri: row['magnet_uri'] as String?,
      torrentFileUrl: row['torrent_file_url'] as String?,
      seeders: row['seeders'] as int?,
      leechers: row['leechers'] as int?,
      language: row['language'] as String?,
      description: row['description'] as String?,
      tags: tags,
      trustMetadata: row['trust_metadata'] as String?,
      indexedAt: DateTime.tryParse(row['indexed_at'] as String? ?? '') ?? DateTime.now(),
      lastSeenAt: DateTime.tryParse(row['last_seen_at'] as String? ?? '') ?? DateTime.now(),
      provenances: provenances,
    );
  }

  Future<int> getRecordCount() async {
    final res = await _db.rawQuery('SELECT COUNT(*) as count FROM torrent_records');
    return (res.firstOrNull?['count'] as int?) ?? 0;
  }

  Future<DateTime?> getLastSyncDate() async {
    final val = await getMeta('last_sync_date');
    if (val == null) return null;
    return DateTime.tryParse(val);
  }

  Future<String?> getMeta(String key) async {
    final rows = await _db.query(
      'torrent_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.firstOrNull?['value'] as String?;
  }

  Future<void> setMeta(String key, String value) async {
    await _db.insert(
      'torrent_meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> close() async {
    await _db.close();
  }
}
