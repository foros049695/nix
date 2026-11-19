import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../local_database.dart';

/// Repositório de preferências do cliente armazenadas de forma cifrada na tabela `preferences`.
class PreferencesRepository {
  final LocalDatabase _database;
  PreferencesRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> setOption(String key, dynamic value, {int revision = 1}) async {
    await _db.insert(
      'preferences',
      {
        'key': key,
        'value_json': jsonEncode(value),
        'revision': revision,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<dynamic> getOption(String key) async {
    final rows = await _db.query(
      'preferences',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final jsonStr = rows.first['value_json'] as String;
    return jsonDecode(jsonStr);
  }
}
