import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/media/catalog_database.dart';
import 'package:nix_client/features/archive/article_detail_view.dart';
import 'package:nix_client/features/archive/archive_environment_view.dart';
import 'package:nix_client/features/media/media_index_view.dart';
import 'package:nix_client/features/navigation/app_shell.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Android Interface, Responsiveness & Accessibility Suite (Etapa 7)', () {
    late NixState nixState;

    setUp(() async {
      nixState = NixState();
      await nixState.initializeEncryptedDatabase(
        passphrase: 'test_android_passphrase_123456',
        customDbPath: inMemoryDatabasePath,
        requireEncryption: false,
        overwriteExistingVault: true,
      );
    });

    tearDown(() {
      nixState.dispose();
    });

    Widget buildTestHarness({
      required Size screenSize,
      required Widget child,
      ThemeMode themeMode = ThemeMode.dark,
      EdgeInsets viewInsets = EdgeInsets.zero,
      EdgeInsets padding = const EdgeInsets.only(top: 24, bottom: 16),
    }) {
      return ChangeNotifierProvider<NixState>.value(
        value: nixState,
        child: MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: themeMode,
          home: MediaQuery(
            data: MediaQueryData(
              size: screenSize,
              padding: padding,
              viewInsets: viewInsets,
            ),
            child: SizedBox(
              width: screenSize.width,
              height: screenSize.height,
              child: child,
            ),
          ),
        ),
      );
    }

    testWidgets('1. SafeArea e Teclado Virtual (360x800): sem overflow de renderização ao abrir teclado', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));

      // Simula teclado virtual ativo (viewInsets.bottom = 320)
      await tester.pumpWidget(
        buildTestHarness(
          screenSize: const Size(360, 800),
          viewInsets: const EdgeInsets.only(bottom: 320),
          child: const NixMediaIndexView(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('2. Modais e Diálogos no Media Index: renderiza catálogo e aciona diálogo de atualização', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      final catalog = await tester.runAsync(() => CatalogDatabase.open(inMemory: true));
      nixState.setCatalogDatabase(catalog!);
      await nixState.setCatalogManifestUrl('http://nixcatalog234567abcdefghijklmnopqrstuvwxyz234567abcdefaa.onion/manifest.json');
      addTearDown(catalog.close);

      await tester.pumpWidget(
        buildTestHarness(
          screenSize: const Size(393, 852),
          child: const NixMediaIndexView(),
        ),
      );
      await tester.pumpAndSettle();

      // Botão de atualização privada no topo
      final iconFinder = find.byIcon(Icons.cloud_sync_rounded);
      expect(iconFinder, findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(iconFinder);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      // Diálogo de atualização privado aberto com publicador Onion configurado
      expect(find.text('Atualizações Privadas do Catálogo'), findsOneWidget);
      expect(find.text('Fechar'), findsOneWidget);
      expect(find.textContaining('Publicador configurado:'), findsOneWidget);
      final verify = find.ancestor(
        of: find.text('Verificar Agora'),
        matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
      );
      expect(tester.widget<ElevatedButton>(verify).onPressed, isNotNull);

      // Fecha o diálogo
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      expect(find.text('Atualizações Privadas do Catálogo'), findsNothing);
    });

    testWidgets('3. Dark Mode e Light Mode: renderiza ArchiveEnvironmentView em ambos os temas sem erros visuais', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));

      // Teste Dark Mode
      await tester.pumpWidget(
        buildTestHarness(
          screenSize: const Size(393, 852),
          themeMode: ThemeMode.dark,
          child: const NixArchiveEnvironmentView(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nix Archive'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Teste Light Mode
      await tester.pumpWidget(
        buildTestHarness(
          screenSize: const Size(393, 852),
          themeMode: ThemeMode.light,
          child: const NixArchiveEnvironmentView(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nix Archive'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('4. ArticleDetailView: página detalhada de leitura com abas, alegações e discussões', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));

      final identity = await NixIdentity.generate();
      final archiveService = nixState.archiveService!;

      final hash = await archiveService.publishArticle(
        author: identity,
        title: 'Segurança Criptográfica em Dispositivos Móveis',
        rawHtmlBody: '<p>Análise de isolamento de processos e Keystores no Android.</p>',
        claims: [
          (claimId: 'claim-hw-1', text: 'Hardware-backed keystore resiste a extração direta.'),
        ],
      );

      final row = await archiveService.archiveRepo.getObject(hash);
      expect(row, isNotNull);

      await tester.pumpWidget(
        buildTestHarness(
          screenSize: const Size(393, 852),
          child: ArticleDetailView(
            articleObject: row!,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Confirma que título, corpo e seções aparecem
      expect(find.text('Segurança Criptográfica em Dispositivos Móveis'), findsWidgets);
      expect(find.text('Autor:'), findsOneWidget);
      expect(find.text('CID Hash:'), findsOneWidget);
      expect(find.text('Alegações Auditáveis e Refutações (1)'), findsOneWidget);
      expect(find.text('Hardware-backed keystore resiste a extração direta.'), findsOneWidget);
      expect(find.text('Discussões Encadeadas (0)'), findsOneWidget);
    });

    testWidgets('5. Acessibilidade e Tamanhos de Toque (Touch Targets): navegação principal com altura >= 48dp', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));

      await tester.pumpWidget(
        buildTestHarness(
          screenSize: const Size(360, 800),
          child: const AppShell(),
        ),
      );
      await tester.pumpAndSettle();

      final navBar = find.byKey(const Key('floating_workspace_tabs'));
      expect(find.descendant(of: navBar, matching: find.byType(InkWell)), findsNWidgets(5));

      // Touch target verification: todas as abas devem ter altura utilizável
      final navBarSize = tester.getSize(navBar);
      expect(navBarSize.height, greaterThanOrEqualTo(48.0));
    });
  });
}
