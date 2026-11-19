import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/database/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late String path;
  final source = Directory('../../database/migrations').absolute;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('nix_db_probe_');
    path = '${temp.path}/probe.db';
  });
  tearDown(() async => temp.delete(recursive: true));

  test('estado de cifragem corresponde ao cipher_version disponível', () async {
    final db = await LocalDatabase.open(
      path: path,
      rawCipherKey: Uint8List(32),
      customFactory: databaseFactoryFfi,
    );
    addTearDown(db.close);
    final rows = await db.rawDatabase.rawQuery('PRAGMA cipher_version');
    final version = rows.isNotEmpty && rows.first.values.isNotEmpty
        ? rows.first.values.first?.toString()
        : null;
    final hasCipher = version != null && version.trim().isNotEmpty;
    expect(db.cipherInfo.isEncrypted, hasCipher);
    expect(db.cipherInfo.cipherEngine,
        hasCipher ? 'SQLCipher' : 'SQLite-Development-Clearnet');
  });

  for (final filename in [
    'local_001_initial.sql',
    'local_002_lookup_indexes.sql'
  ]) {
    test('rejeita um byte alterado em $filename antes de aplicar qualquer SQL',
        () async {
      final migrations = await Directory('${temp.path}/database/migrations')
          .create(recursive: true);
      for (final name in [
        'local_001_initial.sql',
        'local_002_lookup_indexes.sql'
      ]) {
        final sql = await File('${source.path}/$name').readAsString();
        await File('${migrations.path}/$name')
            .writeAsString(name == filename ? '$sql ' : sql);
      }
      final previous = Directory.current;
      Directory.current = temp;
      try {
        await expectLater(
          LocalDatabase.open(path: path, customFactory: databaseFactoryFfi)
              .then((db) => db.close()),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Checksum'),
          )),
        );
        final raw = await databaseFactoryFfi.openDatabase(path);
        try {
          expect(
              (await raw.rawQuery('PRAGMA user_version')).first['user_version'],
              0);
          expect(
              await raw.rawQuery(
                  "SELECT name FROM sqlite_master WHERE type = 'table'"),
              isEmpty);
        } finally {
          await raw.close();
        }
      } finally {
        Directory.current = previous;
      }
    });
  }

  test('overrides explícitos continuam aceitando SQL sintético de testes',
      () async {
    final db = await LocalDatabase.open(
      path: path,
      customFactory: databaseFactoryFfi,
      migration001Sql: '''
CREATE TABLE schema_migrations(version INTEGER, applied_at INTEGER, checksum TEXT);
CREATE TABLE probe(value INTEGER);
''',
      migration002Sql: 'INSERT INTO probe VALUES (42);',
    );
    addTearDown(db.close);
    expect((await db.rawDatabase.query('probe')).single['value'], 42);
    expect((await db.getAppliedMigrations()).length, 2);
  });
}
