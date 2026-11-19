import 'dart:typed_data';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../local_database.dart';

/// Repositório para armazenamento envelopado de material criptográfico (`key_material`).
class KeyMaterialRepository {
  final LocalDatabase _database;
  KeyMaterialRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> storeKeyMaterial({
    required String id,
    required String purpose,
    required Uint8List wrappedBytes,
    required String wrappingKeyRef,
    int formatVersion = 1,
    int? createdAt,
  }) async {
    final now = createdAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert(
      'key_material',
      {
        'id': id,
        'purpose': purpose,
        'wrapped_bytes': wrappedBytes,
        'wrapping_key_ref': wrappingKeyRef,
        'format_version': formatVersion,
        'created_at': now,
        'retired_at': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getKeyMaterial(String id) async {
    final rows = await _db.query(
      'key_material',
      where: 'id = ? AND retired_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> retireKeyMaterial(String id, {int? retiredAt}) async {
    final now = retiredAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.update(
      'key_material',
      {'retired_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
