import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/direct_message.dart';
import 'package:nix_client/core/models/monero_order.dart';
import 'package:nix_client/core/models/pager_appearance.dart';
import 'package:nix_client/core/models/space.dart';
import 'package:nix_client/core/theme/nix_palette.dart';
import 'package:nix_client/features/chat/message_timeline.dart';
import 'package:nix_client/features/dialogs/channel_settings_dialog.dart';
import 'package:nix_client/features/profile/pager_profile.dart';
import 'package:nix_client/features/navigation/app_shell.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Pager fecha pelo X e a seta das configurações volta ao menu',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = NixState(loadMockData: true);
    addTearDown(state.dispose);
    state.selectHomeSubTab(HomeSubTab.cardId);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: AppShell()),
    ));
    await tester.pumpAndSettle();
    final pagerViewport = find
        .descendant(
          of: find.byType(PagerProfile),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    expect(
        tester.getRect(pagerViewport).bottom,
        greaterThan(tester
            .getRect(find.byKey(const Key('floating_workspace_tabs')))
            .center
            .dy));
    await tester.tap(find.byTooltip('Abrir Pager e perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('close_pager_overlay')));
    await tester.pumpAndSettle();
    expect(state.isProfileOverlayOpen, isFalse);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mutar microfone'));
    await tester.pumpAndSettle();
    final muted = find.byTooltip('Desmutar microfone');
    expect(
        find.descendant(
            of: muted, matching: find.byIcon(Icons.mic_off_rounded)),
        findsOneWidget);
    await tester.tap(muted);
    await tester.pumpAndSettle();
    expect(state.calls.isMuted, isFalse);

    await tester.tap(find.byTooltip('Configurações'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(state.isProfileOverlayOpen, isFalse);
    expect(find.byTooltip('Configurações'), findsOneWidget);
  });

  testWidgets(
      'a última mensagem volta ao campo visível depois de enviar pelo Enter',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = NixState(loadMockData: true);
    addTearDown(state.dispose);
    final thread = state.directMessages.firstWhere((dm) => dm.isSavedMessages);
    state.selectDirectMessage(thread);
    for (var i = 0; i < 28; i++) {
      await state.sendDirectMessage('Mensagem anterior $i');
    }
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: AppShell()),
    ));
    await tester.pumpAndSettle();
    final timeline = find.byType(MessageTimeline);
    final scrollable =
        find.descendant(of: timeline, matching: find.byType(Scrollable)).first;
    final scroll = tester.state<ScrollableState>(scrollable).position;
    scroll.jumpTo(400);
    await tester.pumpAndSettle();
    expect(scroll.pixels, greaterThan(100));
    await tester.enterText(
        find.byKey(const Key('chat_message_input')), 'Nova mensagem enviada');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(scroll.pixels, closeTo(scroll.minScrollExtent, .1));
    expect(find.text('Nova mensagem enviada'), findsOneWidget);
  });

  testWidgets(
      'mudar visibilidade exige confirmação antes de alterar o catálogo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = NixState(loadMockData: true);
    addTearDown(state.dispose);
    state.createSpace(name: 'Confirmação', description: '', emoji: 'C');
    final channel = state.currentChannel;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () =>
                          ChannelSettingsDialog.show(context, channel),
                      child: const Text('Abrir configurações do canal'),
                    ))),
      ),
    ));
    await tester.tap(find.text('Abrir configurações do canal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Identidade e acesso'));
    await tester.pumpAndSettle();
    final toggle = find.text('Canal Público na Rede Nix');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    final save = find.text('Salvar Alterações');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Confirmar canal público'), findsOneWidget);
    expect(state.currentChannel.permissions.isPublic, isFalse);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(state.currentChannel.permissions.isPublic, isFalse);
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(state.currentChannel.permissions.isPublic, isTrue);
    expect(
        state.filteredDiscoverableSpaces
            .any((space) => space.id == channel.spaceId),
        isTrue);
  });

  test('preferências e privacidade sobrevivem à reabertura do cofre', () async {
    final dir = await Directory.systemTemp.createTemp('nix-vault-reopen-');
    addTearDown(() => dir.delete(recursive: true));
    final dbPath = '${dir.path}/nix_local_v4.db';
    final vaultPath = '${dir.path}/vault_bootstrap.json';
    const passphrase = 'preferencias-locais-teste-isolado';
    final state = NixState(loadMockData: false);
    addTearDown(state.dispose);
    expect(
        await state.initializeEncryptedDatabase(
          passphrase: passphrase,
          customDbPath: dbPath,
          customVaultPath: vaultPath,
        ),
        isTrue);
    final identity = await NixIdentity.generate();
    await state.persistPrimaryIdentity(
        identity: identity, displayName: 'Nome local');
    state.updateSettings(state.settings.copyWith(
      themeMode: NixThemeMode.lightYellow,
      pagerCaseColor: PagerCaseColor.jade,
      messageNotifications: false,
      showMessagePreview: true,
      enterToSend: false,
      inputVolume: .32,
      microphoneMuted: true,
      autoReconnect: false,
    ));
    state.blockNewUser('NIX-EXAMPLE-BLOCKED');
    state.toggleConnector('conn_jellyfin');
    state.updateProfile(
        avatarStyle: 'local_file',
        customAvatarPath: '${dir.path}/foto.gif',
        avatarCropScale: 1.8,
        avatarCropOffsetX: .25,
        currentActivity: 'Faixa local');
    state.createSpace(
        name: 'Grupo privado', description: 'Privado', emoji: 'G');
    final channel = state.currentChannel;
    expect(state.filteredDiscoverableSpaces, isEmpty);
    expect(
        state.joinDiscoverableSpace(const Space(
          id: 'false-public',
          name: 'Sem permissão',
          initials: 'SP',
          isPublic: true,
          description: '',
          channels: [],
        )),
        isFalse);
    expect(
        await state.updateChannelSettings(channel.copyWith(
          permissions: channel.permissions
              .copyWith(isPublic: true, requireApproval: true),
        )),
        isTrue);
    final formerlyPublic = state.filteredDiscoverableSpaces.single;
    expect(formerlyPublic.channels.single.permissions.requireApproval, isTrue);
    expect(await state.updateChannelSettings(channel), isTrue);
    expect(state.joinDiscoverableSpace(formerlyPublic), isFalse);
    expect(
        await state.sendSovereignMessage(
            conversationId: channel.id, text: 'Mensagem privada'),
        isFalse);
    final article = await state.publishCanonicalArticle(
        channelId: channel.id,
        title: 'Rascunho privado',
        rawContent: '<p>Dados locais.</p>');
    expect(
        (await state.archiveRepository
            .getObject(article.cidHash))?['visibility'],
        'restricted');
    expect(
        await state.archiveRepository.listObjects(publicOnly: true), isEmpty);

    final firstOrder = await state.createAndSignMoneroOrder(
        side: MoneroP2pSide.buy,
        fiatCurrency: 'BRL',
        pricePerXmr: 400,
        minFiatLimit: 10,
        maxFiatLimit: 50,
        paymentMethod: 'XMR',
        notes: '');
    final secondOrder = await state.createAndSignMoneroOrder(
        side: MoneroP2pSide.buy,
        fiatCurrency: 'BRL',
        pricePerXmr: 400,
        minFiatLimit: 10,
        maxFiatLimit: 50,
        paymentMethod: 'XMR',
        notes: '');
    expect(firstOrder.traderPublicId, isNot(secondOrder.traderPublicId));
    expect(firstOrder.traderName, startsWith('Parte-'));
    expect(firstOrder.traderName, isNot(contains('Nome local')));
    await state.flushPreferences();
    await state.localDatabase!.close();

    final restored = NixState(loadMockData: false);
    addTearDown(restored.dispose);
    await restored.unlockWithPassphrase(passphrase,
        customDbPath: dbPath, customVaultPath: vaultPath);
    expect(restored.settings.themeMode, NixThemeMode.lightYellow);
    expect(restored.settings.pagerCaseColor, PagerCaseColor.jade);
    expect(restored.settings.messageNotifications, isFalse);
    expect(restored.settings.showMessagePreview, isTrue);
    expect(restored.settings.enterToSend, isFalse);
    expect(restored.settings.inputVolume, .32);
    expect(restored.settings.autoReconnect, isFalse);
    expect(restored.calls.isMuted, isTrue);
    expect(restored.settings.blockedUserIds, contains('NIX-EXAMPLE-BLOCKED'));
    expect(
        restored.settings.connectors
            .firstWhere((it) => it.id == 'conn_jellyfin')
            .isEnabled,
        isTrue);
    expect(restored.userProfile.customAvatarPath, '${dir.path}/foto.gif');
    expect(restored.userProfile.avatarCropScale, 1.8);
    expect(restored.userProfile.avatarCropOffsetX, .25);
    expect(restored.userProfile.currentActivity, 'Faixa local');
    expect(
        restored.spaces
            .expand((space) => space.channels)
            .firstWhere((entry) => entry.id == channel.id)
            .permissions
            .isPublic,
        isFalse);
    expect(restored.filteredDiscoverableSpaces, isEmpty);
  });
}
