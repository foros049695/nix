import 'dart:typed_data';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../local_database.dart';

/// Repositório de pré-chaves X3DH locais (`prekeys`).
class PreKeyRepository {
  final LocalDatabase _database;
  PreKeyRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> storePreKey({
    required String id,
    required String identityId,
    required String deviceId,
    required String kind,
    required Uint8List publicBytes,
    required String keyRef,
    Uint8List? signature,
    required int expiresAt,
  }) async {
    await _db.insert(
      'prekeys',
      {
        'id': id,
        'identity_id': identityId,
        'device_id': deviceId,
        'kind': kind,
        'public_bytes': publicBytes,
        'key_ref': keyRef,
        'signature': signature,
        'expires_at': expiresAt,
        'consumed_at': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getPreKey(String id) async {
    final rows = await _db.query(
      'prekeys',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> consumePreKey(String id, {int? consumedAt}) async {
    final now = consumedAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.update(
      'prekeys',
      {'consumed_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
