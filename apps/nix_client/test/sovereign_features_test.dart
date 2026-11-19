import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_client/features/dialogs/sovereign_onboarding_dialog.dart';
import 'package:nix_client/features/settings/settings_center.dart';
import 'package:nix_client/core/models/user_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SovereignOnboardingDialog guia o usuário através da máquina de estados em 9 etapas', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nixState = NixState();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => SovereignOnboardingDialog.show(ctx, nixState),
              child: const Text('Abrir Onboarding'),
            ),
          ),
        ),
      ),
    );

    // Abre o onboarding
    await tester.tap(find.text('Abrir Onboarding'));
    await tester.pumpAndSettle();

    // Etapa 1: WELCOME
    expect(find.text('Bem-vindo ao Projeto Nix'), findsOneWidget);
    expect(find.text('ETAPA 1 DE 9'), findsOneWidget);

    // Avança para Etapa 2: TOR_CONSENT
    await tester.tap(find.byKey(const Key('onboarding_next_button')));
    await tester.pumpAndSettle();

    expect(find.text('Consentimento da Rede Tor (Fail-Closed)'), findsOneWidget);
    expect(find.text('ETAPA 2 DE 9'), findsOneWidget);

    // Tentar avançar sem consentimento não altera a etapa (botão desativado)
    await tester.tap(find.byKey(const Key('onboarding_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('ETAPA 2 DE 9'), findsOneWidget);

    // Clica no consentimento
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    // Alterna painel de diagnóstico
    await tester.tap(find.text('Diagnóstico'));
    await tester.pumpAndSettle();
    expect(find.text('DIAGNÓSTICO TÉCNICO:'), findsOneWidget);

    // Fecha o assistente de onboarding com segurança
    await tester.tap(find.byTooltip('Pausar Configuração'));
    await tester.pumpAndSettle();

    expect(find.text('Pausar Configuração Soberana?'), findsOneWidget);
    await tester.tap(find.text('Pausar e Sair'));
    await tester.pumpAndSettle();

    expect(find.byType(SovereignOnboardingDialog), findsNothing);
  });

  testWidgets('SettingsCenter exibe controles de Tor Embutido, Malha Bluetooth e Botão de Pânico', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nixState = NixState();

    await tester.pumpWidget(
      ChangeNotifierProvider<NixState>.value(
        value: nixState,
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsCenter(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Navega para a aba de Conexões
    nixState.selectSettingsCategory(SettingsCategory.connections);
    await tester.pumpAndSettle();

    expect(find.text('DAEMON TOR EMBUTIDO (SEM ORBOT)'), findsOneWidget);
    expect(find.text('MALHA BLUETOOTH OFFLINE (MODO BRIAR BTP)'), findsOneWidget);
    expect(find.byKey(const Key('bluetooth_mesh_switch')), findsOneWidget);

    // Alterna o switch da malha Bluetooth
    await tester.dragUntilVisible(
      find.byKey(const Key('bluetooth_mesh_switch')),
      find.byType(ListView),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bluetooth_mesh_switch')));
    await tester.pumpAndSettle();
    expect(nixState.isBluetoothMeshEnabled, isTrue);

    // 2. Navega para a aba de Sobrevivência & Privacidade
    nixState.selectSettingsCategory(SettingsCategory.survival);
    await tester.pumpAndSettle();

    expect(find.text('BOTÃO DE PÂNICO & APAGAMENTO ANTI-FORENSE'), findsOneWidget);

    // Arrasta até o botão de pânico ficar visível na ListView
    await tester.dragUntilVisible(
      find.byKey(const Key('panic_wipe_button')),
      find.byType(ListView),
      const Offset(0, -150),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panic_wipe_button')), findsOneWidget);

    // Clica no botão de pânico para abrir o diálogo de confirmação
    await tester.tap(find.byKey(const Key('panic_wipe_button')));
    await tester.pumpAndSettle();

    expect(find.text('CONFIRMAR DESTRUIÇÃO TOTAL'), findsOneWidget);
    expect(find.text('SIM, DESTRUIR TUDO'), findsOneWidget);

    // Cancela o diálogo
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('CONFIRMAR DESTRUIÇÃO TOTAL'), findsNothing);
  });
}
