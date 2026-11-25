import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nix_client/core/models/channel.dart';
import 'package:nix_client/features/forum/forum_channel_view.dart';
import 'package:nix_client/features/navigation/channels_sidebar.dart';
import 'package:nix_client/state/nix_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Forum Topics Creation & Sidebar UX', () {
    test('createSpace with withTopics creates forum channel', () {
      final state = NixState(loadMockData: false);
      addTearDown(state.dispose);

      state.createSpace(
        name: 'Comunidade Alpha',
        description: 'Espaço com tópicos ativados',
        emoji: 'NX',
        withTopics: true,
      );

      final createdSpace = state.spaces.firstWhere((s) => s.name == 'Comunidade Alpha');
      expect(createdSpace.channels.first.type, ChannelType.forum);
      expect(createdSpace.channels.first.topic, 'Tópico principal deste espaço.');
    });

    test('createForumPost creates topic for specified channel', () {
      final state = NixState(loadMockData: true);
      addTearDown(state.dispose);

      state.createSpace(
        name: 'Comunidade Beta',
        description: 'Espaço com tópicos',
        emoji: 'NX',
        withTopics: true,
      );
      final ch = state.currentChannel;
      expect(ch.type, ChannelType.forum);

      final ok = state.createForumPost(
        channelId: ch.id,
        title: 'Análise de Segurança de Rede LoRa',
        description: 'Tópico detalhado sobre frequências e alcance.',
        tags: const [],
      );

      expect(ok, isTrue);
      final posts = state.forumPostsFor(ch.id);
      expect(posts.length, 1);
      expect(posts.first.title, 'Análise de Segurança de Rede LoRa');
      expect(posts.first.description, 'Tópico detalhado sobre frequências e alcance.');
      expect(state.selectedForumPost?.id, posts.first.id);
    });

    testWidgets('ForumChannelView displays prominent Novo Tópico button and empty state', (tester) async {
      final state = NixState(loadMockData: false);
      addTearDown(state.dispose);

      state.createSpace(
        name: 'Comunidade Gamma',
        description: 'Espaço com tópicos',
        emoji: 'NX',
        withTopics: true,
      );
      final ch = state.currentChannel;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<NixState>.value(
              value: state,
              child: ForumChannelView(channel: ch),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Search bar hint and Novo Tópico button
      expect(find.text('Pesquisar ou criar um tópico...'), findsOneWidget);
      expect(find.byKey(const Key('forum_btn_novo_topico')), findsOneWidget);

      // Friendly Empty State when 0 topics exist
      expect(find.text('Nenhum tópico criado ainda neste espaço'), findsOneWidget);
      expect(find.byKey(const Key('forum_btn_empty_create_topic')), findsOneWidget);

      // Typing into search bar displays 'Criar' button
      await tester.enterText(find.byType(TextField).first, 'Novo Tópico de Teste');
      await tester.pumpAndSettle();
      expect(find.text('Criar'), findsOneWidget);
    });

    testWidgets('ChannelsSidebar displays Novo Tópico button under forum channel and topic item', (tester) async {
      final state = NixState(loadMockData: true);
      addTearDown(state.dispose);

      state.createSpace(
        name: 'Comunidade Delta',
        description: 'Espaço com tópicos',
        emoji: 'NX',
        withTopics: true,
      );
      final ch = state.currentChannel;

      // Add a topic
      state.createForumPost(
        channelId: ch.id,
        title: 'Tópico 1 - Hardware',
        description: 'Descrição de hardware',
        tags: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<NixState>.value(
              value: state,
              child: const ChannelsSidebar(width: 300),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The topic is rendered in the sidebar
      expect(find.text('Tópico 1 - Hardware'), findsOneWidget);
      // The "+ Novo Tópico" button is rendered in the sidebar
      expect(find.text('Novo Tópico'), findsOneWidget);
    });

    testWidgets('Broadcast channel does NOT display add channel or topic buttons', (tester) async {
      final state = NixState(loadMockData: false);
      addTearDown(state.dispose);

      state.createSpace(
        name: 'Canal Oficial',
        description: 'Transmissão oficial',
        emoji: 'NX',
        isAnnouncementChannel: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<NixState>.value(
              value: state,
              child: const ChannelsSidebar(width: 300),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Announcement channels must not have add channel or topic button
      expect(find.byTooltip('Adicionar Sala / Tópico'), findsNothing);
      expect(find.text('Novo Tópico'), findsNothing);
    });
  });
}
