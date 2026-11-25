import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/database/local_database.dart';
import 'package:nix_client/core/media/catalog_database.dart';
import 'package:nix_client/features/media/media_index_view.dart';
import 'package:nix_client/features/media/universal_metadata_search_dialog.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Nix Media Index — Catálogo Inicial Vazio e Busca de Metadados', () {
    late LocalDatabase localDb;
    late CatalogDatabase catalogDb;
    late NixIdentity alice;
    late NixState nixState;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      localDb = await LocalDatabase.open(
        path: inMemoryDatabasePath,
        requireEncryption: false,
      );
      catalogDb = await CatalogDatabase.open(path: inMemoryDatabasePath);
      alice = await NixIdentity.generate();

      nixState = NixState();
      nixState.setCatalogDatabase(catalogDb);
    });

    tearDown(() async {
      await catalogDb.close();
      await localDb.close();
    });

    testWidgets('Catálogo vazio exibe tela limpa com os 4 botões de ação', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<NixState>.value(
          value: nixState,
          child: const MaterialApp(
            home: NixMediaIndexView(),
          ),
        ),
      );

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      // Verifica exibição do título de catálogo vazio
      expect(find.text('Seu catálogo está vazio'), findsOneWidget);

      // Verifica os 4 botões de ação esperados
      expect(find.text('Pesquisar online'), findsWidgets);
      expect(find.text('Importar arquivo'), findsOneWidget);
      expect(find.text('Adicionar manualmente'), findsOneWidget);
      expect(find.text('Abrir meu Acervo'), findsOneWidget);

      // Abre diálogo de busca online
      await tester.tap(find.text('Pesquisar online').first);
      await tester.pumpAndSettle();

      // Verifica que o modal UniversalMetadataSearchDialog foi exibido
      expect(find.byType(UniversalMetadataSearchDialog), findsOneWidget);
      expect(find.text('Buscar Metadados Online'), findsOneWidget);
      expect(find.textContaining('Transporte:'), findsOneWidget);
    });
  });
}
