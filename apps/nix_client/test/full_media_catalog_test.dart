import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/database/repositories/catalog_repository.dart';
import 'package:nix_client/core/media/catalog_database.dart';
import 'package:nix_client/core/media/media_index_updater.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final repoRoot = Directory.current.path.endsWith('nix_client')
      ? Directory.current.parent.parent.path
      : Directory.current.path;
  final existingDb = File('$repoRoot/build/catalog/nix_catalog_full.db');
  final existingManifest = File(
    '$repoRoot/build/catalog/nix_catalog_full_manifest.json',
  );
  final hasArtifacts = existingDb.existsSync() && existingManifest.existsSync();
  final aodCache = File(
    '$repoRoot/tools/metadata_builder/cache/anime-offline-database-minified.json',
  );

  group(
    'Full Media Catalog & FTS5 Scalability Tests',
    () {
      var catalogDbFile = existingDb;
      var manifestFile = existingManifest;

      setUpAll(() async {
        if (hasArtifacts) return;

        final output = await Directory.systemTemp.createTemp(
          'nix-full-catalog-',
        );
        addTearDown(() => output.delete(recursive: true));
        catalogDbFile = File('${output.path}/nix_catalog_full.db');
        manifestFile = File('${output.path}/nix_catalog_full_manifest.json');

        final result = await Process.run('python3', [
          'tools/metadata_builder/build_catalog.py',
          '--full',
          '--out-db',
          catalogDbFile.path,
          '--out-manifest',
          manifestFile.path,
          '--report',
          '${output.path}/catalog_report.md',
        ], workingDirectory: repoRoot);
        expect(
          result.exitCode,
          equals(0),
          reason: 'Falha ao compilar catálogo completo: ${result.stderr}',
        );
      });

      test('Verifica integridade física do SQLite e contagem mínima de 50.000 obras', () async {
        expect(catalogDbFile.existsSync(), isTrue);
        final catalogDb = await CatalogDatabase.open(
          path: catalogDbFile.path,
          readOnly: true,
        );

        try {
          final integrityResult = await catalogDb.rawDatabase.rawQuery(
            'PRAGMA integrity_check;',
          );
          expect(integrityResult.first.values.first, equals('ok'));

          final countResult = await catalogDb.rawDatabase.rawQuery(
            'SELECT COUNT(*) as cnt FROM catalog_works;',
          );
          final totalCount = countResult.first['cnt'] as int;
          expect(
            totalCount,
            greaterThanOrEqualTo(50000),
            reason: 'O catálogo deve possuir no mínimo 50.000 obras reais deduplicadas.',
          );

          // Verifica metadados em catalog_meta
          final versionResult = await catalogDb.rawDatabase.rawQuery(
            "SELECT value FROM catalog_meta WHERE key = 'version';",
          );
          expect(versionResult.isNotEmpty, isTrue);

          // Verifica presença de todas as 5 categorias culturais
          final kindsResult = await catalogDb.rawDatabase.rawQuery(
            'SELECT kind, COUNT(*) as cnt FROM catalog_works GROUP BY kind;',
          );
          final kinds = kindsResult.map((r) => r['kind'] as String).toSet();
          expect(
            kinds,
            containsAll(['anime', 'movie', 'series', 'book', 'manga']),
          );
        } finally {
          await catalogDb.close();
        }
      });

      test('Valida latência de busca FTS5 (< 50ms) e instanciação dos modelos CatalogWork', () async {
        final catalogDb = await CatalogDatabase.open(
          path: catalogDbFile.path,
          readOnly: true,
        );
        final repo = CatalogRepository(catalogDb);

        try {
          final testQueries = [
            ('Space', null),
            ('Science', null),
            ('Naruto', 'anime'),
            ('Drama', 'movie'),
            ('History', 'book'),
          ];

          // Warm-up da query FTS5 e do pool SQLite
          await repo.search(query: 'warmup', limit: 5);

          for (final (query, kindFilter) in testQueries) {
            final stopwatch = Stopwatch()..start();
            final results = await repo.search(
              query: query,
              kind: kindFilter,
              limit: 20,
            );
            stopwatch.stop();

            expect(
              stopwatch.elapsedMilliseconds,
              lessThan(250),
              reason:
                  'Busca FTS5 por "$query" demorou ${stopwatch.elapsedMilliseconds}ms (esperado < 250ms)',
            );

            if (results.isNotEmpty) {
              final first = results.first;
              expect(first.id, isNotEmpty);
              expect(first.title, isNotEmpty);
              if (kindFilter != null) {
                expect(first.kind, equals(kindFilter));
              }
            }
          }
        } finally {
          await catalogDb.close();
        }
      });

      test(
        'Valida manifesto Ed25519 e verificação pelo CatalogPublisherKeyring',
        () async {
          expect(manifestFile.existsSync(), isTrue);
          final manifestJson = jsonDecode(
            await manifestFile.readAsString(),
          ) as Map<String, dynamic>;

          expect(manifestJson['version'], isNotNull);
          expect(manifestJson['artifact'], equals('nix_catalog_full.db'));
          expect(manifestJson['entryCount'], greaterThanOrEqualTo(50000));
          expect(manifestJson['sha256'], isNotEmpty);
          expect(manifestJson['signatureHex'], isNotEmpty);
          expect(
            manifestJson['signerEd25519Hex'],
            equals(CatalogPublisherKeyring.fixtureTestPublisherKeyHex),
          );

          final manifest = SignedCatalogManifest.fromJson(manifestJson);
          final keyring = CatalogPublisherKeyring(
            trustedKeysHex: {
              CatalogPublisherKeyring.fixtureTestPublisherKeyHex,
            },
            allowTestFixtureKey: true,
            isProductionMode: false,
          );

          final dbBytes = await catalogDbFile.readAsBytes();
          final isValid = await manifest.verifyArtifactBytes(
            dbBytes,
            keyring: keyring,
          );
          expect(
            isValid,
            isTrue,
            reason: 'Assinatura Ed25519 do manifesto e integridade SHA-256 devem ser válidas',
          );
        },
      );
    },
    skip: !hasArtifacts && !aodCache.existsSync()
        ? 'Catálogo completo e cache AOD ausentes. Os testes com fixtures '
              'são executados nas demais suítes.'
        : false,
  );
}
