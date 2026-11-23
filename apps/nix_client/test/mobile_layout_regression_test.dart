import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/direct_message.dart';
import 'package:nix_client/core/models/pager_appearance.dart';
import 'package:nix_client/core/models/user_settings.dart';
import 'package:nix_client/core/security/file_picker_adapter.dart';
import 'package:nix_client/core/security/local_image_helper.dart';
import 'package:nix_client/features/chat/chat_input_bar.dart';
import 'package:nix_client/features/dialogs/nix_symbol_picker.dart';
import 'package:nix_client/features/navigation/app_shell.dart';
import 'package:nix_client/features/profile/qr_code_painter.dart';
import 'package:nix_client/core/theme/nix_palette.dart';
import 'package:nix_client/features/profile/pager_profile.dart';
import 'package:nix_client/features/profile/pager_housing.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
      'Cores do Pager são independentes, persistentes e acessíveis no menu',
      (tester) async {
    final state = NixState();
    addTearDown(state.dispose);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: Scaffold(body: PagerProfile())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menu do Pager'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cores do Pager'));
    await tester.pumpAndSettle();

    for (final color in ['Jade', 'Lima']) {
      final option = find.widgetWithText(ChoiceChip, color);
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Concluir'));
    await tester.pumpAndSettle();

    final housing = tester.widget<PagerHousing>(find.byType(PagerHousing));
    expect(housing.caseColor, PagerCaseColor.jade);
    expect(housing.lcdColor, PagerLcdColor.lime);
    final restored = UserSettings.fromJson(state.settings.toJson());
    expect(restored.pagerCaseColor, housing.caseColor);
    expect(restored.pagerLcdColor, housing.lcdColor);
    expect(UserSettings.fromJson({}).pagerLcdColor, PagerLcdColor.cyan);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Atalhos do Pager aceitam setas, toque e arraste sem trocar de página',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = NixState(loadMockData: true);
    addTearDown(state.dispose);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: Scaffold(body: PagerProfile())),
    ));
    await tester.pumpAndSettle();

    final rail = find.byKey(const Key('pager_shortcuts'));
    final scroll = tester.widget<ListView>(rail).controller!;
    await tester.tap(find.byTooltip('Mais atalhos'));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    await tester.drag(rail, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(find.text('Identidade'), findsOneWidget);

    final friend = state.directMessages.firstWhere((dm) => !dm.isSavedMessages);
    await tester.tap(find.byTooltip('Amigo · ${friend.peerName}'));
    await tester.pumpAndSettle();
    expect(state.selectedDm?.id, friend.id);
  });

  testWidgets(
      'Configurações, participantes e carteira usam a largura do celular',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 690));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = NixState(loadMockData: true);
    addTearDown(state.dispose);
    final space = state.spaces.firstWhere((space) => !space.isDirectMessages);
    state.selectSpace(space);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: AppShell()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message_header_bar')), findsNothing);

    Future<void> channelAction(String action) async {
      await tester.tap(find.byTooltip('Opções do canal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
    }

    await channelAction('Configurações do canal');
    final channelSections =
        find.byKey(const Key('mobile_channel_settings_categories'));
    expect(tester.getSize(channelSections).width, 320);
    await tester.tap(find.text('Identidade e acesso'));
    await tester.pumpAndSettle();
    expect(channelSections, findsNothing);
    expect(find.text('Nome do Canal'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(channelSections, findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await channelAction('Participantes');
    expect(tester.getSize(find.byKey(const Key('members_panel'))).width, 320);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await channelAction('Informações da conversa');
    expect(
        tester.getSize(find.byKey(const Key('conversation_info_panel'))).width,
        320);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    state.openProfileOverlay(startInSettings: true);
    await tester.pumpAndSettle();
    final appSections = find.byKey(const Key('mobile_settings_categories'));
    expect(tester.getSize(appSections).width, 320);
    await tester.tap(find.text('Chats'));
    await tester.pumpAndSettle();
    expect(appSections, findsNothing);
    expect(find.byKey(const ValueKey('mobile_settings_chats')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(appSections, findsOneWidget);

    state.closeProfileOverlay();
    state.selectHomeSubTab(HomeSubTab.transactions);
    await tester.pumpAndSettle();
    expect(find.text('Carteira externa desconectada'), findsOneWidget);
    expect(state.activeArea, NixActiveArea.moneroP2p);
    await tester.tap(find.widgetWithText(Tab, 'Mercado Cripto'));
    await tester.pumpAndSettle();
    expect(find.text('Carteira externa desconectada'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pager cabe em 320 dp com nome longo e fonte ampliada', (
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
          home: const Scaffold(body: PagerProfile()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('card_id_avatar_edit_button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Pager mostra QR, estado real e permite contemplação só com fundo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = NixState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: PagerProfile())),
      ),
    );
    await tester.pumpAndSettle();
    final shell = tester
        .widget<DecoratedBox>(find.byKey(const Key('pager_rendered_shell')));
    final texture =
        (shell.decoration as BoxDecoration).image!.image as AssetImage;
    expect(texture.assetName, 'assets/images/pager_shell.webp');
    final qr = tester.widget<NixQrCodeWidget>(find.byType(NixQrCodeWidget));
    expect(qr.data, state.userProfile.qrPublicPayload);
    state.updateSettings(state.settings.copyWith(allowPublicIdSharing: false));
    await tester.pumpAndSettle();
    expect(find.byType(NixQrCodeWidget), findsNothing);

    await tester.tap(find.byTooltip('Próxima tela'));
    await tester.pumpAndSettle();
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Sem rede'), findsOneWidget);
    expect(find.text('Cofre local: bloqueado'), findsOneWidget);
    final contemplation =
        find.widgetWithText(OutlinedButton, 'Abrir contemplação');
    expect(contemplation.hitTestable(), findsOneWidget);
    expect(
      tester.getBottomRight(contemplation).dy,
      lessThan(tester.getBottomRight(find.byKey(const Key('pager_screen'))).dy),
    );
    await tester.drag(
        find.byKey(const Key('pager_screen')), const Offset(-380, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pager_contemplation_avatar')), findsOneWidget);

    await tester.tap(find.byTooltip('Menu do Pager'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personalizar contemplação'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mostrar foto de perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(state.settings.hidePagerAvatar, isTrue);
    expect(find.byKey(const Key('pager_contemplation_avatar')), findsNothing);
  });

  test('Fundo do Pager fica local e pode ser substituído ou removido',
      () async {
    final state = NixState();
    addTearDown(state.dispose);
    final output = LocalImageHelper.pagerWallpaper;
    addTearDown(() async {
      if (await output.exists()) await output.delete();
    });
    final source = File('assets/images/pager_assistant.png');
    expect(await state.updatePagerWallpaper(source.absolute.path), isTrue);
    expect(await output.length(), greaterThan(0));
    expect(state.pagerWallpaperRevision, 1);
    expect(await state.updatePagerWallpaper(source.absolute.path), isTrue);
    expect(state.pagerWallpaperRevision, 2);
    expect(await state.updatePagerWallpaper(null), isTrue);
    expect(await output.exists(), isFalse);
    expect(state.pagerWallpaperRevision, 3);
  });

  testWidgets('Cancelar seletor do sistema não abre outro diálogo',
      (tester) async {
    final state = NixState();
    addTearDown(state.dispose);
    final original = LocalImageHelper.filePickerAdapter;
    final picker = ProgrammableFilePickerAdapter();
    addTearDown(() => LocalImageHelper.filePickerAdapter = original);
    LocalImageHelper.filePickerAdapter = picker;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(
        home: Scaffold(body: ChatInputBar(channelName: 'geral')),
      ),
    ));
    await tester.tap(find.byKey(const Key('chat_attach_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arquivos'));
    await tester.pumpAndSettle();
    expect(picker.pickAttachmentsCalls, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Fotos usa filtro de imagens, mostra prévia e permite remover', (tester) async {
    final state = NixState();
    addTearDown(state.dispose);
    final original = LocalImageHelper.filePickerAdapter;
    addTearDown(() => LocalImageHelper.filePickerAdapter = original);
    final photo = File('assets/images/nix_logo_128.png').absolute.path;
    LocalImageHelper.filePickerAdapter = ProgrammableFilePickerAdapter(
      nextAttachments: [photo, 'segredo.pdf'],
    );
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: Scaffold(body: ChatInputBar(channelName: 'geral'))),
    ));
    await tester.tap(find.byKey(const Key('chat_attach_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fotos'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('attachment_preview_$photo')), findsOneWidget);
    expect(find.text('segredo.pdf'), findsNothing);
    await tester.tap(find.byKey(const Key('remove_attachment_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('attachment_preview_$photo')), findsNothing);
  });

  testWidgets('Seletor oferece ícones e emojis', (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () async =>
              selected = await showNixSymbolPicker(context, 'i:tag'),
          child: const Text('Selecionar símbolo'),
        );
      })),
    ));
    await tester.tap(find.text('Selecionar símbolo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rádio'));
    await tester.pumpAndSettle();
    expect(selected, 'i:radio');

    await tester.tap(find.text('Selecionar símbolo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emojis'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Raposa'));
    await tester.pumpAndSettle();
    expect(selected, '🦊');
  });

  test('Cores de destaque mantêm contraste nos temas e como fundo de botão',
      () {
    for (final scheme in [
      NixSurfaceScheme.darkYellow,
      NixSurfaceScheme.lightYellow,
      NixSurfaceScheme.amoled,
    ]) {
      for (final palette in NixPalette.standardPalettes) {
        expect(
            NixPalette.contrastRatio(
                palette.readableAccentOn(scheme), scheme.surfaceElevatedHigh),
            greaterThanOrEqualTo(4.5));
        expect(
            NixPalette.contrastRatio(
                palette.onAccentColor, palette.primaryAccent),
            greaterThanOrEqualTo(4.5));
      }
    }
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
