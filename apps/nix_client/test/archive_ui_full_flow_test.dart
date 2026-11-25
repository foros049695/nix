import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:nix_client/core/archive/archive_image.dart';
import 'package:flutter/material.dart';
import 'package:nix_client/core/archive/archive_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nix_client/core/archive/nix_archive_service.dart';
import 'package:nix_client/core/database/local_database.dart';
import 'package:nix_client/core/database/repositories/archive_repository.dart';
import 'package:nix_client/core/database/repositories/key_material_repository.dart';
import 'package:nix_client/features/archive/archive_environment_view.dart';
import 'package:nix_client/core/security/file_picker_adapter.dart';
import 'package:nix_client/core/security/local_image_helper.dart';
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

    test('Markdown preserva formatação permitida e bloqueia mídia remota', () {
      final safe = compileArchiveMarkdown("""
## Meu título

**Forte**, *ênfase*, <u>sublinhado</u> e ~~tachado~~.

- [ ] Ler depois

| Faixa | Nota |
| --- | --- |
| Álbum | 10 |

[Site](https://example.org/x)
[Inseguro](javascript:alert(1))
![Remota](https://example.org/capa.png)
<script>alert('injetado')</script>
""");
      expect(safe, contains('<h2>Meu título</h2>'));
      expect(safe, contains('<strong>Forte</strong>'));
      expect(safe, contains('<em>ênfase</em>'));
      expect(safe, contains('<u>sublinhado</u>'));
      expect(safe, contains('<del>tachado</del>'));
      expect(safe, contains('☐ Ler depois'));
      expect(safe, contains('<table>'));
      expect(safe, contains('href="https://example.org/x"'));
      expect(safe, isNot(contains('href="javascript:')));
      expect(safe, isNot(contains('capa.png')));
      expect(safe, isNot(contains('injetado')));
    });

    test('As notas de rodapé mantêm referências e o corpo no HTML assinado', () {
      final format = compileArchiveMarkdown(
        'Afirmação verificável.[^fonte]\n\n[^fonte]: Documento público de referência.',
      );
      expect(format, contains('<sup>'));
      expect(format, contains('<h4>Notas de rodapé</h4>'));
      expect(format, contains('Documento público de referência.'));
      expect(NixArchiveService.sanitizeRichTextHtml(format), format);
    });

    test('imagem limpa metadados, acompanha rascunho e integra assinatura', () async {
      final png = File('assets/images/nix_logo_128.png').readAsBytesSync();
      final identifyingText = ascii.encode('Comment\u0000segredo-exif-mark');
      final header = ByteData(4)..setUint32(0, identifyingText.length, Endian.big);
      final withMetadata = Uint8List.fromList([
        ...png.take(33),
        ...header.buffer.asUint8List(),
        ...ascii.encode('tEXt'),
        ...identifyingText,
        0, 0, 0, 0,
        ...png.skip(33),
      ]);
      final image = ArchiveImage.fromPng(withMetadata, caption: 'Diagrama local');
      final exportedBytes = image.bytes;
      exportedBytes[0] = 0;
      expect(image.bytes[0], 137);
      expect(latin1.decode(image.bytes), isNot(contains('segredo-exif-mark')));
      expect(() => ArchiveImage.readList([
        {'png': base64Encode(withMetadata), 'caption': 'Remota'},
      ]), throwsFormatException);

      await archiveService.saveDraft(
        id: 'draft_media', title: 'Título', category: 'Ciência',
        markdownContent: 'Texto', images: [image],
      );
      await archiveService.saveDraft(
        id: 'draft_media', title: 'Título atualizado', category: 'Ciência',
        markdownContent: 'Texto alterado',
      );
      expect((await archiveService.readDraftImages('draft_media')).single.caption, 'Diagrama local');
      final hash = await archiveService.publishArticle(
        author: alice,
        title: 'Artigo com mídia',
        rawHtmlBody: '<p>Texto</p><img src="https://example.test/a.png">',
        images: [image],
      );
      expect(await archiveService.verifyStoredObject(hash), isTrue);
      final signed = (await archiveService.readVerifiedArticleImages(hash)).single;
      expect(signed.bytes, orderedEquals(image.bytes));
      expect(signed.caption, image.caption);
      final row = (await archiveRepo.getObject(hash))!;
      final original = row['canonical_bytes'] as List<int>;
      expect(utf8.decode(original), isNot(contains('example.test/a.png')));
      final altered = Uint8List.fromList(original);
      altered[4] ^= 1;
      await localDb.rawDatabase.update('archive_objects', {'canonical_bytes': altered},
          where: 'hash = ?', whereArgs: [hash]);
      expect(await archiveService.readVerifiedArticleImages(hash), isEmpty);
      await archiveService.deleteDraft('draft_media');
      expect(await archiveService.readDraftImages('draft_media'), isEmpty);
    });

    testWidgets('ArticleDetailView renderiza metadados reais, corpo, alegações e badge Ed25519', (tester) async {
      final articleHash = await archiveService.publishArticle(
        author: alice,
        title: 'Manifesto pela Privacidade Absoluta',
        rawHtmlBody: '<p>A soberania tecnológica é uma necessidade civilizatória.</p>',
        claims: [(claimId: 'claim_1', text: 'Vigilância em massa viola a intimidade humana.')],
        images: [
          ArchiveImage.fromPng(
            File('assets/images/nix_logo_128.png').readAsBytesSync(), caption: 'Imagem assinada',
          ),
        ],
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
      expect(find.byKey(const ValueKey('archive_verified_image_0')), findsOneWidget);
      expect(find.text('Alegações Auditáveis e Refutações (1)'), findsOneWidget);
      expect(find.text('Discussões Encadeadas (0)'), findsOneWidget);
    });

    testWidgets('o autor silenciado pode ser restaurado com a discussão vazia',
        (tester) async {
      final hash = await archiveService.publishArticle(
        author: alice,
        title: 'Artigo com comentário silenciado',
        rawHtmlBody: '<p>Texto original.</p>',
      );
      await archiveService.publishComment(
        author: alice,
        authorPersonaId: 'persona_alice',
        targetObjectHash: hash,
        contentMarkdown: 'Comentário local recuperável.',
      );
      await archiveService.muteAuthor(Uint8List.fromList(alice.ed25519PublicKey.bytes));
      final row = await archiveRepo.getObject(hash);
      await tester.pumpWidget(
        ChangeNotifierProvider<NixState>.value(
          value: nixState,
          child: MaterialApp(home: ArticleDetailView(articleObject: row!)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Comentário local recuperável.'), findsNothing);
      final manage = find.byTooltip('Gerenciar moderação local');
      await tester.ensureVisible(manage);
      await tester.tap(manage);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover moderação'));
      await tester.pumpAndSettle();
      expect(find.text('Nenhum autor silenciado ou bloqueado.'), findsOneWidget);
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      expect(find.text('Discussões Encadeadas (1)'), findsOneWidget);
      expect(await archiveService.verifyStoredObject(hash), isTrue);
    });

    testWidgets('editor exige confirmação antes de publicar a imagem selecionada',
        (tester) async {
      final original = LocalImageHelper.filePickerAdapter;
      addTearDown(() => LocalImageHelper.filePickerAdapter = original);
      LocalImageHelper.filePickerAdapter = ProgrammableFilePickerAdapter(
        nextAttachments: [File('assets/images/nix_logo_128.png').absolute.path],
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<NixState>.value(
          value: nixState,
          child: const MaterialApp(home: NixArchiveEnvironmentView()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Novo Artigo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Título do Artigo'), 'Prova de autorização',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Conteúdo em Markdown / Rich Text'), 'Texto local.',
      );
      final addImage = find.text('Adicionar imagem');
      await tester.ensureVisible(addImage);
      await tester.runAsync(() async {
        await tester.tap(addImage);
        for (var turn = 0; turn < 150; turn++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (find.text('Adicionar imagem ao rascunho').evaluate().isNotEmpty) break;
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('Adicionar imagem ao rascunho'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Legenda ou descrição opcional'), 'Imagem autorizada',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Adicionar'));
        for (var turn = 0; turn < 150; turn++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (find.byTooltip('Remover imagem 1').evaluate().isNotEmpty) break;
        }
      });
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remover imagem 1'), findsOneWidget);
      expect(find.text('Imagem autorizada'), findsOneWidget);

      final publish = find.text('Publicar com Assinatura Ed25519');
      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Publicar as imagens?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(await archiveRepo.listObjects(kind: 'article'), isEmpty);
      expect(find.text('Imagem autorizada'), findsOneWidget);

      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() async {
        await tester.tap(find.text('Publicar imagens'));
        for (var turn = 0; turn < 150; turn++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump(const Duration(milliseconds: 20));
          if (find.text('Assinando e Publicando...').evaluate().isEmpty) break;
        }
      });
      await tester.pumpAndSettle();
      final slot = (await archiveRepo.listObjects(kind: 'article')).single;
      final images = await archiveService.readVerifiedArticleImages(slot['hash'] as String);
      expect(images.single.caption, 'Imagem autorizada');
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

    testWidgets('Editor WYSIWYG no Nix Archive não insere caracteres brutos e gera Markdown canônico', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<NixState>.value(
          value: nixState,
          child: const MaterialApp(
            home: NixArchiveEnvironmentView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Navega para aba Novo Artigo
      await tester.tap(find.text('Novo Artigo'));
      await tester.pumpAndSettle();

      // Encontra o campo de título e preenche
      final titleField = find.widgetWithText(TextField, 'Título do Artigo');
      await tester.enterText(titleField, 'Artigo com WYSIWYG');

      // Encontra o campo de conteúdo
      final contentField = find.byType(TextField).at(2);
      await tester.enterText(contentField, 'Texto formatado');
      await tester.pumpAndSettle();

      // Seleciona palavra "Texto" e clica em Negrito
      final boldBtn = find.byTooltip('Negrito');
      expect(boldBtn, findsOneWidget);

      // Clica em Negrito
      await tester.tap(boldBtn);
      await tester.pumpAndSettle();

      // Verifica que NÃO foram inseridos asteriscos visíveis no campo de texto
      final textFieldWidget = tester.widget<TextField>(contentField);
      expect(textFieldWidget.controller!.text.contains('**'), isFalse);
    });
  });
}
