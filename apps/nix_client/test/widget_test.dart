import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nix_client/core/models/channel.dart';
import 'package:nix_client/core/models/direct_message.dart';
import 'package:nix_client/core/models/member.dart';
import 'package:nix_client/core/models/monero_order.dart';
import 'package:nix_client/core/security/local_image_helper.dart';
import 'package:nix_client/core/theme/nix_colors.dart';
import 'package:nix_client/core/theme/nix_palette.dart';
import 'package:nix_client/main.dart';
import 'package:nix_client/state/nix_state.dart';

void main() {
  testWidgets('1. Splash Screen initializes and transitions to V4 Dark Yellow default shell',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NixState(),
        child: const NixApp(skipSplash: false),
      ),
    );

    expect(find.byKey(const ValueKey('nix_splash_screen')), findsOneWidget);
    expect(find.text('N I X'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpAndSettle();

    // Dark Yellow V4 padrão oficial (#08090B bg, #17191E surface, #292C33 elevated, #FFC928 accent)
    expect(NixColors.background, const Color(0xFF08090B));
    expect(NixColors.surfaceCard, const Color(0xFF17191E));
    expect(NixColors.surfaceElevated, const Color(0xFF292C33));
    expect(NixColors.accentYellow, const Color(0xFFFFC928));

    expect(find.text('QG Nix'), findsAtLeastNWidgets(1));
    expect(find.text('geral'), findsAtLeastNWidgets(1));
    expect(find.text('desenvolvimento-core'), findsOneWidget);
  });

  testWidgets('2. Settings -> Aparencia -> Temas switches Light Yellow, AMOLED, System, and Accent Palettes',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final state = NixState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const NixApp(skipSplash: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nix_brand_profile_trigger')));
    await tester.pumpAndSettle();

    expect(find.text('NIX-7E3A-9F01-C45B-289D'), findsOneWidget);
    await tester.tap(find.byKey(const Key('card_id_settings_gear')));
    await tester.pumpAndSettle();

    expect(find.text('CENTRAL DE CONFIGURAÇÕES NIX'), findsOneWidget);
    expect(find.text('Configurações → Aparência → Temas'), findsOneWidget);

    // Light Yellow (#FFFFFF bg, #F6F7F9 surface, #E9EBEF elevated)
    await tester.tap(find.byKey(const Key('theme_mode_light_yellow')));
    await tester.pumpAndSettle();
    expect(state.settings.themeMode, NixThemeMode.lightYellow);
    expect(NixColors.background, const Color(0xFFFFFFFF));
    expect(NixColors.surfaceCard, const Color(0xFFF6F7F9));
    expect(NixColors.surfaceElevated, const Color(0xFFE9EBEF));
    expect(NixColors.textPrimary, const Color(0xFF17191E));

    // AMOLED (#000000 bg)
    await tester.tap(find.byKey(const Key('theme_mode_amoled')));
    await tester.pumpAndSettle();
    expect(state.settings.themeMode, NixThemeMode.amoled);
    expect(NixColors.background, const Color(0xFF000000));

    // Sistema e volta ao Dark Yellow
    await tester.tap(find.byKey(const Key('theme_mode_system')));
    await tester.pumpAndSettle();
    expect(state.settings.themeMode, NixThemeMode.system);

    await tester.tap(find.byKey(const Key('theme_mode_dark_yellow')));
    await tester.pumpAndSettle();
    expect(NixColors.background, const Color(0xFF08090B));

    // Personalização da cor de destaque
    await tester.tap(find.byKey(const Key('palette_violet')));
    await tester.pumpAndSettle();
    expect(state.settings.paletteType, NixPaletteType.violet);
    expect(state.currentPalette.primaryAccent, const Color(0xFF8B5CF6));

    // Abas Dispositivos, Sobrevivência e Privacidade (Visibilidade Card ID)
    await tester.tap(find.text('Privacidade e Segurança'));
    await tester.pumpAndSettle();
    expect(find.text('Privacidade → Visibilidade do Card ID'), findsOneWidget);

    await tester.tap(find.text('Dispositivos & Sessões'));
    await tester.pumpAndSettle();
    expect(find.text('5.6 Dispositivos e Compartimentalização'), findsOneWidget);

    final survivalFinder = find.text('Sobrevivência e Privacidade');
    await tester.ensureVisible(survivalFinder);
    await tester.pumpAndSettle();
    await tester.tap(survivalFinder);
    await tester.pumpAndSettle();
    expect(find.text('5.7 Sobrevivência e Privacidade'), findsOneWidget);

    await tester.tap(find.byKey(const Key('back_to_card_id_button')));
    await tester.pumpAndSettle();
    expect(find.text('NIX-7E3A-9F01-C45B-289D'), findsOneWidget);

    await tester.tap(find.byKey(const Key('close_profile_overlay_button')));
    await tester.pumpAndSettle();
  });

  testWidgets('3. Clean Card ID removes Assistindo & duplicate QR, enforces deterministic fallback and EXIF stripping',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final state = NixState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const NixApp(skipSplash: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dock_home_private_button')));
    await tester.pumpAndSettle();

    // Limpeza visual exigida na Seção 7
    expect(find.text('Assistindo'), findsNothing);
    expect(find.text('QR ID'), findsNothing);
    expect(find.text('NIX-7E3A-9F01-C45B-289D'), findsOneWidget);

    // Fallback determinístico quando username é omitido
    final anon = state.userProfile.copyWith(displayName: '');
    expect(anon.effectiveDisplayName, state.userProfile.copyWith(displayName: '').effectiveDisplayName);
    expect(anon.effectiveDisplayName, startsWith('NX-'));

    // Remoção de segmento JPEG APP1 EXIF em memória
    final fakeJpegWithExif = Uint8List.fromList([
      0xFF, 0xD8, // SOI
      0xFF, 0xE1, 0x00, 0x06, 0x45, 0x78, 0x69, 0x66, // APP1 "Exif" (len 6 = 2+4 bytes)
      0xFF, 0xDA, 0x00, 0x03, 0x01, 0xFF, 0xD9, // SOS + data + EOI
    ]);
    final strippedJpeg = LocalImageHelper.stripMetadataBytes(fakeJpegWithExif);
    expect(strippedJpeg, equals(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x03, 0x01, 0xFF, 0xD9])));
  });

  testWidgets('4. Peer Card ID anti-flicker hover lockout, middle positioning, privacy gate and Saved Messages',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final state = NixState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const NixApp(skipSplash: true),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Mensagens Salvas accessible e sem nomes pessoais hardcoded
    await tester.tap(find.byKey(const Key('dock_home_private_button')));
    await tester.pumpAndSettle();
    expect(find.text('Mensagens Salvas'), findsAtLeastNWidgets(1));

    await tester.tap(find.byKey(const Key('dm_item_dm_saved_messages')));
    await tester.pumpAndSettle();
    expect(state.homeSubTab, HomeSubTab.directChat);
    expect(state.selectedDm?.isSavedMessages, true);
    state.sendDirectMessage('Anotação privada local v4');
    await tester.pumpAndSettle();
    expect(find.text('Anotação privada local v4'), findsAtLeastNWidgets(1));

    // 2. Solicitações -> Hover state machine com lockout do botão X + bloqueio por privacidade
    await tester.tap(find.text('Solicitações'));
    await tester.pumpAndSettle();
    expect(find.text('Recusar'), findsAtLeastNWidgets(1));
    expect(find.text('Aceitar Chave'), findsAtLeastNWidgets(1));

    final req = state.contactRequests.first;
    state.onRequestPeerHoverEnter(req);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('floating_peer_card_id_preview')), findsOneWidget);
    expect(find.text('DESTAQUES CULTURAIS PÚBLICOS'), findsOneWidget);

    // Garante que o cartão flutuante não invade a zona direita dos botões Aceitar/Recusar
    final cardRect = tester.getRect(find.byKey(const Key('floating_peer_card_id_preview')));
    final acceptRect = tester.getRect(find.text('Aceitar Chave').first);
    expect(cardRect.right <= acceptRect.left, isTrue);

    // Fechar explicitamente pelo X aciona lockout impedindo reabertura imediata até cursor sair
    await tester.tap(find.byKey(const Key('floating_card_id_close_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('floating_peer_card_id_preview')), findsNothing);

    state.onRequestPeerHoverEnter(req); // cursor ainda na região: continua fechado (sem flickering!)
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('floating_peer_card_id_preview')), findsNothing);

    state.onRequestPeerHoverExit(req); // cursor sai da zona de ativação -> libera nova interação
    state.onRequestPeerHoverEnter(req);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('floating_peer_card_id_preview')), findsOneWidget);
    state.dismissHoveredPeerCard();
    await tester.pumpAndSettle();

    // Regra de privacidade aplicada aos dados no estado (não apenas visual)
    final hiddenAuth = state.getAuthorizedPeerCardData(
      peerName: 'Peer Oculto',
      peerPublicId: 'NIX-0000-0000-0000-0000',
      trustLevel: NixTrustLevel.level1Red,
      hasCryptographicShield: false,
      rawBio: 'Bio Secreta Não Autorizada',
      rawHighlights: ['Item Privado X'],
      ownerVisibility: 'Oculto',
      isVerifiedContact: false,
    );
    expect(hiddenAuth.isAuthorized, isFalse);
    expect(hiddenAuth.bio, contains('Dados restritos'));
    expect(hiddenAuth.culturalHighlights, isEmpty);
  });

  testWidgets('5. Telegram-inspired Space Folders CRUD preserves spaces and Folder tabs filter safely',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final state = NixState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const NixApp(skipSplash: true),
      ),
    );
    await tester.pumpAndSettle();

    final initialSpacesCount = state.spaces.length;
    final initialFoldersCount = state.folders.length;

    state.combineSpacesIntoFolder('space_qg', 'space_cultura', 'QG & Cultura');
    expect(state.folders.length, initialFoldersCount + 1);
    final createdFolder = state.folders.last;
    expect(createdFolder.name, 'QG & Cultura');

    state.selectFolder(createdFolder.id);
    expect(state.visibleSpacesForFolder.length, 2);

    // Excluir pasta NÃO exclui os espaços/conversas contidos nela
    state.dissolveFolder(createdFolder.id);
    expect(state.folders.length, initialFoldersCount);
    expect(state.spaces.length, initialSpacesCount);
    expect(state.activeFolderId, equals('all'));
  });

  testWidgets('6. Full Message Actions, Emoji Picker, Header Info Panel and Channel Settings',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final state = NixState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const NixApp(skipSplash: true),
      ),
    );
    await tester.pumpAndSettle();

    final textChannel = state.spaces.first.channels.firstWhere((c) => c.type == ChannelType.text);
    state.selectChannel(textChannel);
    await tester.pumpAndSettle();

    // Envia, responde, edita, fixa e reage em mensagem
    state.sendMessage('Texto inicial V4');
    final sent = state.currentMessages.last;
    state.startEditMessage(sent);
    state.sendMessage('Texto editado V4');
    expect(state.currentMessages.last.text, 'Texto editado V4');
    expect(state.currentMessages.last.isEdited, isTrue);

    state.togglePinMessage(sent.id);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pinned_message_banner')), findsOneWidget);

    state.toggleMessageReaction(sent.id, '⚡');
    expect(state.currentMessages.last.reactions['⚡'], 1);

    // Encaminha a versão editada para Mensagens Salvas
    final editedMsg = state.currentMessages.last;
    state.forwardMessage(editedMsg, targetId: 'dm_saved_messages', isChannel: false);
    final savedDm = state.directMessages.firstWhere((d) => d.isSavedMessages);
    expect(savedDm.messages.any((m) => m.text == 'Texto editado V4' && m.forwardedFrom != null), isTrue);

    // Clica no cabeçalho para abrir Painel de Informações da Conversa (estilo Telegram Desktop)
    await tester.tap(find.byKey(const Key('channel_info_panel_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation_info_panel')), findsOneWidget);

    // Abre Emoji Picker e verifica busca/categorias
    await tester.tap(find.byKey(const Key('emoji_picker_toggle_button')));
    await tester.pumpAndSettle();
    expect(find.text('Sorrisos'), findsOneWidget);
    expect(find.text('Segurança & Símbolos'), findsOneWidget);

    // Atualiza permissões granulares de canal & proteção de prévias
    final updated = state.currentChannel.copyWith(
      permissions: state.currentChannel.permissions.copyWith(
        protectPreviews: true,
        allowVideos: false,
        slowModeSeconds: 15,
      ),
    );
    state.updateChannelSettings(updated);
    expect(state.currentChannel.permissions.protectPreviews, isTrue);
    expect(state.currentChannel.permissions.allowVideos, isFalse);
    expect(state.currentChannel.permissions.slowModeSeconds, 15);
  });

  testWidgets('7. Starwire GitHub Discovery Analytics Charts, Monero P2P Verification and Offline App Share Modal',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final state = NixState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const NixApp(skipSplash: true),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Starwire GitHub Discovery
    await tester.tap(find.byKey(const Key('dock_home_private_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home_nav_github')));
    await tester.pumpAndSettle();

    expect(find.text('STARWIRE GITHUB DISCOVERY · ACERVO ABERTO'), findsOneWidget);
    expect(find.byKey(const Key('starwire_analytics_panel')), findsOneWidget);
    expect(state.githubLanguageCounts.isNotEmpty, isTrue);

    // Salvar no Acervo mantém privado por padrão no Card ID
    final targetRepo = state.githubRepos.firstWhere((r) => !r.isSavedInAcervo);
    state.toggleSaveRepoInAcervo(targetRepo.id);
    final savedItem = state.userProfile.culturalItems.lastWhere((i) => i.title == targetRepo.name);
    expect(savedItem.isPublicInCardId, isFalse);

    // 2. Monero P2P com verificação de assinatura e expiração
    await tester.tap(find.byKey(const Key('home_nav_monero')));
    await tester.pumpAndSettle();
    expect(find.text('MERCADO MONERO P2P DESCENTRALIZADO (NON-CUSTODIAL)'), findsOneWidget);

    final firstOrder = state.moneroOrders.first;
    expect(state.verifyMoneroOrder(firstOrder), isTrue);

    final expiredOrder = MoneroP2pOrder(
      id: 'ord_exp',
      traderName: 'ExpiredPeer',
      traderPublicId: 'NIX-EXPD',
      side: MoneroP2pSide.sell,
      fiatCurrency: 'BRL',
      pricePerXmr: 900,
      minFiatLimit: 100,
      maxFiatLimit: 500,
      paymentMethod: 'PIX',
      signedManifestHash: 'ed25519_exp',
      signatureHex: 'abc',
      expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
    );
    expect(state.verifyMoneroOrder(expiredOrder), isFalse);

    // 3. Modal Compartilhar App Offline (estilo Briar)
    await tester.tap(find.byKey(const Key('home_nav_share_offline')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('share_app_offline_dialog')), findsOneWidget);
    expect(find.text('Compartilhar Nix Offline'), findsOneWidget);
  });
}
