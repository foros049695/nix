import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/media/catalog_database.dart';
import 'package:nix_client/core/models/direct_message.dart';
import 'package:nix_client/core/models/message.dart';
import 'package:nix_client/core/models/publication.dart';
import 'package:nix_client/core/models/user_settings.dart';
import 'package:nix_client/core/theme/nix_palette.dart';
import 'package:nix_client/features/archive/archive_view_model.dart';
import 'package:nix_client/features/chat/chat_view_model.dart';
import 'package:nix_client/features/identity/identity_view_model.dart';
import 'package:nix_client/features/media/media_view_model.dart';
import 'package:nix_client/features/navigation/navigation_view_model.dart';
import 'package:nix_client/features/settings/settings_view_model.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Etapa 8 — Desacoplamento e ViewModels Unit Tests', () {
    test('NavigationViewModel: transições de área e subtabs isoladas', () {
      final nav = NavigationViewModel();
      int notifyCount = 0;
      nav.addListener(() => notifyCount++);

      expect(nav.activeArea, NixActiveArea.spaces);
      nav.setActiveArea(NixActiveArea.mediaIndex);
      expect(nav.activeArea, NixActiveArea.mediaIndex);
      expect(notifyCount, 1);

      nav.setHomeSubTab(HomeSubTab.directChat);
      expect(nav.homeSubTab, HomeSubTab.directChat);
      expect(notifyCount, 2);

      nav.dispose();
    });

    test('ChatViewModel: seleção, composição e preview de DMs', () {
      final chat = ChatViewModel();
      int notifyCount = 0;
      chat.addListener(() => notifyCount++);

      final dm = DirectMessageThread(
        id: 'peer_1',
        peerName: 'Satoshi',
        peerPublicId: 'NX-1111',
        statusText: 'Disponível',
        messages: [],
      );
      chat.setDirectMessages([dm]);
      chat.selectDm(dm);
      expect(chat.selectedDm?.id, 'peer_1');

      final msg = Message(
        id: 'm1',
        channelId: 'peer_1',
        senderName: 'Satoshi',
        senderFingerprint: 'NX-1111',
        isMe: false,
        text: 'Olá mundo soberano',
        timestamp: DateTime.now(),
      );
      chat.addMessage('peer_1', msg);
      expect(chat.getMessagesForChannel('peer_1').length, 1);
      expect(chat.directMessages.first.unreadCount, 1);

      chat.markThreadRead('peer_1');
      expect(chat.directMessages.first.unreadCount, 0);

      chat.toggleMessageSelection('m1');
      expect(chat.selectedMessageIds.contains('m1'), isTrue);
      chat.clearMessageSelection();
      expect(chat.selectedMessageIds.isEmpty, isTrue);

      chat.dispose();
    });

    test('IdentityViewModel: atualização determinística de persona e contexto', () async {
      final idVm = IdentityViewModel();
      int notifyCount = 0;
      idVm.addListener(() => notifyCount++);

      idVm.updateDisplayName('Alice');
      expect(idVm.effectiveDisplayName, 'Alice');
      expect(idVm.securityContext.myPersona, 'Alice');
      expect(notifyCount, 1);

      final identity = await NixIdentity.generate();
      idVm.setPrimaryIdentity(identity);
      expect(idVm.hasIdentity, isTrue);
      expect(idVm.publicId, identity.publicId);
      expect(idVm.securityContext.myFingerprint, identity.publicId);

      idVm.dispose();
    });

    test('SettingsViewModel: persistência e atualização de opções', () async {
      final tmpDir = await Directory.systemTemp.createTemp('nix_settings_test_');
      final path = '${tmpDir.path}/settings.json';
      final vm = SettingsViewModel(storageFilePath: path);

      int notifyCount = 0;
      vm.addListener(() => notifyCount++);

      vm.setThemeMode(NixThemeMode.amoled);
      expect(vm.themeMode, NixThemeMode.amoled);
      expect(notifyCount, 1);

      // Espera salvar em disco assincronamente
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(File(path).existsSync(), isTrue);

      final vm2 = SettingsViewModel(storageFilePath: path);
      await vm2.loadFromDisk();
      expect(vm2.themeMode, NixThemeMode.amoled);

      vm.dispose();
      vm2.dispose();
      await tmpDir.delete(recursive: true);
    });

    test('ArchiveViewModel: rascunhos, cache de verificação e publicações', () async {
      final archiveVm = ArchiveViewModel();
      int notifyCount = 0;
      archiveVm.addListener(() => notifyCount++);

      expect(archiveVm.hasDraft, isFalse);
      archiveVm.saveDraft(
        title: 'Manifesto Soberano',
        content: 'O conteúdo não pode ser censurado.',
        claims: ['Claim 1: Descentralização'],
      );
      expect(archiveVm.hasDraft, isTrue);
      expect(archiveVm.draftTitle, 'Manifesto Soberano');

      final pub = Publication(
        id: 'pub_1',
        channelId: 'ch_archive',
        title: 'Manifesto Soberano',
        authorPersona: 'Alice',
        authorFingerprint: 'NX-ALICE',
        contentMarkdown: 'Conteúdo...',
        claimsCount: 1,
        refutationsCount: 0,
        cidHash: 'hash_test_123',
        publishedAt: DateTime.now().toUtc(),
        isVerifiedSignature: true,
      );

      archiveVm.addPublication('ch_archive', pub);
      expect(archiveVm.getPublicationsForChannel('ch_archive').length, 1);
      expect(archiveVm.verificationCache['hash_test_123'], ArchiveCryptoStatus.verified);

      archiveVm.clearDraft();
      expect(archiveVm.hasDraft, isFalse);

      archiveVm.dispose();
    });

    test('MediaViewModel: busca FTS5, paginação e limite de memória', () async {
      final db = await CatalogDatabase.open(inMemory: true);
      // Insere registros para teste de paginação e busca
      final works = <CatalogWork>[
        for (int i = 1; i <= 60; i++)
          CatalogWork(
            id: 'work_$i',
            kind: 'anime',
            title: 'Cyberpunk Edgerunners Ep $i',
            releaseYear: 2022,
            updatedAt: 1000,
          ),
      ];
      await db.batchUpsertWorks(works);

      final mediaVm = MediaViewModel(catalogDatabase: db);
      int notifyCount = 0;
      mediaVm.addListener(() => notifyCount++);

      await mediaVm.search(query: 'Cyberpunk', refresh: true);
      expect(mediaVm.searchResults.length, 50); // Primeira página de 50
      expect(mediaVm.hasMore, isTrue);

      await mediaVm.loadMore();
      expect(mediaVm.searchResults.length, 60); // Total de 60
      expect(mediaVm.hasMore, isFalse);

      // Teste de salvamento no acervo pessoal
      mediaVm.toggleSaveAcervoId('work_1');
      expect(mediaVm.isSaved('work_1'), isTrue);
      mediaVm.toggleSaveAcervoId('work_1');
      expect(mediaVm.isSaved('work_1'), isFalse);

      mediaVm.dispose();
      await db.close();
    });

    test('NixState integra todos os ViewModels com backward compatibility', () {
      final state = NixState(loadMockData: true);

      expect(state.navigation, isNotNull);
      expect(state.chatVm, isNotNull);
      expect(state.identityVm, isNotNull);
      expect(state.mediaVm, isNotNull);
      expect(state.archiveVm, isNotNull);
      expect(state.settingsVm, isNotNull);

      // Verificação da API de compatibilidade existente
      expect(state.activeArea, NixActiveArea.spaces);
      state.openMediaIndexArea();
      expect(state.activeArea, NixActiveArea.mediaIndex);

      state.dispose();
    });
  });
}
