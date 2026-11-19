import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nix_client/main.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_client/features/onboarding/sovereign_onboarding_model.dart';
import 'package:nix_client/features/onboarding/sovereign_onboarding_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Experiência Real de Primeiro Acesso, Onboarding Soberano & Mensageiro Limpo (Seções 2, 3, 4, 5, 6)', () {
    late Directory tempDir;
    late String statePersistencePath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nix_onboarding_e2e_test_');
      statePersistencePath = '${tempDir.path}/onboarding_state.json';
      await OnboardingStateSnapshot.delete();
    });

    tearDown(() async {
      await OnboardingStateSnapshot.delete();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('Instalação limpa inicia no Onboarding Soberano sem dados mockados e comuta para o Mensageiro Real', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Inicia em modo produção limpo (sem MockData)
      final nixState = NixState(loadMockData: false);

      expect(nixState.isOnboarded, isFalse);
      expect(nixState.directMessages.length, equals(1));
      expect(nixState.directMessages.first.isSavedMessages, isTrue);
      expect(nixState.directMessages.first.peerName, equals('Mensagens Salvas'));
      expect(nixState.contactRequests, isEmpty);

      await tester.pumpWidget(
        ChangeNotifierProvider<NixState>.value(
          value: nixState,
          child: const NixApp(skipSplash: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // 1. ETAPA WELCOME: Portão de Onboarding Soberano exibido imediatamente
      expect(find.byType(SovereignOnboardingFlow), findsOneWidget);
      expect(find.text('PROJETO NIX · ONBOARDING SOBERANO'), findsOneWidget);
      expect(find.text('Bem-vindo ao Projeto Nix'), findsOneWidget);
      expect(find.text('ETAPA 1 DE 9'), findsOneWidget);

      // 2. ETAPA TOR_CONSENT
      final nextBtn = find.byKey(const Key('onboarding_next_button'));
      await tester.tap(nextBtn);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Consentimento da Rede Tor (Fail-Closed)'), findsOneWidget);
      expect(find.text('ETAPA 2 DE 9'), findsOneWidget);

      // Consentimento obrigatório
      final checkboxFinder = find.byType(Checkbox);
      await tester.tap(checkboxFinder);
      await tester.pump(const Duration(milliseconds: 100));

      // 3. Conclui Onboarding e comuta para estado READY / PRODUÇÃO REAL
      await nixState.completeOnboarding(
        displayName: 'Cypherpunk 2026',
        avatarStyle: 'sentinel',
      );
      await tester.pump(const Duration(milliseconds: 200));

      // O onboarding desapareceu e o mensageiro operacional limpo foi aberto
      expect(find.byType(SovereignOnboardingFlow), findsNothing);
      expect(nixState.isOnboarded, isTrue);
      expect(find.text('CONVERSAS & MENSAGENS SALVAS'), findsOneWidget);
      expect(find.text('Mensagens Salvas'), findsOneWidget);

      // 4. Adiciona Contato Real por Card ID / Chave Pública
      expect(find.byKey(const Key('add_contact_sidebar_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('add_contact_sidebar_button')));
      await tester.pumpAndSettle();

      expect(find.text('Adicionar Contato Soberano'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('add_contact_id_field')), 'NIX-4B82-E119-9A00-7F22');
      await tester.enterText(find.byKey(const Key('add_contact_name_field')), 'Alice Soberana');
      await tester.tap(find.byKey(const Key('add_contact_confirm_button')));
      await tester.pumpAndSettle();

      // Contato adicionado e selecionado para chat
      expect(nixState.directMessages.length, equals(2));
      expect(nixState.selectedDm?.peerName, equals('Alice Soberana'));
      expect(find.text('Alice Soberana'), findsAtLeastNWidgets(1));

      // 5. Envia mensagem soberana cifrada
      nixState.sendDirectMessage('Olá Alice, chave E2E estabelecida via Tor Onion v3!');
      await tester.pumpAndSettle();

      expect(nixState.selectedDm?.messages.length, equals(2));
      expect(find.text('Olá Alice, chave E2E estabelecida via Tor Onion v3!'), findsAtLeastNWidgets(1));
    });

    test('OnboardingStateSnapshot persiste e restaura estado transacional sem vazar a Seed A', () async {
      const snapshot = OnboardingStateSnapshot(
        currentStep: OnboardingStep.publicId,
        torConsentAccepted: true,
        torBootstrapped: true,
        torVerified: true,
        identityGenerated: true,
        backupConfirmed: true,
        publicIdDerived: true,
        displayName: 'Soberano Teste',
        avatarStyle: 'crypto',
        publicId: 'NIX-7E3A-9F01-C45B-289D',
      );

      await OnboardingStateSnapshot.save(snapshot, customPath: statePersistencePath);

      final loaded = await OnboardingStateSnapshot.load(customPath: statePersistencePath);
      expect(loaded.currentStep, equals(OnboardingStep.publicId));
      expect(loaded.torConsentAccepted, isTrue);
      expect(loaded.torBootstrapped, isTrue);
      expect(loaded.backupConfirmed, isTrue);
      expect(loaded.displayName, equals('Soberano Teste'));
      expect(loaded.avatarStyle, equals('crypto'));
      expect(loaded.publicId, equals('NIX-7E3A-9F01-C45B-289D'));

      // Invariante de privacidade: nenhuma chave privada ou seed em claro no JSON
      final rawContent = await File(statePersistencePath).readAsString();
      expect(rawContent.contains('seedWords'), isFalse);
      expect(rawContent.contains('passphrase'), isFalse);
      expect(rawContent.contains('mnemonic'), isFalse);
    });
  });
}
