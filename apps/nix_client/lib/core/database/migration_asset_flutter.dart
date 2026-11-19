import 'package:flutter/services.dart' show rootBundle;

/// Carrega scripts de migração SQL embutidos em `flutter_assets` (Linux, Android e testes Flutter).
Future<String?> loadBundledMigrationSql(String filename) async {
  try {
    return await rootBundle.loadString('assets/migrations/$filename');
  } catch (_) {
    return null;
  }
}
