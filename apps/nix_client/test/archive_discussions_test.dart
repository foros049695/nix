import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/archive/nix_archive_service.dart';
import 'package:nix_client/core/database/local_database.dart';
import 'package:nix_client/core/database/repositories/archive_repository.dart';
import 'package:nix_client/core/database/repositories/key_material_repository.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Nix Archive Discussions & Drafts Tests (Fase 19)', () {
    late LocalDatabase localDb;
    late ArchiveRepository archiveRepo;
    late KeyMaterialRepository keyRepo;
    late NixArchiveService archiveService;
    late NixIdentity authorAlice;
    late NixIdentity authorBob;
    late NixIdentity authorCarol;

    setUp(() async {
      localDb = await LocalDatabase.open(
        path: inMemoryDatabasePath,
        requireEncryption: false,
      );
      archiveRepo = ArchiveRepository(localDb);
      keyRepo = KeyMaterialRepository(localDb);
      archiveService = NixArchiveService(archiveRepo);

      authorAlice = await NixIdentity.generate();
      authorBob = await NixIdentity.generate();
      authorCarol = await NixIdentity.generate();

      // Registra personas
      await archiveService.ensurePersonaRegistered(
        identity: authorAlice,
        personaId: 'persona_alice',
        keyMaterialRepo: keyRepo,
        keyRef: 'key_ref_alice',
      );
      await archiveService.ensurePersonaRegistered(
        identity: authorBob,
        personaId: 'persona_bob',
        keyMaterialRepo: keyRepo,
        keyRef: 'key_ref_bob',
      );
      await archiveService.ensurePersonaRegistered(
        identity: authorCarol,
        personaId: 'persona_carol',
        keyMaterialRepo: keyRepo,
        keyRef: 'key_ref_carol',
      );
    });

    tearDown(() async {
      await localDb.close();
    });

    test('Ciclo de vida de rascunhos de artigos: salvar, listar, recuperar e excluir', () async {
      await archiveService.saveDraft(
        id: 'draft_001',
        title: 'Criptografia e Soberania Digital',
        category: 'Tecnologia',
        markdownContent: '# Soberania\nA soberania digital requer infraestrutura sem intermediários.',
        tags: ['crypto', 'tor', 'p2p'],
      );

      final drafts = await archiveService.listDrafts();
      expect(drafts.length, equals(1));
      expect(drafts.first['id'], equals('draft_001'));
      expect(drafts.first['title'], equals('Criptografia e Soberania Digital'));

      final draft = await archiveService.getDraft('draft_001');
      expect(draft, isNotNull);
      expect(draft!['category'], equals('Tecnologia'));
      expect(draft['markdown_content'], contains('A soberania digital'));

      await archiveService.deleteDraft('draft_001');
      final draftsAfter = await archiveService.listDrafts();
      expect(draftsAfter, isEmpty);
    });

    test('Discussões encadeadas (threading), citações e verificação de assinatura Ed25519', () async {
      // 1. Alice publica o artigo original
      final articleHash = await archiveService.publishArticle(
        author: authorAlice,
        title: 'O Fim da Vigilância em Massa',
        rawHtmlBody: '<p>A criptografia de ponta a ponta é um direito humano fundamental.</p>',
        claims: [(claimId: 'claim_1', text: 'E2EE impede vigilância em trânsito.')],
      );
      expect(articleHash, isNotEmpty);
      expect(await archiveService.verifyStoredObject(articleHash), isTrue);

      // 2. Bob adiciona um comentário raiz sobre o artigo
      final comment1Hash = await archiveService.publishComment(
        author: authorBob,
        authorPersonaId: 'persona_bob',
        targetObjectHash: articleHash,
        contentMarkdown: 'Concordo integralmente com a premissa.',
      );
      expect(comment1Hash, isNotEmpty);
      expect(await archiveService.verifyStoredComment(comment1Hash), isTrue);

      // 3. Carol responde ao comentário de Bob (nível 1 de encadeamento) com citação
      final comment2Hash = await archiveService.publishComment(
        author: authorCarol,
        authorPersonaId: 'persona_carol',
        targetObjectHash: articleHash,
        parentCommentHash: comment1Hash,
        contentMarkdown: 'Exato, mas precisamos de transportes resistentes a metadados.',
        quoteText: 'Concordo integralmente com a premissa.',
      );
      expect(comment2Hash, isNotEmpty);
      expect(await archiveService.verifyStoredComment(comment2Hash), isTrue);

      // 4. Bob responde a Carol (nível 2 de encadeamento)
      final comment3Hash = await archiveService.publishComment(
        author: authorBob,
        authorPersonaId: 'persona_bob',
        targetObjectHash: articleHash,
        parentCommentHash: comment2Hash,
        contentMarkdown: 'O Tor e roteamento cebola resolvem essa camada.',
      );
      expect(comment3Hash, isNotEmpty);
      expect(await archiveService.verifyStoredComment(comment3Hash), isTrue);

      // 5. Alice responde na raiz (outro comentário raiz)
      final comment4Hash = await archiveService.publishComment(
        author: authorAlice,
        authorPersonaId: 'persona_alice',
        targetObjectHash: articleHash,
        contentMarkdown: 'Obrigada pelas contribuições ao debate!',
      );
      expect(comment4Hash, isNotEmpty);

      // 6. Verifica estrutura da árvore de comentários
      final threads = await archiveService.getThreadedComments(articleHash);
      expect(threads.length, equals(4));

      // Ordem da árvore: Root Bob (0) -> Reply Carol (1) -> Reply Bob (2) -> Root Alice (0)
      expect(threads[0]['hash'], equals(comment1Hash));
      expect(threads[0]['thread_depth'], equals(0));

      expect(threads[1]['hash'], equals(comment2Hash));
      expect(threads[1]['thread_depth'], equals(1));
      expect(threads[1]['quote_text'], equals('Concordo integralmente com a premissa.'));

      expect(threads[2]['hash'], equals(comment3Hash));
      expect(threads[2]['thread_depth'], equals(2));

      expect(threads[3]['hash'], equals(comment4Hash));
      expect(threads[3]['thread_depth'], equals(0));
    });

    test('Moderação local silencia autor sem invalidar assinaturas', () async {
      final articleHash = await archiveService.publishArticle(
        author: authorAlice,
        title: 'Artigo de Teste de Moderação',
        rawHtmlBody: '<p>Conteúdo relevante.</p>',
      );

      // Comentário legítimo de Bob
      await archiveService.publishComment(
        author: authorBob,
        authorPersonaId: 'persona_bob',
        targetObjectHash: articleHash,
        contentMarkdown: 'Comentário útil de Bob.',
      );

      // Comentário indesejado de Carol (ex: spam)
      await archiveService.publishComment(
        author: authorCarol,
        authorPersonaId: 'persona_carol',
        targetObjectHash: articleHash,
        contentMarkdown: 'Comentário ofensivo ou spam.',
      );

      final commentsBefore = await archiveService.getThreadedComments(articleHash);
      expect(commentsBefore.length, equals(2));

      // Bloqueia localmente a autora Carol
      final carolPub = Uint8List.fromList(authorCarol.ed25519PublicKey.bytes);
      await archiveService.blockAuthor(carolPub, reason: 'Spam excessivo');
      expect(await archiveService.isAuthorModerated(carolPub), isTrue);

      // Consulta filtrada oculta os comentários de Carol
      final commentsFiltered = await archiveService.getThreadedComments(articleHash);
      expect(commentsFiltered.length, equals(1));
      expect(commentsFiltered.first['author_persona_id'], equals('persona_bob'));

      // Consulta sem filtro preserva a persistência criptográfica auditável
      final commentsUnfiltered = await archiveService.getThreadedComments(
        articleHash,
        filterModerated: false,
      );
      expect(commentsUnfiltered.length, equals(2));

      // Desbloqueia e restabelece a visibilidade
      await archiveService.unmoderateAuthor(carolPub);
      expect(await archiveService.isAuthorModerated(carolPub), isFalse);

      final commentsAfterUnblock = await archiveService.getThreadedComments(articleHash);
      expect(commentsAfterUnblock.length, equals(2));
    });

    test('Diferenciação formal entre comentários de discussão e refutações estruturadas', () async {
      final articleHash = await archiveService.publishArticle(
        author: authorAlice,
        title: 'Teoria da Informação',
        rawHtmlBody: '<p>Premissas fundamentais.</p>',
        claims: [(claimId: 'claim_alpha', text: 'Entropia termodinâmica equivale à informacional.')],
      );

      // Comentário informal de discussão
      final commentHash = await archiveService.publishComment(
        author: authorBob,
        authorPersonaId: 'persona_bob',
        targetObjectHash: articleHash,
        contentMarkdown: 'Discussão livre sobre o tema.',
      );

      // Refutação formal técnica vinculada a uma alegação específica
      final refutationHash = await archiveService.publishRefutation(
        author: authorCarol,
        targetHash: articleHash,
        targetClaimId: 'claim_alpha',
        rationaleHtml: '<p>Demonstração formal de distinção matemática entre as duas entropias.</p>',
      );

      final commentObj = await archiveRepo.getComment(commentHash);
      expect(commentObj, isNotNull);

      final refutationObj = await archiveRepo.getObject(refutationHash);
      expect(refutationObj, isNotNull);
      expect(refutationObj!['kind'], equals('refutation'));

      final refutations = await archiveRepo.listRefutationsForTarget(articleHash);
      expect(refutations.length, equals(1));
      expect(refutations.first['target_claim_id'], equals('claim_alpha'));
      expect(refutations.first['refutation_hash'], equals(refutationHash));
    });
  });
}
