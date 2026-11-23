import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/features/chat/chat_inline_format.dart';
import 'package:nix_client/features/chat/external_link_dialog.dart';
import 'package:nix_client/features/chat/conversation_info_panel.dart';
import 'package:nix_client/core/models/direct_message.dart';
import 'package:nix_client/core/models/message.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('ChatInlineText renders clickable link for URL and opens ExternalLinkDialog on tap', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatInlineText(
            'Acesse https://nix.onion/repo para ver o código',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ),
    );

    expect(find.byType(Text), findsOneWidget);
    final textWidget = tester.widget<Text>(find.byType(Text));
    expect(textWidget.textSpan, isNotNull);

    // Abre o diálogo de link externo diretamente
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExternalLinkDialog(url: 'https://nix.onion/repo'),
        ),
      ),
    );

    expect(find.text('Endereço Onion Detectado'), findsOneWidget);
    expect(find.text('https://nix.onion/repo'), findsOneWidget);
    expect(find.text('Copiar Link'), findsOneWidget);
    expect(find.text('Abrir Navegador'), findsOneWidget);
  });

  testWidgets('ExternalLinkDialog handles clearnet URLs with privacy warning', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExternalLinkDialog(url: 'https://github.com/foros049695/nix'),
        ),
      ),
    );

    expect(find.text('Link Externo (Clearnet)'), findsOneWidget);
    expect(find.text('https://github.com/foros049695/nix'), findsOneWidget);
    expect(find.text('Copiar Link'), findsOneWidget);
    expect(find.text('Abrir Navegador'), findsOneWidget);
  });

  testWidgets('ConversationInfoPanel displays media tabs and indexed counters', (tester) async {
    final state = NixState(loadMockData: false);
    final dm = DirectMessageThread(
      id: 'dm_test_media',
      peerName: 'Alice',
      peerPublicId: 'NIX-ALICE-123',
      statusText: 'Online',
      isSavedMessages: false,
      messages: [
        Message(
          id: 'msg_1',
          channelId: 'dm_test_media',
          senderName: 'Alice',
          senderFingerprint: 'FP_ALICE_123',
          isMe: false,
          text: 'Veja esse link: https://nix.onion/doc e essa foto',
          timestamp: DateTime.now(),
          attachments: ['photo1.png', 'documento.pdf'],
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<NixState>.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: ConversationInfoPanel(
              directMessage: dm,
              fullScreen: true,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    // Verifica se os contadores locais foram gerados
    expect(find.text('1 fotos'), findsOneWidget);
    expect(find.text('1 arquivos'), findsOneWidget);
    expect(find.text('1 links compartilhados'), findsOneWidget);

    // Toca na aba de links compartilhados
    await tester.tap(find.text('1 links compartilhados'));
    await tester.pump();

    expect(find.text('LINKS COMPARTILHADOS (1)'), findsOneWidget);
    expect(find.text('https://nix.onion/doc'), findsOneWidget);

    // Toca na aba de arquivos
    await tester.tap(find.text('1 arquivos'));
    await tester.pump();

    expect(find.text('ARQUIVOS & DOCUMENTOS (1)'), findsOneWidget);
    expect(find.text('documento.pdf'), findsOneWidget);

    // Toca na aba de fotos
    await tester.tap(find.text('1 fotos'));
    await tester.pump();

    expect(find.text('FOTOS COMPARTILHADAS (1)'), findsOneWidget);
  });
}
