import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nix_client/core/database/repositories/catalog_repository.dart';
import 'package:nix_client/core/media/catalog_database.dart';
import 'package:nix_client/features/media/media_index_view.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Media Index - Itens Clicáveis e Gestão no Acervo', () {
    late NixState nixState;
    late CatalogDatabase catalogDb;

    setUp(() async {
      nixState = NixState(loadMockData: false);
      await nixState.initializeEncryptedDatabase(
        passphrase: 'test_passphrase_media_index_123',
        customDbPath: inMemoryDatabasePath,
        requireEncryption: false,
        overwriteExistingVault: true,
      );
      await nixState.persistPrimaryIdentity(
        identity: await NixIdentity.generate(),
        displayName: 'Colecionador Teste',
      );
    });

    tearDown(() async {
      await catalogDb.close();
      nixState.dispose();
    });

    Widget buildHarness() {
      return ChangeNotifierProvider<NixState>.value(
        value: nixState,
        child: const MaterialApp(
          home: Scaffold(
            body: NixMediaIndexView(),
          ),
        ),
      );
    }

    testWidgets('clicar no item do catálogo abre detalhes e permite gerenciar no Acervo', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      catalogDb = (await tester.runAsync(() => CatalogDatabase.open(inMemory: true)))!;
      nixState.setCatalogDatabase(catalogDb);

      final repo = CatalogRepository(catalogDb);
      final testWork = CatalogWork(
        id: 'test_film_1',
        kind: 'movie',
        title: 'Blade Runner 2049',
        originalTitle: 'Blade Runner 2049',
        creators: 'Denis Villeneuve',
        genres: 'Ficção Científica, Cyberpunk',
        releaseYear: 2017,
        summary: 'Trinta anos após os acontecimentos do primeiro filme.',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      await tester.runAsync(() => repo.batchUpsertWorks([testWork]));

      await tester.pumpWidget(buildHarness());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();

      expect(find.text('Blade Runner 2049'), findsOneWidget);
      expect(find.text('Denis Villeneuve'), findsOneWidget);

      // Clica no título para abrir o modal de detalhes
      await tester.tap(find.text('Blade Runner 2049'));
      await tester.pumpAndSettle();

      // Valida modal de detalhes
      expect(find.text('SINOPSE & DETALHES'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Dialog), matching: find.text('Trinta anos após os acontecimentos do primeiro filme.')),
        findsOneWidget,
      );
      expect(find.text('STATUS NO ACERVO PESSOAL'), findsOneWidget);
      expect(find.text('Obra não incluída no Acervo'), findsOneWidget);

      await tester.ensureVisible(find.text('Adicionar ao Acervo'));
      await tester.pumpAndSettle();
      expect(find.text('Adicionar ao Acervo'), findsOneWidget);

      // Adiciona ao Acervo
      await tester.runAsync(() async {
        await tester.tap(find.text('Adicionar ao Acervo'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      expect(find.text('Obra presente no seu Acervo Pessoal'), findsOneWidget);
      await tester.ensureVisible(find.text('Remover do Acervo'));
      expect(find.text('Remover do Acervo'), findsOneWidget);
      expect(
        nixState.userProfile.culturalItems.any((i) => i.title == 'Blade Runner 2049'),
        isTrue,
      );

      // Remove do Acervo
      await tester.runAsync(() async {
        await tester.tap(find.text('Remover do Acervo'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      expect(find.text('Obra não incluída no Acervo'), findsOneWidget);
      expect(
        nixState.userProfile.culturalItems.any((i) => i.title == 'Blade Runner 2049'),
        isFalse,
      );

      // Fecha o modal
      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();

      expect(find.text('Blade Runner 2049'), findsOneWidget);
    });

    testWidgets('detalhes de música indicam metadados quando sem áudio local', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      catalogDb = (await tester.runAsync(() => CatalogDatabase.open(inMemory: true)))!;
      nixState.setCatalogDatabase(catalogDb);

      final repo = CatalogRepository(catalogDb);
      final testMusic = CatalogWork(
        id: 'music_track_42',
        kind: 'track',
        title: 'Resonance',
        originalTitle: 'Resonance Single',
        creators: 'HOME',
        genres: 'Synthwave, Chillwave',
        releaseYear: 2014,
        summary: 'Faixa seminal do movimento synthwave moderno.',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      await tester.runAsync(() => repo.batchUpsertWorks([testMusic]));

      await tester.pumpWidget(buildHarness());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();

      expect(find.text('Resonance'), findsOneWidget);

      await tester.tap(find.text('Resonance'));
      await tester.pumpAndSettle();

      expect(find.text('ÁUDIO & FAIXAS LOCAIS'), findsOneWidget);
      expect(find.textContaining('Apenas metadados indexados'), findsOneWidget);
    });
  });
}
