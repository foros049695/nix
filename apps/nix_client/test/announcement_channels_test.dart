import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/channel.dart';
import 'package:nix_client/core/models/space.dart';
import 'package:nix_client/core/models/user_profile.dart';
import 'package:nix_client/features/chat/chat_input_bar.dart';
import 'package:nix_client/features/chat/chat_view.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Canais de Transmissão no Estilo Telegram (Seção 8)', () {
    test('Criação de canal de transmissão define ChannelType.announcement e admin proprietário', () {
      final state = NixState(loadMockData: false);
      state.createSpace(
        name: 'Canal Oficial Nix',
        description: 'Notícias oficiais do ecossistema',
        emoji: 'i:megaphone',
        isAnnouncementChannel: true,
      );

      final space = state.spaces.firstWhere((s) => s.name == 'Canal Oficial Nix');
      expect(space.channels.first.type, equals(ChannelType.announcement));
      expect(space.channels.first.admins, contains(space.ownerFingerprint));
    });

    test('Administrador pode publicar mensagem no canal de transmissão', () {
      final state = NixState(loadMockData: false);
      state.createSpace(
        name: 'Canal de Avisos',
        description: 'Comunicados urgentes',
        emoji: 'i:bell',
        isAnnouncementChannel: true,
      );

      // state.currentChannel já é o canal criado
      expect(state.currentChannel.type, equals(ChannelType.announcement));

      final sent = state.sendMessage('Comunicado soberano: atualização v2 disponível.');
      expect(sent, isTrue);
      expect(state.currentMessages.last.text, equals('Comunicado soberano: atualização v2 disponível.'));
    });

    test('Membro não-administrador é bloqueado ao tentar publicar mensagem', () {
      final state = NixState(loadMockData: false);

      // Canal de transmissão criado por outra identidade
      const externalAdminFp = 'OTHER-ADMIN-9999-AAAA';
      final announcementChannel = Channel(
        id: 'ch_announcement_external',
        spaceId: 'space_ext',
        name: 'noticias-externas',
        topic: 'Canal oficial de terceiros',
        type: ChannelType.announcement,
        category: 'TRANSMISSÃO',
        ownerFingerprint: externalAdminFp,
        admins: [externalAdminFp],
      );

      final externalSpace = Space(
        id: 'space_ext',
        name: 'Espaço Externo',
        initials: 'EE',
        description: 'Espaço de terceiros',
        ownerFingerprint: externalAdminFp,
        channels: [announcementChannel],
      );
      state.addSpace(externalSpace);
      state.selectChannel(announcementChannel);

      final sent = state.sendMessage('Tentativa de postar por não-admin');
      expect(sent, isFalse);
    });

    testWidgets('Interface exibe barra somente leitura com silenciar para membro comum', (tester) async {
      final state = NixState(loadMockData: false);

      const externalAdminFp = 'OTHER-ADMIN-9999-AAAA';
      final announcementChannel = Channel(
        id: 'ch_announcement_external',
        spaceId: 'space_ext',
        name: 'noticias-externas',
        topic: 'Canal oficial de terceiros',
        type: ChannelType.announcement,
        category: 'TRANSMISSÃO',
        ownerFingerprint: externalAdminFp,
        admins: [externalAdminFp],
      );
      state.selectChannel(announcementChannel);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<NixState>.value(
            value: state,
            child: Scaffold(
              body: ChatView(channel: announcementChannel),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Não deve ter ChatInputBar
      expect(find.byType(ChatInputBar), findsNothing);
      // Deve exibir aviso de canal de transmissão e botão de silenciar
      expect(find.text('Canal de Transmissão'), findsOneWidget);
      expect(find.text('Somente administradores podem publicar mensagens neste canal.'), findsOneWidget);
      expect(find.text('Silenciar'), findsOneWidget);
    });

    testWidgets('Interface exibe barra de entrada normal para administrador do canal', (tester) async {
      final state = NixState(loadMockData: false);
      state.createSpace(
        name: 'Canal Admin',
        description: 'Meu canal de transmissão',
        emoji: 'i:megaphone',
        isAnnouncementChannel: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<NixState>.value(
            value: state,
            child: Scaffold(
              body: ChatView(channel: state.currentChannel),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Administrador tem acesso à barra de entrada
      expect(find.byType(ChatInputBar), findsOneWidget);
    });
  });
}
