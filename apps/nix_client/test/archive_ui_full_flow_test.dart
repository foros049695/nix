import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nix_client/core/archive/nix_archive_service.dart';
import 'package:nix_client/core/database/local_database.dart';
import 'package:nix_client/core/database/repositories/archive_repository.dart';
import 'package:nix_client/core/database/repositories/key_material_repository.dart';
import 'package:nix_client/features/archive/archive_environment_view.dart';
import 'package:nix_client/features/archive/article_detail_view.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Etapa 2 — Interface Completa do Nix Archive (Sem Telas Demonstrativas)', () {
    late LocalDatabase localDb;
    late ArchiveRepository archiveRepo;
    late KeyMaterialRepository keyRepo;
    late NixArchiveService archiveService;
    late NixIdentity alice;
    late NixState nixState;

    setUp(() async {
      localDb = await LocalDatabase.open(
        path: inMemoryDatabasePath,
        requireEncryption: false,
      );
      archiveRepo = ArchiveRepository(localDb);
      keyRepo = KeyMaterialRepository(localDb);
      archiveService = NixArchiveService(archiveRepo);
      alice = await NixIdentity.generate();

      await archiveService.ensurePersonaRegistered(
        identity: alice,
        personaId: 'persona_alice',
        keyMaterialRepo: keyRepo,
        keyRef: 'key_ref_alice',
      );

      nixState = NixState();
      // Injeta instâncias de teste no NixState
      nixState.debugOverrideArchive(archiveRepo, archiveService, alice);
    });

    tearDown(() async {
      await localDb.close();
    });

    testWidgets('ArticleDetailView renderiza metadados reais, corpo, alegações e badge Ed25519', (tester) async {
      final articleHash = await archiveService.publishArticle(
        author: alice,
        title: 'Manifesto pela Privacidade Absoluta',
        rawHtmlBody: '<p>A soberania tecnológica é uma necessidade civilizatória.</p>',
        claims: [(claimId: 'claim_1', text: 'Vigilância em massa viola a intimidade humana.')],
      );

      final row = await archiveRepo.getObject(articleHash);
      expect(row, isNotNull);

      await tester.pumpWidget(
        ChangeNotifierProvider<NixState>.value(
          value: nixState,
          child: MaterialApp(
            home: ArticleDetailView(articleObject: row!),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Manifesto pela Privacidade Absoluta'), findsWidgets);
      expect(find.textContaining('Vigilância em massa viola a intimidade humana.'), findsOneWidget);
      expect(find.text('VERIFIED'), findsOneWidget);
      expect(find.text('Alegações Auditáveis e Refutações (1)'), findsOneWidget);
      expect(find.text('Discussões Encadeadas (0)'), findsOneWidget);
    });

    testWidgets('NixArchiveEnvironmentView renderiza as 4 abas e aba de discussões funcional', (tester) async {
      await archiveService.publishArticle(
        author: alice,
        title: 'Artigo para Discussão',
        rawHtmlBody: '<p>Texto base.</p>',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<NixState>.value(
          value: nixState,
          child: const MaterialApp(
            home: NixArchiveEnvironmentView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verifica 4 abas
      expect(find.textContaining('Explorar'), findsOneWidget);
      expect(find.textContaining('Rascunhos'), findsOneWidget);
      expect(find.text('Novo Artigo'), findsOneWidget);
      expect(find.text('Discussões'), findsOneWidget);

      // Clica na aba Discussões
      await tester.tap(find.text('Discussões'));
      await tester.pumpAndSettle();

      // Verifica que a lista de tópicos de discussão é exibida com o botão Entrar
      expect(find.text('Artigo para Discussão'), findsOneWidget);
      expect(find.text('Entrar'), findsOneWidget);

      // Entra na discussão do artigo
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      // Deve exibir o composer com botão de envio Ed25519
      expect(find.textContaining('Comentar com identidade soberana...'), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });
  });
}
