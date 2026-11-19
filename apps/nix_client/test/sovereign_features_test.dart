import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_client/features/dialogs/sovereign_onboarding_dialog.dart';
import 'package:nix_client/features/settings/settings_center.dart';
import 'package:nix_client/core/models/user_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SovereignOnboardingDialog guia o usuário através do Tor, Seed no Papel e Card ID', (tester) async {
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

    // Etapa 0: Consentimento Tor
    expect(find.text('CONSENTIMENTO DA REDE TOR (FAIL-CLOSED)'), findsOneWidget);
    expect(find.byKey(const Key('tor_consent_checkbox_tile')), findsOneWidget);

    // Garante que o tile está visível e clica no consentimento
    await tester.ensureVisible(find.byKey(const Key('tor_consent_checkbox_tile')));
    await tester.tap(find.byKey(const Key('tor_consent_checkbox_tile')));
    await tester.pumpAndSettle();

    // Avança para o bootstrap Tor
    expect(find.byKey(const Key('accept_tor_and_continue_button')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('accept_tor_and_continue_button')));
    await tester.tap(find.byKey(const Key('accept_tor_and_continue_button')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Avança o tempo virtual para cobrir o bootstrap (300ms + 400ms) e transicionar para o Step 2
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    // Etapa 2: Exibição da Seed Soberana de 24 palavras
    expect(find.text('ANOTE SUA SEED PRIVADA NO PAPEL'), findsOneWidget);
    expect(find.byKey(const Key('seed_written_checkbox_tile')), findsOneWidget);

    // Marca confirmação de anotação no papel
    await tester.ensureVisible(find.byKey(const Key('seed_written_checkbox_tile')));
    await tester.tap(find.byKey(const Key('seed_written_checkbox_tile')));
    await tester.pumpAndSettle();

    // Avança para o Card ID Público
    expect(find.byKey(const Key('confirm_seed_written_button')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('confirm_seed_written_button')));
    await tester.tap(find.byKey(const Key('confirm_seed_written_button')));
    await tester.pumpAndSettle();

    // Etapa 3: Exibição da Chave Pública
    expect(find.text('SUA IDENTIDADE PÚBLICA (CARD ID)'), findsOneWidget);
    expect(find.byKey(const Key('finish_onboarding_button')), findsOneWidget);

    // Finaliza o onboarding
    await tester.ensureVisible(find.byKey(const Key('finish_onboarding_button')));
    await tester.tap(find.byKey(const Key('finish_onboarding_button')));
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
