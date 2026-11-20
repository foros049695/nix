import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/security/file_picker_adapter.dart';
import 'package:nix_client/features/profile/card_id_widget.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Card ID cabe em 320 dp com nome longo e fonte ampliada', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 660);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = NixState();
    addTearDown(state.dispose);
    state.updateProfile(displayName: 'Pessoa com um pseudônimo longo');
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const Scaffold(body: CardIdWidget()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('card_id_avatar_edit_button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Seletor fecha com teclado aberto sem descartar controller cedo',
      (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 580));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () =>
              CrossPlatformFilePickerAdapter.showPortableFileChooserDialog(
                  context),
          child: const Text('Abrir seletor'),
        );
      }))),
    );
    final input = find.byKey(const Key('portable_file_picker_path_input'));
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Abrir seletor'));
      await tester.pumpAndSettle();
      await tester.enterText(input, '/arquivo-inexistente.png');
      await tester
          .tap(find.byKey(const Key('portable_file_picker_confirm_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
