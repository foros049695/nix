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
}
