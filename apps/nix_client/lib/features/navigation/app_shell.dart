import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/models/channel.dart';
import '../../state/nix_state.dart';
import 'spaces_dock.dart';
import 'channels_sidebar.dart';
import '../chat/chat_view.dart';
import '../calls/call_room_view.dart';
import '../publications/publication_room_view.dart';
import '../members/members_panel.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final currentChannel = nixState.currentChannel;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 850;

        if (isDesktop) {
          // ================= DESKTOP LAYOUT (3 COLUNAS) =================
          return Scaffold(
            body: Row(
              children: [
                // 1. Dock de Espaços (Extrema Esquerda)
                const SpacesDock(),

                // 2. Barra Lateral de Canais & Categorias
                const ChannelsSidebar(),

                // 3. Área Central Principal (Chat, Call ou Arquivo)
                Expanded(
                  child: _buildMainContent(currentChannel),
                ),

                // 4. Painel Lateral de Membros (Se aberto)
                if (nixState.isMembersPanelOpen)
                  const MembersPanel(),
              ],
            ),
          );
        } else {
          // ================= ANDROID / MOBILE LAYOUT =================
          return Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  Icon(currentChannel.icon, size: 18, color: currentChannel.iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      currentChannel.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.people_outline_rounded),
                  tooltip: 'Participantes',
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: NixColors.surfaceSidebar,
                      builder: (ctx) => const SizedBox(
                        height: 400,
                        child: MembersPanel(),
                      ),
                    );
                  },
                ),
              ],
            ),
            drawer: Drawer(
              backgroundColor: NixColors.surfaceSidebar,
              child: const SafeArea(
                child: Row(
                  children: [
                    SpacesDock(),
                    Expanded(child: ChannelsSidebar()),
                  ],
                ),
              ),
            ),
            body: _buildMainContent(currentChannel),
          );
        }
      },
    );
  }

  Widget _buildMainContent(Channel channel) {
    switch (channel.type) {
      case ChannelType.text:
      case ChannelType.announcement:
        return ChatView(key: ValueKey(channel.id), channel: channel);
      case ChannelType.voice:
        return CallRoomView(key: ValueKey(channel.id), channel: channel);
      case ChannelType.publication:
        return PublicationRoomView(key: ValueKey(channel.id), channel: channel);
    }
  }
}
