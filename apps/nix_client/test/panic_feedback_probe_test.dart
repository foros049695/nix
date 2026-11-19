import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/user_settings.dart';
import 'package:nix_client/core/security/anti_forensic_shredder.dart';
import 'package:nix_client/features/settings/settings_center.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:provider/provider.dart';

class ReportingState extends NixState {
  ReportingState(this.errors);
  final Map<String, String> errors;

  @override
  Future<ShredReport> panicWipeAllData({String? customBaseDir}) async =>
      ShredReport(
        filesOverwritten: 3,
        totalBytesWiped: 1024,
        passesPerFile: 3,
        memoryWiped: true,
        shreddedPaths: const [],
        errors: errors,
      );
}

void main() {
  for (final failed in [false, true]) {
    testWidgets('resultado do pânico com erros=$failed', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state =
          ReportingState(failed ? {'alvo1': 'erro', 'alvo2': 'erro'} : {});
      addTearDown(state.dispose);
      state.selectSettingsCategory(SettingsCategory.survival);
      await tester.pumpWidget(ChangeNotifierProvider<NixState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: SettingsCenter())),
      ));
      final button = find.byKey(const Key('panic_wipe_button'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('SIM, DESTRUIR TUDO'));
      await tester.pumpAndSettle();
      expect(
          find.textContaining(failed
              ? 'Apagamento anti-forense incompleto: 2 alvos com falha'
              : 'Apagamento anti-forense concluído: 3 arquivos'),
          findsOneWidget);
      if (failed) {
        expect(find.textContaining('Apagamento anti-forense concluído'),
            findsNothing);
      }
    });
  }
}
