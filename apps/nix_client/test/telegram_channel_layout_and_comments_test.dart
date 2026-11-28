import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/channel.dart';
import 'package:nix_client/core/models/message.dart';
import 'package:nix_client/features/chat/channel_comments_sheet.dart';
import 'package:nix_client/features/chat/message_bubble.dart';
import 'package:nix_client/features/chat/message_header.dart';
import 'package:nix_client/features/dialogs/create_space_dialog.dart';
import 'package:nix_client/features/dialogs/channel_settings_dialog.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Projeto Nix — Redesign de Canais, Cabeçalho e Comentários (Estilo Telegram)', () {
    testWidgets('CreateSpaceDialog exibe opções limpas sem a palavra "soberano"', (tester) async {
      final state = NixState(loadMockData: false);
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<NixState>.value(
            value: state,
            child: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ChangeNotifierProvider<NixState>.value(
                      value: state,
                      child: const CreateSpaceDialog(),
                    ),
                  ),
                  child: const Text('Abrir Diálogo'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Diálogo'));
      await tester.pumpAndSettle();

      // Verifica que o dropdown exibe os nomes corretos
      expect(find.text('Grupo sem tópicos'), findsOneWidget);
      expect(find.text('Grupo soberano'), findsNothing);
      expect(find.text('Grupo soberano com tópicos'), findsNothing);
      expect(find.text('Canal de transmissão'), findsNothing);

      // Abre o dropdown para verificar as opções
      await tester.tap(find.text('Grupo sem tópicos'));
      await tester.pumpAndSettle();

      expect(find.text('Grupo com tópicos'), findsOneWidget);
      expect(find.text('Canal'), findsOneWidget);

      // Placeholder do campo de descrição
      expect(find.text('Descreva os objetivos deste espaço...'), findsOneWidget);
      expect(find.textContaining('soberano'), findsNothing);
    });

    test('Criação de canal utiliza o nome e descrição reais digitados pelo usuário', () {
      final state = NixState(loadMockData: false);
      state.createSpace(
        name: 'RHOBERLY - PROMOÇÕES',
        description: 'Melhores ofertas e cupons verificados da comunidade.',
        emoji: 'i:tag',
        isAnnouncementChannel: true,
      );

      final space = state.spaces.firstWhere((s) => s.name == 'RHOBERLY - PROMOÇÕES');
      final channel = space.channels.first;

      expect(channel.name, equals('RHOBERLY - PROMOÇÕES'));
      expect(channel.name, isNot(equals('comunicados')));
      expect(channel.topic, equals('Melhores ofertas e cupons verificados da comunidade.'));
      expect(channel.topic, isNot(equals('Canal oficial de transmissão e comunicados.')));
      expect(channel.type, equals(ChannelType.announcement));
      expect(channel.permissions.allowComments, isTrue);
    });

    testWidgets('MessageHeader exibe nome real, descrição real e avatar circular no lugar do megafone', (tester) async {
      final state = NixState(loadMockData: false);
      state.createSpace(
        name: 'RHOBERLY - PROMOÇÕES',
        description: 'Canal de ofertas e cupons',
        emoji: 'i:tag',
        isAnnouncementChannel: true,
      );

      final channel = state.currentChannel;

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<NixState>.value(
            value: state,
            child: Scaffold(
              body: MessageHeader(channel: channel),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Nome e descrição reais
      expect(find.text('RHOBERLY - PROMOÇÕES'), findsOneWidget);
      expect(find.text('Canal de ofertas e cupons'), findsOneWidget);
      expect(find.text('comunicados'), findsNothing);

      // Iniciais no avatar circular (RP)
      expect(find.text('RP'), findsOneWidget);
      // Não deve renderizar o ícone de megafone como leading
      expect(find.byIcon(Icons.campaign_outlined), findsNothing);
    });

    testWidgets('Postagem no canal posiciona anexos de mídia ACIMA do texto e exibe botão de comentários', (tester) async {
      final state = NixState(loadMockData: false);
      state.createSpace(
        name: 'RHOBERLY - PROMOÇÕES',
        description: 'Canal de ofertas',
        emoji: 'i:tag',
        isAnnouncementChannel: true,
      );

      final channel = state.currentChannel;
      final msg = Message(
        id: 'msg_post_promo_01',
        channelId: channel.id,
        senderName: 'RHOBERLY - PROMOÇÕES',
        senderFingerprint: state.securityContext.myFingerprint,
        isMe: true,
        text: '🔥 Fonte XPG Core Reactor II VF, 850W Gold\nValor: R\$ 440',
        timestamp: DateTime.now(),
        attachments: ['photo_xpg_supply.jpg'],
        isVerified: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<NixState>.value(
            value: state,
            child: Scaffold(
              body: MessageBubble(message: msg),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Botão de comentários visível (Telegram Style)
      expect(find.text('Deixar um comentário'), findsOneWidget);
      expect(find.byKey(const Key('channel_comments_btn_msg_post_promo_01')), findsOneWidget);

      // Verifica que a imagem/anexo está posicionado verticalmente antes do texto
      final imagePos = tester.getTopLeft(find.byKey(const ValueKey('msg_post_promo_01:0')));
      final textPos = tester.getTopLeft(find.textContaining('Fonte XPG Core Reactor'));
      expect(imagePos.dy, lessThan(textPos.dy), reason: 'A imagem deve ficar acima do texto no padrão Telegram');
    });

    testWidgets('Botão de comentários é ocultado quando administrador desativa allowComments', (tester) async {
      final state = NixState(loadMockData: false);
      state.createSpace(
        name: 'Canal Comunicados',
        description: 'Sem comentários',
        emoji: 'i:bell',
        isAnnouncementChannel: true,
      );

      // Desativa comentários no canal
      final chWithNoComments = state.currentChannel.copyWith(
        permissions: state.currentChannel.permissions.copyWith(allowComments: false),
      );
      await state.updateChannelSettings(chWithNoComments);

      final msg = Message(
        id: 'msg_announcement_locked',
        channelId: chWithNoComments.id,
        senderName: chWithNoComments.name,
        senderFingerprint: state.securityContext.myFingerprint,
        isMe: true,
        text: 'Aviso urgente sem comentários permitidos.',
        timestamp: DateTime.now(),
        isVerified: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<NixState>.value(
            value: state,
            child: Scaffold(
              body: MessageBubble(message: msg),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Deixar um comentário'), findsNothing);
      expect(find.byKey(const Key('channel_comments_btn_msg_announcement_locked')), findsNothing);
    });

    testWidgets('ChannelCommentsSheet permite aos assinantes publicar comentários na postagem', (tester) async {
      final state = NixState(loadMockData: false);
      state.createSpace(
        name: 'RHOBERLY - PROMOÇÕES',
        description: 'Canal de ofertas',
        emoji: 'i:tag',
        isAnnouncementChannel: true,
      );

      final channel = state.currentChannel;
      final msg = Message(
        id: 'msg_promo_deal',
        channelId: channel.id,
        senderName: 'RHOBERLY - PROMOÇÕES',
        senderFingerprint: state.securityContext.myFingerprint,
        isMe: true,
        text: 'Super promoção da placa de vídeo!',
        timestamp: DateTime.now(),
        isVerified: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<NixState>.value(
            value: state,
            child: Scaffold(
              body: ChannelCommentsSheet(
                channel: channel,
                message: msg,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Painel aberto
      expect(find.text('Comentários da Postagem'), findsOneWidget);
      expect(find.text('Nenhum comentário ainda'), findsOneWidget);

      // Digita um comentário
      await tester.enterText(find.byType(TextField), 'Excelente oferta, já garanti a minha!');
      await tester.tap(find.byKey(const Key('channel_comment_send_button')));
      await tester.pumpAndSettle();

      // O comentário deve ter sido publicado e associado à postagem
      expect(find.text('Excelente oferta, já garanti a minha!'), findsOneWidget);
      final storedComments = state.messagesFor(channel.id).where((m) => m.replyToMessageId == msg.id);
      expect(storedComments.length, equals(1));
      expect(storedComments.first.text, equals('Excelente oferta, já garanti a minha!'));
    });

    testWidgets('ChannelSettingsDialog contém o switch para permitir comentários', (tester) async {
      final state = NixState(loadMockData: false);
      state.createSpace(
        name: 'Canal Teste',
        description: 'Configurações',
        emoji: 'i:gear',
        isAnnouncementChannel: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<NixState>.value(
            value: state,
            child: Scaffold(
              body: ChannelSettingsDialog(channel: state.currentChannel),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Abre aba de permissões de mensagens
      await tester.tap(find.text('Permissões de Mensagens'));
      await tester.pumpAndSettle();

      // Rola a lista até o switch de comentários
      final switchFinder = find.text('Permitir Comentários nas Postagens');
      await tester.scrollUntilVisible(
        switchFinder,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(switchFinder, findsOneWidget);
    });

    test('sendChannelComment preserva replyToMessageId, excerpt e autor sem sobrescrever mensagem em edição', () {
      final state = NixState(loadMockData: false);
      state.createSpace(
        name: 'Canal de Notícias',
        description: 'Transmissões oficiais',
        emoji: 'i:newspaper',
        isAnnouncementChannel: true,
      );

      final channel = state.currentChannel;
      final post = Message(
        id: 'post_original_123',
        channelId: channel.id,
        senderName: 'Editor Chefe',
        senderFingerprint: 'ed_11223344',
        isMe: false,
        text: 'Postagem principal do canal com novidades importantes.',
        timestamp: DateTime.now(),
      );

      // Simula uma mensagem em edição no chat geral
      final draftToEdit = Message(
        id: 'msg_to_edit_456',
        channelId: channel.id,
        senderName: 'Eu',
        senderFingerprint: state.securityContext.myFingerprint,
        isMe: true,
        text: 'Texto original do rascunho',
        timestamp: DateTime.now(),
      );
      state.startEditMessage(draftToEdit);
      expect(state.editingMessage?.id, equals('msg_to_edit_456'));

      // Envia comentário vinculado à postagem via sendChannelComment
      final ok = state.sendChannelComment(
        channel: channel,
        parentMessage: post,
        text: 'Meu comentário sobre a postagem principal',
      );

      expect(ok, isTrue);

      // Garante que o rascunho em edição NÃO foi alterado nem sobrescrito
      expect(state.editingMessage?.id, equals('msg_to_edit_456'));
      expect(draftToEdit.text, equals('Texto original do rascunho'));

      // Valida que o comentário gravou a identidade e a referência do pai
      final comments = state.messagesFor(channel.id).where((m) => m.replyToMessageId == post.id).toList();
      expect(comments.length, equals(1));
      expect(comments.first.text, equals('Meu comentário sobre a postagem principal'));
      expect(comments.first.replyToMessageId, equals('post_original_123'));
      expect(comments.first.replyToSenderName, equals('Editor Chefe'));
      expect(comments.first.replyToExcerpt, equals('Postagem principal do canal com novidades importantes.'));
    });
  });
}
