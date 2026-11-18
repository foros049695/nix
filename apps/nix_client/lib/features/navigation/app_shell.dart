import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/channel.dart';
import '../../core/models/direct_message.dart';
import '../../core/security/window_privacy_guard.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import '../calls/call_room_view.dart';
import '../chat/chat_view.dart';
import '../chat/conversation_info_panel.dart';
import '../discovery/github_discovery_view.dart';
import '../explore/explore_spaces_view.dart';
import '../forum/forum_channel_view.dart';
import '../home/home_private_view.dart';
import '../home/home_sidebar.dart';
import '../members/members_panel.dart';
import '../monero_p2p/monero_p2p_view.dart';
import '../profile/profile_overlay.dart';
import '../publications/publication_room_view.dart';
import 'channels_sidebar.dart';
import 'panel_resize_divider.dart';
import 'resizable_window_frame.dart';
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

    final showInfoPanel = nixState.isConversationInfoOpen &&
        ((activeArea == NixActiveArea.spaces) ||
            (activeArea == NixActiveArea.homePrivate &&
                nixState.homeSubTab == HomeSubTab.directChat &&
                nixState.selectedDm != null));

    return MediaQuery(
      data: sanitizedMq,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 820;

          final Widget shellScaffold = isDesktop
              ? Scaffold(
                  backgroundColor: NixColors.background,
                  body: ResizableWindowFrame(
                    isFloating: settings.floatingWindowMode,
                    child: Column(
                      children: [
                        const WindowTitleBar(),
                        Expanded(
                          child: Row(
                            children: [
                              // Área 1: Barra vertical compacta de Pastas & Organização (redimensionável)
                              SpacesDock(width: nixState.dockWidth),

                              // Divisor Redimensionável 1: Entre Dock e Sidebar
                              PanelResizeDivider(
                                key: const Key('dock_resize_divider'),
                                onDeltaDrag: (delta) => nixState.updateDockWidth(nixState.dockWidth + delta),
                                onDoubleTapReset: () => nixState.resetDockWidth(),
                                tooltip: 'Redimensionar Pastas (Duplo clique para 78px)',
                              ),

                              // Área 2: Lista de Conversas & Navegação Principal (redimensionável)
                              if (activeArea == NixActiveArea.homePrivate ||
                                  activeArea == NixActiveArea.github ||
                                  activeArea == NixActiveArea.moneroP2p)
                                HomeSidebar(width: nixState.sidebarWidth)
                              else if (activeArea == NixActiveArea.spaces)
                                ChannelsSidebar(width: nixState.sidebarWidth),

                              // Divisor Redimensionável 2: Entre Sidebar e Conversa Ativa
                              if (activeArea == NixActiveArea.homePrivate ||
                                  activeArea == NixActiveArea.github ||
                                  activeArea == NixActiveArea.moneroP2p ||
                                  activeArea == NixActiveArea.spaces)
                                PanelResizeDivider(
                                  key: const Key('sidebar_resize_divider'),
                                  onDeltaDrag: (delta) => nixState.updateSidebarWidth(nixState.sidebarWidth + delta),
                                  onDoubleTapReset: () => nixState.resetSidebarWidth(),
                                  tooltip: 'Redimensionar Conversas (Duplo clique para 288px)',
                                ),

                              // Área 3: Conversa Ativa / Palco Principal
                              Expanded(
                                child: _buildActiveStage(activeArea, currentChannel),
                              ),

                              // Painel Lateral de Informações da Conversa (Seção 10)
                              if (showInfoPanel)
                                ConversationInfoPanel(
                                  directMessage: activeArea == NixActiveArea.homePrivate
                                      ? nixState.selectedDm
                                      : null,
                                  channel: activeArea == NixActiveArea.spaces
                                      ? currentChannel
                                      : null,
                                )
                              else if (activeArea == NixActiveArea.spaces &&
                                  nixState.isMembersPanelOpen)
                                const MembersPanel(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Scaffold(
                  backgroundColor: NixColors.background,
                  appBar: AppBar(
                    title: Row(
                      children: [
                        Icon(
                          _getAreaIcon(activeArea, currentChannel),
                          size: 18,
                          color: NixColors.textPrimary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _getAreaTitle(activeArea, nixState.selectedDm, currentChannel),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: NixColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.info_outline_rounded),
                        tooltip: 'Informações da Conversa',
                        onPressed: () => nixState.toggleConversationInfoPanel(),
                      ),
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
                    width: 366,
                    backgroundColor: NixColors.surfaceSidebar,
                    child: SafeArea(
                      child: Row(
                        children: [
                          const SpacesDock(),
                          Expanded(
                            child: (activeArea == NixActiveArea.homePrivate ||
                                    activeArea == NixActiveArea.github ||
                                    activeArea == NixActiveArea.moneroP2p)
                                ? const HomeSidebar()
                                : const ChannelsSidebar(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  body: Stack(
                    children: [
                      _buildActiveStage(activeArea, currentChannel),
                      if (showInfoPanel)
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: ConversationInfoPanel(
                            directMessage:
                                activeArea == NixActiveArea.homePrivate ? nixState.selectedDm : null,
                            channel: activeArea == NixActiveArea.spaces ? currentChannel : null,
                          ),
                        ),
                    ],
                  ),
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

  IconData _getAreaIcon(NixActiveArea activeArea, Channel channel) {
    switch (activeArea) {
      case NixActiveArea.homePrivate:
        return Icons.badge_outlined;
      case NixActiveArea.explore:
        return Icons.explore_outlined;
      case NixActiveArea.github:
        return Icons.code_rounded;
      case NixActiveArea.moneroP2p:
        return Icons.currency_exchange_rounded;
      case NixActiveArea.spaces:
        return channel.icon;
    }
  }

  String _getAreaTitle(NixActiveArea activeArea, DirectMessageThread? dm, Channel channel) {
    switch (activeArea) {
      case NixActiveArea.homePrivate:
        return dm != null ? dm.peerName : 'Conversas Privadas & Card ID';
      case NixActiveArea.explore:
        return 'Explorar Comunidades';
      case NixActiveArea.github:
        return 'GitHub Discovery';
      case NixActiveArea.moneroP2p:
        return 'Mercado Monero P2P';
      case NixActiveArea.spaces:
        return channel.name;
    }
  }

  Widget _buildActiveStage(NixActiveArea activeArea, Channel channel) {
    if (activeArea == NixActiveArea.homePrivate) {
      return const HomePrivateView();
    }
    if (activeArea == NixActiveArea.explore) {
      return const ExploreSpacesView();
    }
    if (activeArea == NixActiveArea.github) {
      return const GithubDiscoveryView();
    }
    if (activeArea == NixActiveArea.moneroP2p) {
      return const MoneroP2pView();
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
