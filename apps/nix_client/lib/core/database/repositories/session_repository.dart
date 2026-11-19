import 'dart:typed_data';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../local_database.dart';

/// Repositório de sessões Double Ratchet, chaves puladas (`skipped_keys`) e nonces anti-replay.
class SessionRepository {
  final LocalDatabase _database;
  SessionRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> saveSession({
    required String id,
    required String conversationId,
    required String localDeviceId,
    required String peerDeviceId,
    required Uint8List stateBlob,
    int formatVersion = 1,
    int revision = 0,
    int? updatedAt,
  }) async {
    final now = updatedAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert(
      'sessions',
      {
        'id': id,
        'conversation_id': conversationId,
        'local_device_id': localDeviceId,
        'peer_device_id': peerDeviceId,
        'state_blob': stateBlob,
        'format_version': formatVersion,
        'revision': revision,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getSessionByConversation(
    String conversationId, {
    String? peerDeviceId,
  }) async {
    final rows = await _db.query(
      'sessions',
      where: peerDeviceId == null
          ? 'conversation_id = ?'
          : 'conversation_id = ? AND peer_device_id = ?',
      whereArgs: peerDeviceId == null
          ? [conversationId]
          : [conversationId, peerDeviceId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> listSessions() async {
    return _db.query('sessions', orderBy: 'updated_at DESC');
  }

  Future<void> storeSkippedKey({
    required String sessionId,
    required Uint8List ratchetPublic,
    required int messageNo,
    required Uint8List wrappedKey,
    required int expiresAt,
  }) async {
    await _db.insert(
      'skipped_keys',
      {
        'session_id': sessionId,
        'ratchet_public': ratchetPublic,
        'message_no': messageNo,
        'wrapped_key': wrappedKey,
        'expires_at': expiresAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Uint8List?> takeSkippedKey({
    required String sessionId,
    required Uint8List ratchetPublic,
    required int messageNo,
  }) async {
    final rows = await _db.query(
      'skipped_keys',
      where: 'session_id = ? AND ratchet_public = ? AND message_no = ?',
      whereArgs: [sessionId, ratchetPublic, messageNo],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    await _db.delete(
      'skipped_keys',
      where: 'session_id = ? AND ratchet_public = ? AND message_no = ?',
      whereArgs: [sessionId, ratchetPublic, messageNo],
    );
    return Uint8List.fromList(rows.first['wrapped_key'] as List<int>);
  }

  Future<int> purgeExpiredSkippedKeys({int? nowMs}) async {
    final now = nowMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    return _db.delete(
      'skipped_keys',
      where: 'expires_at <= ?',
      whereArgs: [now],
    );
  }

  Future<bool> hasReplayNonce({
    required String issuerKey,
    required String recordType,
    required Uint8List nonce,
  }) async {
    final rows = await _db.query(
      'replay_nonces',
      where: 'issuer_key = ? AND record_type = ? AND nonce = ?',
      whereArgs: [issuerKey, recordType, nonce],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> recordReplayNonce({
    required String issuerKey,
    required String recordType,
    required Uint8List nonce,
    required int expiresAt,
  }) async {
    await _db.insert(
      'replay_nonces',
      {
        'issuer_key': issuerKey,
        'record_type': recordType,
        'nonce': nonce,
        'expires_at': expiresAt,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
