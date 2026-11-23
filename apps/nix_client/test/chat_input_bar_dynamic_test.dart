import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/features/chat/chat_input_bar.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('ChatInputBar transiciona dinamicamente entre microfone, envio e edição', (tester) async {
    final state = NixState();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<NixState>.value(
            value: state,
            child: const ChatInputBar(channelName: 'geral'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Campo vazio: microfone é o botão principal, sem botão de envio concorrente
    expect(find.byKey(const Key('voice_record_button')), findsOneWidget);
    expect(find.byKey(const Key('chat_send_button')), findsNothing);

    // 2. Campo com texto: substitui automaticamente por seta de envio
    await tester.enterText(find.byKey(const Key('chat_message_input')), 'Olá Nix');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat_send_button')), findsOneWidget);
    expect(find.byKey(const Key('voice_record_button')), findsNothing);

    // 3. Texto apagado: restaura microfone
    await tester.enterText(find.byKey(const Key('chat_message_input')), '');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voice_record_button')), findsOneWidget);
    expect(find.byKey(const Key('chat_send_button')), findsNothing);
  });
}
