import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/security/seed_recovery.dart';
import 'package:nix_client/features/onboarding/sovereign_onboarding_flow.dart';
import 'package:nix_client/features/onboarding/sovereign_onboarding_model.dart';
import 'package:nix_client/core/security/key_vault.dart';
import 'package:nix_client/core/security/os_key_storage.dart';
import 'package:nix_client/state/nix_state.dart';

class FailingKeyStorage extends InMemoryOsKeyStorage {
  @override
  Future<bool> storeSecret(String key, String value) async => false;
}

// Mantém o fluxo real, mas confina o banco e o cofre ao diretório do teste.
class IsolatedOnboardingState extends NixState {
  IsolatedOnboardingState(this.root)
      : super(
          loadMockData: false,
          keyVault: KeyVault(osKeyStorage: PassphraseOnlyKeyStorage()),
        );

  final Directory root;
  bool? requestedBinding;
  bool? initialized;

  @override
  Future<bool> initializeEncryptedDatabase({
    required String passphrase,
    String? customDbPath,
    String? customVaultPath,
    String? migration001Sql,
    String? migration002Sql,
    bool bindToOsKeyring = false,
    String? duressPassphrase,
    bool? requireEncryption,
  }) async {
    requestedBinding = bindToOsKeyring;
    initialized = await super.initializeEncryptedDatabase(
      passphrase: passphrase,
      customDbPath: '${root.path}/local.db',
      customVaultPath: '${root.path}/vault.json',
      bindToOsKeyring: bindToOsKeyring,
      duressPassphrase: duressPassphrase,
    );
    return initialized!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final storage in <OsKeyStorage>[
    PassphraseOnlyKeyStorage(),
    FailingKeyStorage(),
    InMemoryOsKeyStorage(),
  ]) {
    test('bootstrap respeita vínculo solicitado: ${storage.runtimeType}',
        () async {
      final root = await Directory.systemTemp.createTemp('nix_keyring_probe_');
      final vault = KeyVault(osKeyStorage: storage);
      final state = NixState(loadMockData: false, keyVault: vault);
      addTearDown(() async {
        await state.localDatabase?.close();
        state.dispose();
        await root.delete(recursive: true);
      });
      final succeeds = storage.runtimeType == InMemoryOsKeyStorage;
      final path = '${root.path}/vault.json';
      final result = await state.initializeEncryptedDatabase(
        passphrase: 'senha-sintetica-probe',
        customDbPath: '${root.path}/local.db',
        customVaultPath: path,
        bindToOsKeyring: true,
      );
      expect(result, succeeds);
      expect(await vault.isInitialized(customPath: path), succeeds);
      expect(await File(path).exists(), succeeds);
      expect(vault.isUnlocked, succeeds);
      expect(state.isDatabaseReady, succeeds);
      if (!succeeds) {
        expect(state.lastDatabaseInitError, contains('keyring'));
        expect(await File('${root.path}/local.db').exists(), isFalse);
      }
    });
  }
  for (final restore in [false, true]) {
    testWidgets(
        restore
            ? 'restauração com senha gerada sem keyring falha e desfaz cofre'
            : 'senha digitada sem keyring passa com opção padrão marcada',
        (tester) async {
      // O Flutter 3.50 reporta este aviso visual preexistente na etapa de identidade.
      // O probe verifica a decisão de vínculo; todos os demais erros continuam fatais.
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().startsWith(
            'ListTile background color or ink splashes may be invisible.')) {
          return;
        }
        previousOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousOnError);
      final root = Directory.systemTemp.createTempSync('nix_onboarding_probe_');
      final state = IsolatedOnboardingState(root);
      addTearDown(() => tester.runAsync(() async {
            await state.localDatabase?.close();
            state.dispose();
            await root.delete(recursive: true);
          }));
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final snapshotPath = '${root.path}/onboarding.json';
      await OnboardingStateSnapshot.save(
        OnboardingStateSnapshot(
          currentStep: restore
              ? OnboardingStep.welcome
              : OnboardingStep.identityGeneration,
        ),
        customPath: snapshotPath,
      );
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(0.8)),
          child: child!,
        ),
        home: Scaffold(
          body: SovereignOnboardingFlow(
            nixState: state,
            onComplete: () {},
            customPersistencePath: snapshotPath,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      if (restore) {
        final restoreButton =
            find.text('Já possuo Seed A (Recuperar Conta de Backup)');
        await tester.ensureVisible(restoreButton);
        await tester.pumpAndSettle();
        await tester.tap(restoreButton);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).first,
          SeedRecoveryManager.generateMnemonic().join(' '),
        );
      } else {
        expect(
            tester
                .widget<CheckboxListTile>(find.byType(CheckboxListTile))
                .value,
            isTrue);
        await tester.enterText(
            find.byType(TextField).first, 'senha-do-usuario');
      }
      // Executa o callback real fora do relógio simulado: Argon2id e SQLite usam IO.
      // ElevatedButton.icon usa uma subclasse privada em SDKs mais antigos.
      final buttonFinder = find.ancestor(
        of: find.text(
          restore ? 'Restaurar Conta' : 'Gerar Identidade Soberana Segura',
        ),
        matching: find.byWidgetPredicate((widget) => widget is ElevatedButton),
      );
      expect(buttonFinder, findsOneWidget);
      final button = tester.widget<ElevatedButton>(buttonFinder);
      await tester.runAsync(button.onPressed! as Future<void> Function());
      await tester.pumpAndSettle();

      expect(state.requestedBinding, restore);
      expect(state.initialized, !restore);
      expect(File('${root.path}/vault.json').existsSync(), !restore);
      expect(state.keyVault.isUnlocked, !restore);
      if (restore) {
        expect(state.lastDatabaseInitError, contains('keyring'));
        expect(File('${root.path}/local.db').existsSync(), isFalse);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
