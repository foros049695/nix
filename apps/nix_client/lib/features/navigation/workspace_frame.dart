import 'package:flutter/material.dart';

import '../../core/models/user_settings.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import '../chat/conversation_info_panel.dart';
import '../design/nix_surfaces.dart';
import '../design/nix_glass.dart';
import '../home/home_sidebar.dart';
import '../members/members_panel.dart';
import '../media/passport_dex_sheet.dart';
import '../profile/nix_user_avatar.dart';
import '../notifications/notification_center_dialog.dart';
import '../network/connectivity_center_dialog.dart';
import 'channels_sidebar.dart';
import 'panel_resize_divider.dart';
import 'resizable_window_frame.dart';
import 'spaces_dock.dart';
import 'window_title_bar.dart';

enum WorkspaceTab {
  chats('Conversas', Icons.chat_bubble_outline_rounded,
      Icons.chat_bubble_rounded),
  spaces('Grupos', Icons.forum_outlined, Icons.forum_rounded),
  media('Acervo', Icons.local_library_outlined, Icons.local_library_rounded),
  downloads('Downloads', Icons.downloading_outlined, Icons.downloading_rounded),
  archive('Arquivo', Icons.auto_stories_outlined, Icons.auto_stories_rounded),
  market('Cripto', Icons.currency_exchange_rounded,
      Icons.currency_exchange_rounded);

  const WorkspaceTab(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;

  static const mobileTabs = [chats, spaces, media, archive, market];

  static WorkspaceTab forArea(NixActiveArea area) => switch (area) {
        NixActiveArea.spaces => spaces,
        NixActiveArea.mediaIndex => media,
        NixActiveArea.downloads => downloads,
        NixActiveArea.archive => archive,
        NixActiveArea.moneroP2p => market,
        _ => chats,
      };

  void open(NixState state) {
    switch (this) {
      case chats:
        state.openHomePrivateArea();
      case spaces:
        state.selectFolder('all');
        if (state.spaces.isNotEmpty) state.selectSpace(state.currentSpace);
      case media:
        state.openMediaIndexArea();
      case downloads:
        state.openDownloadsArea();
      case archive:
        state.openArchiveArea();
      case market:
        state.openMoneroP2pArea();
    }
  }
}

class NixDesktopWorkspace extends StatelessWidget {
  final NixState state;
  final Widget stage;
  final Widget? offGridBanner;
  final bool showInfoPanel;

  const NixDesktopWorkspace({
    super.key,
    required this.state,
    required this.stage,
    required this.showInfoPanel,
    this.offGridBanner,
  });

  @override
  Widget build(BuildContext context) {
    final area = state.activeArea;
    final isSpace = area == NixActiveArea.spaces;
    final hasSidebar = area != NixActiveArea.explore &&
        !(isSpace && state.currentSpace.isSingleChat);
    final activeWork = state.activeWorkDetail;
    final panel = activeWork != null
        ? SizedBox(
            width: 360,
            child: PassportDexSheet(
              item: activeWork,
              isSidebar: true,
              onClose: state.closeWorkDetail,
            ),
          )
        : showInfoPanel
            ? ConversationInfoPanel(
                directMessage: isSpace ? null : state.selectedDm,
                channel: isSpace ? state.currentChannel : null,
              )
            : isSpace && state.isMembersPanelOpen
                ? const MembersPanel()
                : null;
    final wallpaper = state.settings.interfaceWallpaper;
    final wallpaperVisible = wallpaper.image != null && wallpaper.opacity > 0;
    return Scaffold(
      backgroundColor: context.bgColor,
      body: ResizableWindowFrame(
        isFloating: state.settings.floatingWindowMode,
        child: Column(
          children: [
            const WindowTitleBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 10, 7),
              child: NixGlass(child: _WorkspaceBar(state: state)),
            ),
            if (offGridBanner != null) offGridBanner!,
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                final width = constraints.maxWidth;
                final sidebarWidth = state.sidebarWidth
                    .clamp(200.0, width * .30 < 200 ? 200.0 : width * .30);
                final showSideBySide = panel != null && width >= 900;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 10, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      NixGlass(child: SpacesDock(width: state.dockWidth)),
                      PanelResizeDivider(
                        key: const Key('dock_resize_divider'),
                        onDeltaDrag: (delta) =>
                            state.updateDockWidth(state.dockWidth + delta),
                        onDoubleTapReset: state.resetDockWidth,
                        tooltip:
                            'Redimensionar Pastas (Duplo clique para 78px)',
                      ),
                      if (hasSidebar) ...[
                        NixGlass(
                            child: isSpace
                                ? ChannelsSidebar(width: sidebarWidth)
                                : HomeSidebar(width: sidebarWidth)),
                        PanelResizeDivider(
                          key: const Key('sidebar_resize_divider'),
                          onDeltaDrag: (delta) => state
                              .updateSidebarWidth(state.sidebarWidth + delta),
                          onDoubleTapReset: state.resetSidebarWidth,
                          tooltip:
                              'Redimensionar Conversas (Duplo clique para 288px)',
                        ),
                      ],
                      Expanded(
                        child: NixFrame(
                          raised: false,
                          background: wallpaperVisible ? Colors.transparent : context.bgColor,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              stage,
                              if (panel != null && !showSideBySide)
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: panel,
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (showSideBySide)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: NixFrame(child: panel),
                        ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceBar extends StatelessWidget {
  final NixState state;
  const _WorkspaceBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final selected = WorkspaceTab.forArea(state.activeArea);
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 7),
        child: Row(
          children: [
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final tab in WorkspaceTab.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: tab == selected
                          ? FilledButton.icon(
                              key: ValueKey('workspace_tab_${tab.name}'),
                              onPressed: () => tab.open(state),
                              icon: Icon(tab.activeIcon, size: 17),
                              label: Text(tab.label),
                            )
                          : OutlinedButton.icon(
                              key: ValueKey('workspace_tab_${tab.name}'),
                              onPressed: () => tab.open(state),
                              icon: Icon(tab.icon, size: 17),
                              label: Text(tab.label),
                            ),
                    ),
                ],
              ),
            ),
            IconButton(
              key: const Key('connectivity_center_trigger'),
              tooltip: 'Central de Conectividade (Rede Híbrida A–G)',
              onPressed: () => ConnectivityCenterDialog.show(context),
              icon: Icon(Icons.hub_outlined, size: 19, color: NixColors.accentCyan),
            ),
            IconButton(
              tooltip: 'Aparência do Nix',
              onPressed: () => state.openProfileOverlay(
                startInSettings: true,
                category: SettingsCategory.appearance,
              ),
              icon: const Icon(Icons.palette_outlined, size: 19),
            ),
            IconButton(
              tooltip: 'Central de Notificações',
              onPressed: () => NotificationCenterDialog.show(context),
              icon: Badge.count(
                count: state.unreadNotificationCount,
                isLabelVisible: state.unreadNotificationCount > 0,
                backgroundColor: NixColors.accentCyan,
                child: const Icon(Icons.notifications_none_rounded, size: 20),
              ),
            ),
            Tooltip(
              message: 'Abrir Pager e perfil',
              child: NixUserAvatar(
                size: 34,
                onTap: () => state.openProfileOverlay(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
