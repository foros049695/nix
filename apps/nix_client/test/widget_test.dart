import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nix_client/main.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_client/core/models/channel.dart';
import 'package:nix_client/core/models/direct_message.dart';
import 'package:nix_client/core/models/user_settings.dart';
import 'package:nix_client/core/theme/nix_colors.dart';
import 'package:nix_client/core/security/window_privacy_guard.dart';

void main() {
  testWidgets('1. Splash Screen initializes and transitions smoothly to NIX AMOLED shell',
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

    // Verifica que a interface principal carregou com paleta AMOLED (#000000)
    expect(NixColors.background, const Color(0xFF000000));
    expect(find.text('QG Nix'), findsOneWidget);
    expect(find.text('geral'), findsAtLeastNWidgets(1));
    expect(find.text('desenvolvimento-core'), findsOneWidget);
  });

  testWidgets('2. Profile Overlay opens via Nix icon, displays Card ID, and transitions to Settings',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NixState(),
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
    expect(find.text('5.1 Notificações e Sons'), findsOneWidget);

    // Navega para a aba 5.6 Sobrevivência e Privacidade
    await tester.tap(find.text('Sobrevivência e Privacidade'));
    await tester.pumpAndSettle();
    expect(find.text('5.6 Sobrevivência e Privacidade'), findsOneWidget);

    // Volta para o Card ID e fecha o overlay
    await tester.tap(find.byKey(const Key('back_to_card_id_button')));
    await tester.pumpAndSettle();
    expect(find.text('NIX-7E3A-9F01-C45B-289D'), findsOneWidget);

    await tester.tap(find.byKey(const Key('close_profile_overlay_button')));
    await tester.pumpAndSettle();
    expect(find.text('CENTRAL DE CONFIGURAÇÕES NIX'), findsNothing);
  });

  testWidgets('3. Home Private Area shows Card ID when empty and opens chat when DM is selected',
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

    // Ao selecionar uma conversa privada (Sentinela-Alpha), o Card ID sai de cena e abre o chat
    await tester.tap(find.text('Sentinela-Alpha').first);
    await tester.pumpAndSettle();

    expect(state.homeSubTab, HomeSubTab.directChat);
    expect(
      find.text('Verifiquei a assinatura do seu Card ID via QR Code. Sessão par a par validada.'),
      findsOneWidget,
    );
  });

  testWidgets('4. Explore view lists public spaces from least populous to most populous & Forum works',
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

    // Verifica ordenação padrão: do menos populoso (8 membros) ao mais populoso (48 membros)
    final sorted = state.filteredDiscoverableSpaces;
    expect(sorted.first.memberCount <= sorted.last.memberCount, true);
    expect(sorted.first.name, 'Laboratório Pós-Quântico');

    // Abre a aba Explorar na UI
    await tester.tap(find.byKey(const Key('dock_explore_button')));
    await tester.pumpAndSettle();
    expect(find.text('EXPLORAR COMUNIDADES & CANAIS PÚBLICOS'), findsOneWidget);

    // Muda para o canal de Fórum / Tópicos Interativos (topicos-e-achados)
    final forumChannel =
        state.spaces.first.channels.firstWhere((c) => c.type == ChannelType.forum);
    state.selectSpace(state.spaces.first);
    state.selectChannel(forumChannel);
    await tester.pumpAndSettle();

    expect(find.text('Kit Transceiver LoRa RAK4631 + Antena 915MHz'), findsAtLeastNWidgets(1));
  });

  test('5. Anti-fingerprinting Viewport Quantization & Regression tests', () {
    // Discretização de viewport em múltiplos de 64px
    final quantized = WindowPrivacyGuard.quantizeSize(const Size(1366, 768));
    expect(quantized.width % 64, 0);
    expect(quantized.height % 64, 0);

    final state = NixState();
    expect(state.currentChannel.name, 'geral');
    final initialCount = state.currentMessages.length;

    // Enviar mensagem
    state.sendMessage('Mensagem de teste automatizado');
    expect(state.currentMessages.length, initialCount + 1);
    expect(state.currentMessages.last.text, 'Mensagem de teste automatizado');

    // Entrar e sair da call
    final callChannel =
        state.currentSpace.channels.firstWhere((c) => c.type == ChannelType.voice);
    state.joinCall(callChannel);
    expect(state.callState.isConnected, true);
    state.toggleMute();
    expect(state.callState.isMuted, true);
    state.leaveCall();
    expect(state.callState.isConnected, false);

    // Criar canal e pasta
    state.createChannel(
      name: 'sala-secreta-01',
      type: ChannelType.text,
      topic: 'Tópico exclusivo',
      category: 'COMUNIDADE',
    );
    expect(state.currentChannel.name, 'sala-secreta-01');

    // Persistência de configurações em memória
    state.updateSettings(state.settings.copyWith(fontScale: 1.15, silentMode: true));
    expect(state.settings.fontScale, 1.15);
    expect(state.settings.silentMode, true);
    expect(SettingsCategory.values.length, 6);
  });
}
