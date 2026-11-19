import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/database/local_database.dart';
import 'package:nix_client/core/database/repositories.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDir;
  late LocalDatabase database;
  late MediaRepository media;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nix_media_fts5_probe_');
    database = await LocalDatabase.open(
      path: '${tempDir.path}/media.db',
      rawCipherKey: Uint8List(32),
      customFactory: databaseFactoryFfi,
    );
    media = MediaRepository(database);
  });

  tearDown(() async {
    await database.close();
    await tempDir.delete(recursive: true);
  });

  for (final term in ['sci-fi', 'utf-8', 'a "quoted" title', "author's book"]) {
    test('busca mídia com termo literal: $term', () async {
      await media.upsertMediaItem(id: 'match', kind: 'book', title: term);
      await media.upsertMediaItem(
          id: 'other', kind: 'book', title: 'Outro livro');

      final results = await media.searchMedia('  $term  ');
      expect(results.map((row) => row['id']), ['match']);
    });
  }

  test('busca vazia não retorna mídia', () async {
    await media.upsertMediaItem(id: 'match', kind: 'book', title: 'Livro');
    expect(await media.searchMedia('   '), isEmpty);
  });
}
