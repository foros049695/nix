import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nix_client/main.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:nix_client/core/models/channel.dart';

void main() {
  testWidgets('NixApp initializes with tactical dark shell and spaces dock', (WidgetTester tester) async {
    // Definir tamanho de tela de desktop para o teste
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NixState(),
        child: const NixApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verifica se os canais do QG Nix foram renderizados
    expect(find.text('QG Nix'), findsOneWidget);
    expect(find.text('geral'), findsOneWidget);
    expect(find.text('desenvolvimento-core'), findsOneWidget);
  });

  test('NixState handles channel selection and messaging without bugs', () {
    final state = NixState();

    expect(state.currentChannel.name, 'geral');
    final initialCount = state.currentMessages.length;

    // Enviar mensagem
    state.sendMessage('Mensagem de teste automatizado');
    expect(state.currentMessages.length, initialCount + 1);
    expect(state.currentMessages.last.text, 'Mensagem de teste automatizado');
    expect(state.currentMessages.last.isMe, true);
  });

  test('NixState handles call joining and controls', () {
    final state = NixState();
    final callChannel = state.currentSpace.channels.firstWhere((c) => c.type == ChannelType.voice);

    // Entrar na call
    state.joinCall(callChannel);
    expect(state.callState.isConnected, true);
    expect(state.callState.activeChannelId, callChannel.id);
    expect(state.callState.isMuted, false);

    // Mudar mudo
    state.toggleMute();
    expect(state.callState.isMuted, true);

    // Sair da call
    state.leaveCall();
    expect(state.callState.isConnected, false);
  });

  test('NixState creates new channel topic cleanly', () {
    final state = NixState();
    final initialChannelsCount = state.currentSpace.channels.length;

    state.createChannel(
      name: 'sala-secreta-01',
      type: ChannelType.text,
      topic: 'Tópico exclusivo',
      category: '💬 TÓPICOS DE TEXTO',
    );

    expect(state.currentSpace.channels.length, initialChannelsCount + 1);
    expect(state.currentChannel.name, 'sala-secreta-01');
  });
}
