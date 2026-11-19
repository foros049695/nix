import 'dart:convert';
import 'dart:typed_data';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../local_database.dart';

/// Repositório para Nix Archive: personas assinantes, objetos imutáveis canônicos,
/// alegações (claims), refutações e registros de réplicas distribuídas.
class ArchiveRepository {
  final LocalDatabase _database;
  ArchiveRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> upsertPersona({
    required String id,
    required Uint8List publicKey,
    required String keyRef,
  }) async {
    await _db.insert(
      'archive_personas',
      {
        'id': id,
        'public_key': publicKey,
        'key_ref': keyRef,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getPersona(String id) async {
    final rows = await _db.query(
      'archive_personas',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsertObject({
    required String hash,
    required String kind,
    required Uint8List canonicalBytes,
    required Uint8List authorPublic,
    required Uint8List signature,
    String? supersedesHash,
    String visibility = 'public',
    int? createdAt,
  }) async {
    final now = createdAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert(
      'archive_objects',
      {
        'hash': hash,
        'kind': kind,
        'canonical_bytes': canonicalBytes,
        'author_public': authorPublic,
        'signature': signature,
        'supersedes_hash': supersedesHash,
        'visibility': visibility,
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getObject(String hash) async {
    final rows = await _db.query(
      'archive_objects',
      where: 'hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> listObjects({
    String? kind,
    int limit = 50,
  }) async {
    return _db.query(
      'archive_objects',
      where: kind == null ? null : 'kind = ?',
      whereArgs: kind == null ? null : [kind],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<void> upsertClaim({
    required String objectHash,
    required String claimId,
    required String text,
  }) async {
    await _db.insert(
      'archive_claims',
      {
        'object_hash': objectHash,
        'claim_id': claimId,
        'text': text,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getClaimsForObject(
    String objectHash,
  ) async {
    return _db.query(
      'archive_claims',
      where: 'object_hash = ?',
      whereArgs: [objectHash],
      orderBy: 'claim_id ASC',
    );
  }

  Future<void> insertRefutation({
    required String refutationHash,
    required String targetHash,
    required String targetClaimId,
  }) async {
    await _db.insert(
      'archive_refutations',
      {
        'refutation_hash': refutationHash,
        'target_hash': targetHash,
        'target_claim_id': targetClaimId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> listRefutationsForTarget(
    String targetHash,
  ) async {
    return _db.query(
      'archive_refutations',
      where: 'target_hash = ?',
      whereArgs: [targetHash],
    );
  }

  Future<void> upsertReplica({
    required String objectHash,
    required String replicaId,
    required String endpoint,
    int? lastVerifiedAt,
    int? promisedUntil,
  }) async {
    await _db.insert(
      'archive_replicas',
      {
        'object_hash': objectHash,
        'replica_id': replicaId,
        'endpoint': endpoint,
        'last_verified_at': lastVerifiedAt,
        'promised_until': promisedUntil,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> listReplicas(String objectHash) async {
    return _db.query(
      'archive_replicas',
      where: 'object_hash = ?',
      whereArgs: [objectHash],
    );
  }

  // ===========================================================================
  // SUBSISTEMA DE DISCUSSÕES, RASCUNHOS E MODERAÇÃO LOCAL (Fase 19)
  // ===========================================================================

  Future<void> ensureDiscussionTables() async {
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS archive_drafts (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        markdown_content TEXT NOT NULL,
        tags_json TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    await _db.execute('''
      CREATE TABLE IF NOT EXISTS archive_comments (
        hash TEXT PRIMARY KEY,
        target_object_hash TEXT NOT NULL,
        parent_comment_hash TEXT,
        author_public BLOB NOT NULL CHECK(length(author_public)=32),
        author_persona_id TEXT NOT NULL,
        signature BLOB NOT NULL CHECK(length(signature)=64),
        content_markdown TEXT NOT NULL,
        quote_text TEXT,
        created_at INTEGER NOT NULL
      );
    ''');

    await _db.execute('''
      CREATE TABLE IF NOT EXISTS archive_moderation (
        author_public BLOB PRIMARY KEY CHECK(length(author_public)=32),
        status TEXT NOT NULL CHECK(status IN ('muted', 'blocked')),
        reason TEXT,
        updated_at INTEGER NOT NULL
      );
    ''');
  }

  Future<void> saveDraft({
    required String id,
    required String title,
    required String category,
    required String markdownContent,
    List<String> tags = const [],
  }) async {
    await ensureDiscussionTables();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert(
      'archive_drafts',
      {
        'id': id,
        'title': title,
        'category': category,
        'markdown_content': markdownContent,
        'tags_json': jsonEncode(tags),
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getDraft(String id) async {
    await ensureDiscussionTables();
    final rows = await _db.query(
      'archive_drafts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> listDrafts() async {
    await ensureDiscussionTables();
    return _db.query('archive_drafts', orderBy: 'updated_at DESC');
  }

  Future<void> deleteDraft(String id) async {
    await ensureDiscussionTables();
    await _db.delete('archive_drafts', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> insertComment({
    required String hash,
    required String targetObjectHash,
    String? parentCommentHash,
    required Uint8List authorPublic,
    required String authorPersonaId,
    required Uint8List signature,
    required String contentMarkdown,
    String? quoteText,
    int? createdAt,
  }) async {
    await ensureDiscussionTables();
    final now = createdAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert(
      'archive_comments',
      {
        'hash': hash,
        'target_object_hash': targetObjectHash,
        'parent_comment_hash': parentCommentHash,
        'author_public': authorPublic,
        'author_persona_id': authorPersonaId,
        'signature': signature,
        'content_markdown': contentMarkdown,
        'quote_text': quoteText,
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> listCommentsForObject(
    String targetObjectHash,
  ) async {
    await ensureDiscussionTables();
    return _db.query(
      'archive_comments',
      where: 'target_object_hash = ?',
      whereArgs: [targetObjectHash],
      orderBy: 'created_at ASC',
    );
  }

  Future<Map<String, dynamic>?> getComment(String hash) async {
    await ensureDiscussionTables();
    final rows = await _db.query(
      'archive_comments',
      where: 'hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> setAuthorModeration({
    required Uint8List authorPublic,
    required String status,
    String? reason,
  }) async {
    await ensureDiscussionTables();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert(
      'archive_moderation',
      {
        'author_public': authorPublic,
        'status': status,
        'reason': reason,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeAuthorModeration(Uint8List authorPublic) async {
    await ensureDiscussionTables();
    await _db.delete(
      'archive_moderation',
      where: 'author_public = ?',
      whereArgs: [authorPublic],
    );
  }

  Future<Map<String, dynamic>?> getAuthorModeration(
    Uint8List authorPublic,
  ) async {
    await ensureDiscussionTables();
    final rows = await _db.query(
      'archive_moderation',
      where: 'author_public = ?',
      whereArgs: [authorPublic],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> listModeratedAuthors() async {
    await ensureDiscussionTables();
    return _db.query('archive_moderation', orderBy: 'updated_at DESC');
  }
}
