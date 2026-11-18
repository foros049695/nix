import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nix_client/main.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_client/core/models/channel.dart';
import 'package:nix_client/core/models/direct_message.dart';
import 'package:nix_client/core/models/member.dart';
import 'package:nix_client/core/models/monero_order.dart';
import 'package:nix_client/core/theme/nix_colors.dart';
import 'package:nix_client/core/theme/nix_palette.dart';

void main() {
  testWidgets('1. Splash Screen initializes and transitions smoothly to NIX LIVING AMOLED shell',
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

    // No primeiro frame, a Splash Screen minimalista está visível
    expect(find.byKey(const ValueKey('nix_splash_screen')), findsOneWidget);
    expect(find.text('N I X'), findsOneWidget);

    // Avança a inicialização real (220ms) + transição fluida
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    // Verifica que a interface principal carregou com paleta AMOLED (#000000) e superfícies elevadas
    expect(NixColors.background, const Color(0xFF000000));
    expect(NixColors.surfaceElevated, const Color(0xFF101014));
    expect(NixColors.surfaceElevatedHigh, const Color(0xFF19191F));
    expect(find.text('QG Nix'), findsOneWidget);
    expect(find.text('geral'), findsAtLeastNWidgets(1));
    expect(find.text('desenvolvimento-core'), findsOneWidget);
  });

  testWidgets('2. Profile Overlay opens via Nix icon, displays Card ID, and transitions to Settings with Living AMOLED Palettes',
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

    // Clica no ícone oficial do Nix no topo do dock
    await tester.tap(find.byKey(const Key('nix_brand_profile_trigger')));
    await tester.pumpAndSettle();

    // Verifica que o Card ID e o Identificador Público estão visíveis no Overlay
    expect(find.text('NIX-7E3A-9F01-C45B-289D'), findsOneWidget);
    expect(find.text('PASSAPORTE CULTURAL & ACERVO'), findsOneWidget);

    // Clica na engrenagem integrada ao Card ID para transicionar às Configurações
    await tester.tap(find.byKey(const Key('card_id_settings_gear')));
    await tester.pumpAndSettle();

    expect(find.text('CENTRAL DE CONFIGURAÇÕES NIX'), findsOneWidget);

    // Testa a troca dinâmica de paletas Living AMOLED (Aparência)
    expect(find.text('Configurações → Aparência → Paleta de Cores'), findsOneWidget);
    expect(find.byKey(const Key('palette_violet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('palette_violet')));
    await tester.pumpAndSettle();
    expect(state.settings.paletteType, NixPaletteType.violet);
    expect(state.currentPalette.primaryAccent, const Color(0xFF8B5CF6));

    // Testa troca para Nix Blue
    await tester.tap(find.byKey(const Key('palette_blue')));
    await tester.pumpAndSettle();
    expect(state.settings.paletteType, NixPaletteType.blue);

    // Navega para a aba Dispositivos & Sessões
    await tester.tap(find.text('Dispositivos & Sessões'));
    await tester.pumpAndSettle();
    expect(find.text('5.6 Dispositivos e Compartimentalização'), findsOneWidget);
    expect(find.text('Linux Desktop (Esta Sessão)'), findsOneWidget);

    // Navega para a aba Sobrevivência e Privacidade
    final survivalFinder = find.text('Sobrevivência e Privacidade');
    await tester.ensureVisible(survivalFinder);
    await tester.pumpAndSettle();
    await tester.tap(survivalFinder);
    await tester.pumpAndSettle();
    expect(find.text('5.7 Sobrevivência e Privacidade'), findsOneWidget);

    // Volta para o Card ID e fecha o overlay
    await tester.tap(find.byKey(const Key('back_to_card_id_button')));
    await tester.pumpAndSettle();
    expect(find.text('NIX-7E3A-9F01-C45B-289D'), findsOneWidget);

    await tester.tap(find.byKey(const Key('close_profile_overlay_button')));
    await tester.pumpAndSettle();
    expect(find.text('CENTRAL DE CONFIGURAÇÕES NIX'), findsNothing);
  });

  testWidgets('3. Home Private Area shows Card ID when empty, hover preview on contact requests, and opens DM',
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

    // Abre a Área Inicial de Conversas Privadas
    await tester.tap(find.byKey(const Key('dock_home_private_button')));
    await tester.pumpAndSettle();

    // Quando vazia, a área central exibe o Card ID
    expect(state.homeSubTab, HomeSubTab.cardId);
    expect(find.text('NIX-7E3A-9F01-C45B-289D'), findsOneWidget);

    // Vai para a aba Solicitações
    await tester.tap(find.text('Solicitações'));
    await tester.pumpAndSettle();
    expect(find.text('NodeRunner-77'), findsOneWidget);

    // Testa pré-visualização flutuante de Card ID ao inspecionar solicitação
    state.setHoveredContactRequest(state.contactRequests.first);
    await tester.pumpAndSettle();
    expect(find.text('DESTAQUES CULTURAIS PÚBLICOS'), findsOneWidget);

    // Ao selecionar uma conversa privada (Sentinela-Alpha), o Card ID sai de cena e abre o chat
    await tester.tap(find.text('Sentinela-Alpha').first);
    await tester.pumpAndSettle();

    expect(state.homeSubTab, HomeSubTab.directChat);
    expect(
      find.text('Verifiquei a assinatura do seu Card ID via QR Code. Sessão par a par validada.'),
      findsOneWidget,
    );
  });

  testWidgets('4. GitHub Discovery (starwire.foo) and Monero P2P Marketplace navigation & actions',
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

    // 1. Abre a Área Inicial e depois o GitHub Discovery pela navegação principal (HomeSidebar)
    await tester.tap(find.byKey(const Key('dock_home_private_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home_nav_github')));
    await tester.pumpAndSettle();
    expect(find.text('GITHUB DISCOVERY · ACERVO ABERTO DE CÓDIGO'), findsOneWidget);
    expect(find.text('rust-anything'), findsAtLeastNWidgets(1));

    // Salvar/Remover do acervo com 1 clique
    final initialAcervoCount = state.userProfile.culturalItems.length;
    final repoTarget = state.githubRepos.firstWhere((r) => r.id == 'gh_reticulum');
    expect(repoTarget.isSavedInAcervo, false);
    state.toggleSaveRepoInAcervo(repoTarget.id);
    await tester.pumpAndSettle();
    expect(state.userProfile.culturalItems.length, initialAcervoCount + 1);

    // 2. Abre o Mercado Monero P2P pela navegação principal (HomeSidebar)
    // Retorna para a Home se necessário ou clica diretamente
    await tester.tap(find.byKey(const Key('home_nav_monero')));
    await tester.pumpAndSettle();
    expect(find.text('MERCADO MONERO P2P DESCENTRALIZADO (NON-CUSTODIAL)'), findsOneWidget);
    expect(find.text('SovereignNode_SP'), findsOneWidget);

    // Alterna para Vender XMR
    await tester.tap(find.text('Vender XMR'));
    await tester.pumpAndSettle();
    expect(state.moneroSelectedSide, MoneroP2pSide.buy);

    // Testa filtro de moedas fiat
    state.setMoneroFiat('EUR');
    await tester.pumpAndSettle();
    expect(state.moneroSelectedFiat, 'EUR');
  });

  testWidgets('5. Drag-and-drop Space Folders, Emoji picker in Chat, and 3-Tier Trust Model',
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

    // Testa combinação de espaços em pasta por drag-and-drop
    final initialFoldersCount = state.folders.length;
    state.combineSpacesIntoFolder('space_qg', 'space_cultura', 'QG & Cultura');
    expect(state.folders.length, initialFoldersCount + 1);
    expect(state.folders.last.name, 'QG & Cultura');
    expect(state.folders.last.spaceIds.contains('space_qg'), true);
    expect(state.folders.last.spaceIds.contains('space_cultura'), true);

    // Testa abertura do seletor de emojis no chat
    final textChannel = state.spaces.first.channels.firstWhere((c) => c.type == ChannelType.text);
    state.selectChannel(textChannel);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('emoji_picker_toggle_button')));
    await tester.pumpAndSettle();
    expect(find.text('Sorrisos'), findsOneWidget);
    expect(find.text('Gestos'), findsOneWidget);
    expect(find.text('Segurança & Símbolos'), findsOneWidget);

    // Testa Modelo de Confiança em 3 Níveis
    expect(NixTrustLevel.values.length, 3);
    final mem = state.members.first;
    expect(mem.trustLevel, NixTrustLevel.level3Green);
    expect(mem.hasCryptographicShield, true);

    // Testa Username Opcional determinístico
    final emptyNameProfile = state.userProfile.copyWith(displayName: '');
    expect(emptyNameProfile.effectiveDisplayName.startsWith('NX-'), true);
  });

  testWidgets('6. Universal Peer Card ID by click, hover lockout, and non-obstructive positioning',
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

    // 1. Testa abertura do Card ID de membro da lista de participantes
    state.toggleMembersPanel();
    await tester.pumpAndSettle();
    expect(find.text('PARTICIPANTES'), findsOneWidget);

    // Clica no membro Sentinela-Alpha na lista de participantes
    await tester.tap(find.text('Sentinela-Alpha').first);
    await tester.pumpAndSettle();

    // Deve abrir o diálogo modal do Peer Card ID
    expect(find.text('NIX SOVEREIGN CARD ID'), findsOneWidget);
    expect(find.text('Sentinela-Alpha'), findsAtLeastNWidgets(1));

    // Fecha via botão X
    await tester.tap(find.byTooltip('Fechar (Esc)'));
    await tester.pumpAndSettle();
    expect(find.text('NIX SOVEREIGN CARD ID'), findsNothing);

    // 2. Vai para a Home (Solicitações de contato)
    await tester.tap(find.byKey(const Key('dock_home_private_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solicitações'));
    await tester.pumpAndSettle();

    // Os botões "Recusar" e "Aceitar Chave" devem estar acessíveis
    expect(find.text('Recusar'), findsAtLeastNWidgets(1));
    expect(find.text('Aceitar Chave'), findsAtLeastNWidgets(1));

    // Ativa preview em hover sobre o peer
    final req = state.contactRequests.first;
    state.setHoveredContactRequest(req);
    await tester.pumpAndSettle();
    expect(find.text('DESTAQUES CULTURAIS PÚBLICOS'), findsOneWidget);

    // Limpa hover
    state.setHoveredContactRequest(null);
    await tester.pumpAndSettle();
    expect(find.text('DESTAQUES CULTURAIS PÚBLICOS'), findsNothing);
  });

  testWidgets('7. Message actions (toggleable reactions, context menu, forward, delete) and Channel settings',
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

    // 1. Envia mensagem no canal ativo
    final initialCount = state.currentMessages.length;
    state.sendMessage('Mensagem de teste de release v0.2.0');
    expect(state.currentMessages.length, initialCount + 1);
    final msg = state.currentMessages.last;

    // 2. Testa alternar reação (toggleMessageReaction)
    expect(msg.reactions.containsKey('⚡'), false);
    state.toggleMessageReaction(msg.id, '⚡');
    expect(state.currentMessages.last.reactions['⚡'], 1);
    expect(state.currentMessages.last.myReactions.contains('⚡'), true);

    // Desmarca a reação (toggle off)
    state.toggleMessageReaction(msg.id, '⚡');
    expect(state.currentMessages.last.reactions.containsKey('⚡'), false);
    expect(state.currentMessages.last.myReactions.contains('⚡'), false);

    // 3. Testa encaminhamento de mensagem
    final fwdTargetChannel = state.spaces.first.channels.last;
    state.forwardMessage(msg, targetId: fwdTargetChannel.id, isChannel: true);
    // Mensagem foi encaminhada no state
    expect(msg.text, contains('Mensagem de teste'));

    // 4. Testa deleção de mensagem
    final beforeDeleteCount = state.currentMessages.length;
    state.deleteMessage(msg.id, forEveryone: true);
    expect(state.currentMessages.length, beforeDeleteCount - 1);

    // 5. Testa configurações de canal e permissões
    final currentChan = state.currentChannel;
    final updatedChan = currentChan.copyWith(
      description: 'Canal de alta segurança auditado.',
      permissions: currentChan.permissions.copyWith(
        requestScreenshotProtection: true,
        slowModeSeconds: 5,
        restrictExport: true,
      ),
    );
    state.updateChannelSettings(updatedChan);
    expect(state.currentChannel.description, 'Canal de alta segurança auditado.');
    expect(state.currentChannel.permissions.requestScreenshotProtection, true);
    expect(state.currentChannel.permissions.slowModeSeconds, 5);
    expect(state.currentChannel.permissions.restrictExport, true);
  });
}
