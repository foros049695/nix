import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/channel.dart';
import '../../core/security/window_privacy_guard.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import '../calls/call_room_view.dart';
import '../chat/chat_view.dart';
import '../explore/explore_spaces_view.dart';
import '../forum/forum_channel_view.dart';
import '../home/home_private_view.dart';
import '../home/home_sidebar.dart';
import '../members/members_panel.dart';
import '../profile/profile_overlay.dart';
import '../publications/publication_room_view.dart';
import 'channels_sidebar.dart';
import 'spaces_dock.dart';
import 'window_title_bar.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final settings = nixState.settings;
    final currentChannel = nixState.currentChannel;
    final activeArea = nixState.activeArea;

    final rawMq = MediaQuery.of(context);
    final sanitizedMq = WindowPrivacyGuard.sanitizedMediaQuery(
      rawMq,
      quantizeDimensions: settings.quantizeViewportDimensions,
      reducedMotion: settings.reducedMotion,
    );

    return MediaQuery(
      data: sanitizedMq,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 820;

          final Widget shellScaffold = isDesktop
              ? Scaffold(
                  backgroundColor: NixColors.background,
                  body: Column(
                    children: [
                      const WindowTitleBar(),
                      Expanded(
                        child: Row(
                          children: [
                            // 1. Dock de Espaços, Pastas, Home e Explorar
                            const SpacesDock(),

                            // 2. Barra Lateral Secundária (Home Privada ou Canais do Espaço)
                            if (activeArea == NixActiveArea.homePrivate)
                              const HomeSidebar()
                            else if (activeArea == NixActiveArea.spaces)
                              const ChannelsSidebar(),

                            // 3. Palco Principal
                            Expanded(
                              child: _buildActiveStage(activeArea, currentChannel),
                            ),

                            // 4. Painel de Membros (Quando aberto em um Espaço)
                            if (activeArea == NixActiveArea.spaces && nixState.isMembersPanelOpen)
                              const MembersPanel(),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : Scaffold(
                  backgroundColor: NixColors.background,
                  appBar: AppBar(
                    title: Row(
                      children: [
                        Icon(
                          activeArea == NixActiveArea.explore
                              ? Icons.explore_outlined
                              : (activeArea == NixActiveArea.homePrivate
                                  ? Icons.badge_outlined
                                  : currentChannel.icon),
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            activeArea == NixActiveArea.explore
                                ? 'Explorar Comunidades'
                                : (activeArea == NixActiveArea.homePrivate
                                    ? 'Conversas Privadas & Card ID'
                                    : currentChannel.name),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.badge_outlined),
                        tooltip: 'Abrir Card ID & Perfil',
                        onPressed: () => nixState.openProfileOverlay(),
                      ),
                      if (activeArea == NixActiveArea.spaces)
                        IconButton(
                          icon: const Icon(Icons.people_outline_rounded),
                          tooltip: 'Participantes',
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: NixColors.surfaceSidebar,
                              builder: (_) => const SizedBox(
                                height: 400,
                                child: MembersPanel(),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  drawer: Drawer(
                    width: 324,
                    backgroundColor: NixColors.surfaceSidebar,
                    child: SafeArea(
                      child: Row(
                        children: [
                          const SpacesDock(),
                          Expanded(
                            child: activeArea == NixActiveArea.homePrivate
                                ? const HomeSidebar()
                                : const ChannelsSidebar(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  body: _buildActiveStage(activeArea, currentChannel),
                );

          return Stack(
            children: [
              shellScaffold,
              if (nixState.isProfileOverlayOpen) const ProfileOverlay(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActiveStage(NixActiveArea activeArea, Channel channel) {
    if (activeArea == NixActiveArea.homePrivate) {
      return const HomePrivateView();
    }
    if (activeArea == NixActiveArea.explore) {
      return const ExploreSpacesView();
    }

    switch (channel.type) {
      case ChannelType.text:
      case ChannelType.announcement:
        return ChatView(key: ValueKey(channel.id), channel: channel);
      case ChannelType.forum:
        return ForumChannelView(key: ValueKey(channel.id), channel: channel);
      case ChannelType.voice:
        return CallRoomView(key: ValueKey(channel.id), channel: channel);
      case ChannelType.publication:
        return PublicationRoomView(key: ValueKey(channel.id), channel: channel);
    }
  }
}
