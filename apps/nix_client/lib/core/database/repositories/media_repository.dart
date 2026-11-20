import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../local_database.dart';

/// Repositório de acervo cultural privado e indexação FTS5.
class MediaRepository {
  final LocalDatabase _database;
  MediaRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> upsertMediaItem({
    required String id,
    required String kind,
    required String title,
    String? parentId,
    Map<String, dynamic> metadata = const {},
    String? source,
    String? sourceId,
    bool preserveExisting = false,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final onConflict = preserveExisting ? 'DO NOTHING' : '''
      DO UPDATE SET kind = excluded.kind, title = excluded.title,
        parent_id = excluded.parent_id, metadata_json = excluded.metadata_json,
        source = excluded.source, source_id = excluded.source_id,
        updated_at = excluded.updated_at
    ''';
    await _db.rawInsert('''
      INSERT INTO media_items (id, kind, title, parent_id, metadata_json, source,
          source_id, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (id) $onConflict
    ''', [id, kind, title, parentId, jsonEncode(metadata), source, sourceId, now]);
  }

  Future<List<Map<String, dynamic>>> listMediaItems({int limit = 50}) async {
    return _db.query('media_items', orderBy: 'updated_at DESC', limit: limit);
  }

  Future<List<Map<String, dynamic>>> searchMedia(String queryTerm) async {
    final clean = queryTerm.trim();
    if (clean.isEmpty) return [];
    // Trata a busca como frase literal, inclusive hífens e aspas internas.
    final safeTerm = '"${clean.replaceAll('"', '""')}"';
    return _db.rawQuery('''
      SELECT m.* FROM media_items m
      JOIN media_search ms ON m.id = ms.media_id
      WHERE media_search MATCH ?
      ORDER BY m.updated_at DESC LIMIT 30;
    ''', [safeTerm]);
  }

  Future<void> deleteMediaItem(String id) async {
    await _db.delete('media_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> upsertLibraryEntry({
    required String identityId,
    required String mediaId,
    String status = 'saved',
    Map<String, dynamic> progress = const {},
    int? rating,
    bool publicInCard = false,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert(
      'library_entries',
      {
        'identity_id': identityId,
        'media_id': mediaId,
        'status': status,
        'progress_json': jsonEncode(progress),
        'rating': rating,
        'public_in_card': publicInCard ? 1 : 0,
        'saved_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> listLibraryEntries(String identityId) async {
    return _db.rawQuery('''
      SELECT l.*, m.kind, m.title, m.metadata_json, m.source, m.source_id
      FROM library_entries l
      JOIN media_items m ON m.id = l.media_id
      WHERE l.identity_id = ?
      ORDER BY l.saved_at DESC;
    ''', [identityId]);
  }

  Future<void> deleteLibraryEntry({
    required String identityId,
    required String mediaId,
  }) async {
    await _db.delete(
      'library_entries',
      where: 'identity_id = ? AND media_id = ?',
      whereArgs: [identityId, mediaId],
    );
  }
}
