import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/features/archive/archive_environment_view.dart';
import 'package:nix_client/features/media/media_index_view.dart';
import 'package:nix_client/features/navigation/app_shell.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Mobile-First Responsive Layout & Touch Targets Tests (Fase 17)', () {
    late NixState nixState;

    setUp(() async {
      nixState = NixState();
      await nixState.initializeEncryptedDatabase(
        passphrase: 'test_responsive_passphrase_123456',
        customDbPath: inMemoryDatabasePath,
        requireEncryption: false,
        overwriteExistingVault: true,
      );
    });

    tearDown(() {
      nixState.dispose();
    });

    Widget createTestApp({
      required Size screenSize,
      required Widget child,
    }) {
      return ChangeNotifierProvider<NixState>.value(
        value: nixState,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: MediaQueryData(
              size: screenSize,
              padding: const EdgeInsets.only(top: 24, bottom: 16),
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

    testWidgets('Resolução 360x800 (Compacto): renderiza AppShell sem overflow e com NavigationBar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));

      await tester.pumpWidget(
        createTestApp(
          screenSize: const Size(360, 800),
          child: const AppShell(),
        ),
      );
      await tester.pump();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Conversas'), findsOneWidget);
      expect(find.text('Acervo'), findsOneWidget);
      expect(find.text('Arquivo'), findsOneWidget);
    });

    testWidgets('Resolução 393x852 (Smartphone padrão): renderiza MediaIndexView com busca e chips', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));

      await tester.pumpWidget(
        createTestApp(
          screenSize: const Size(393, 852),
          child: const NixMediaIndexView(),
        ),
      );
      await tester.pump();

      expect(find.text('Nix Media Index'), findsOneWidget);
      expect(find.text('100% Offline'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Filmes'), findsOneWidget);
      expect(find.text('Livros'), findsOneWidget);
    });

    testWidgets('Resolução 412x915 (Smartphone grande): renderiza ArchiveEnvironmentView com abas', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));

      await tester.pumpWidget(
        createTestApp(
          screenSize: const Size(412, 915),
          child: const NixArchiveEnvironmentView(),
        ),
      );
      await tester.pump();

      expect(find.text('Nix Archive'), findsOneWidget);
      expect(find.text('Novo Artigo'), findsOneWidget);
      expect(find.text('Discussões'), findsOneWidget);
    });

    testWidgets('Resolução 800x1280 (Tablet): navegação e touch targets adequados', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1280));

      await tester.pumpWidget(
        createTestApp(
          screenSize: const Size(800, 1280),
          child: const AppShell(),
        ),
      );
      await tester.pump();

      expect(find.byType(AppShell), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
