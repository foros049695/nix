import 'dart:io';
import 'dart:typed_data';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/local_database.dart';

/// Leitor puramente offline de mapas MBTiles (SQLite local sem nenhuma requisição de rede, Fase 5).
class MbtilesMapReader {
  final Database _db;
  MbtilesMapReader._(this._db);

  static Future<MbtilesMapReader> openFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Arquivo .mbtiles não encontrado', path);
    }
    LocalDatabase.ensureSqliteInitialized();
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    return MbtilesMapReader._(db);
  }

  Future<Map<String, String>> readMetadata() async {
    final rows = await _db.query('metadata');
    return {
      for (final row in rows)
        row['name'].toString(): (row['value'] ?? '').toString(),
    };
  }

  Future<Uint8List?> getTile({
    required int zoom,
    required int column,
    required int row,
  }) async {
    final rows = await _db.query(
      'tiles',
      columns: ['tile_data'],
      where: 'zoom_level = ? AND tile_column = ? AND tile_row = ?',
      whereArgs: [zoom, column, row],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final data = rows.first['tile_data'];
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    return null;
  }

  Future<void> close() => _db.close();
}
