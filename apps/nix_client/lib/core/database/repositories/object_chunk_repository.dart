import 'dart:typed_data';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../local_database.dart';

/// Repositório de objetos binários fragmentados (chunks) e anexos cifrados E2EE.
class ObjectChunkRepository {
  final LocalDatabase _database;
  ObjectChunkRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> upsertObject({
    required String id,
    required Uint8List sha256Digest,
    required String mimeType,
    required int byteSize,
    required String keyRef,
    required String encryptedPath,
    int? createdAt,
    int? expiresAt,
  }) async {
    final now = createdAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert(
      'objects',
      {
        'id': id,
        'sha256': sha256Digest,
        'mime_type': mimeType,
        'byte_size': byteSize,
        'key_ref': keyRef,
        'encrypted_path': encryptedPath,
        'created_at': now,
        'expires_at': expiresAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getObject(String id) async {
    final rows = await _db.query(
      'objects',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsertChunk({
    required String objectId,
    required int chunkNo,
    required Uint8List ciphertextHash,
    required int cipherSize,
    required String encryptedPath,
  }) async {
    await _db.insert(
      'object_chunks',
      {
        'object_id': objectId,
        'chunk_no': chunkNo,
        'ciphertext_hash': ciphertextHash,
        'cipher_size': cipherSize,
        'encrypted_path': encryptedPath,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getChunks(String objectId) async {
    return _db.query(
      'object_chunks',
      where: 'object_id = ?',
      whereArgs: [objectId],
      orderBy: 'chunk_no ASC',
    );
  }

  Future<void> linkAttachment({
    required String messageId,
    required String objectId,
    required String fileName,
    int ordinal = 0,
  }) async {
    await _db.insert(
      'attachments',
      {
        'message_id': messageId,
        'object_id': objectId,
        'file_name': fileName,
        'ordinal': ordinal,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAttachmentsForMessage(
    String messageId,
  ) async {
    return _db.rawQuery('''
      SELECT a.*, o.sha256, o.mime_type, o.byte_size, o.key_ref, o.encrypted_path
      FROM attachments a
      JOIN objects o ON o.id = a.object_id
      WHERE a.message_id = ?
      ORDER BY a.ordinal ASC;
    ''', [messageId]);
  }
}
