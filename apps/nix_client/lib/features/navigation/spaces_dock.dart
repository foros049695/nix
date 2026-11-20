import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/space.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../dialogs/create_space_dialog.dart';
import '../dialogs/manage_folders_dialog.dart';
import '../dialogs/nix_symbol_picker.dart';
import '../offline/share_app_offline_dialog.dart';
import '../profile/nix_user_avatar.dart';

/// Área 1 — Barra vertical compacta de Pastas & Organização (Estilo Telegram Desktop).
class SpacesDock extends StatelessWidget {
  final double? width;

  const SpacesDock({super.key, this.width});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final effectiveWidth = width ?? nixState.dockWidth;
    final folders = nixState.folders;
    final folderedIds = folders.expand((f) => f.spaceIds).toSet();
    final standaloneSpaces =
        nixState.spaces.where((s) => !folderedIds.contains(s.id)).toList();

    final totalUnreadSpaces = nixState.spaces.fold<int>(0, (sum, s) => sum + s.unreadCount);
    final totalUnreadDms = nixState.directMessages.fold<int>(0, (sum, d) => sum + d.unreadCount);
    final allUnread = totalUnreadSpaces + totalUnreadDms;

    return Container(
      width: effectiveWidth,
      decoration: BoxDecoration(
        color: NixColors.surfaceDock,
        border: Border(
          right: BorderSide(color: NixColors.surfaceBorder, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),

          // 1. Gatilho do Perfil / Card ID (Nova Logo do Nix adaptada ao Tema)
          _NixBrandProfileTrigger(
            isOverlayOpen: nixState.isProfileOverlayOpen,
            onTap: () => nixState.openProfileOverlay(),
          ),
          const SizedBox(height: 10),

          // 2. Pasta "Todas" (All Chats)
          _TelegramFolderTab(
            key: const Key('folder_tab_all'),
            icon: Icons.forum_rounded,
            label: 'Todas',
            unreadCount: allUnread,
            isSelected: nixState.activeFolderId == 'all' &&
                nixState.activeArea == NixActiveArea.spaces,
            onTap: () {
              nixState.selectFolder('all');
              if (nixState.spaces.isNotEmpty) {
                nixState.selectSpace(nixState.currentSpace);
              }
            },
          ),

          // 3. Pasta "Privadas" (Conversas Diretas, Mensagens Salvas, Amigos, Solicitações, Card ID)
          _TelegramFolderTab(
            key: const Key('dock_home_private_button'),
            icon: Icons.person_outline_rounded,
            label: 'Privadas',
            unreadCount: totalUnreadDms + nixState.contactRequests.length,
            isSelected: nixState.activeArea == NixActiveArea.homePrivate ||
                nixState.activeFolderId == 'private',
            onTap: () => nixState.openHomePrivateArea(),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Divider(color: NixColors.surfaceBorder, height: 1),
          ),

          // 4. Pastas Personalizáveis + Espaços com Drag-and-Drop real
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 2),
              children: [
                // Pastas de usuário (aceitam DMs, grupos, canais e espaços via Drag-and-Drop)
                ...folders.map((folder) {
                  final folderUnread = _computeFolderUnread(nixState, folder);
                  final folderColor = Color(folder.colorValue);
                  final isSelected = nixState.activeFolderId == folder.id;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: DragTarget<String>(
                      onWillAcceptWithDetails: (details) =>
                          !folder.spaceIds.contains(details.data) &&
                          !folder.conversationIds.contains(details.data),
                      onAcceptWithDetails: (details) {
                        nixState.assignItemToFolder(details.data, folder.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Adicionado à pasta "${folder.name}".'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      builder: (context, candidateData, rejectedData) {
                        final isHoveredDrop = candidateData.isNotEmpty;
                        return AnimatedContainer(
                          duration: NixTokens.motionFast,
                          decoration: isHoveredDrop
                              ? BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: context.accentColor, width: 1.8),
                                  color: context.accentColor.withValues(alpha: 0.14),
                                )
                              : null,
                          child: _TelegramFolderTab(
                            key: Key('folder_tab_${folder.id}'),
                            icon: folderIconFromName(folder.iconName),
                            label: folder.name,
                            customDotColor: folderColor,
                            unreadCount: folderUnread,
                            isSelected: isSelected,
                            onTap: () => nixState.selectFolder(folder.id),
                          ),
                        );
                      },
                    ),
                  );
                }),

                // Espaços avulsos (podem ser arrastados entre si para formar pastas)
                if (standaloneSpaces.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Divider(color: NixColors.surfaceBorder, height: 1),
                  ),
                  ...standaloneSpaces.map((space) {
                    final isSelected = nixState.activeArea == NixActiveArea.spaces &&
                        space.id == nixState.currentSpace.id;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: DragTarget<String>(
                        onWillAcceptWithDetails: (details) =>
                            details.data != space.id &&
                            nixState.spaces.any((s) => s.id == details.data),
                        onAcceptWithDetails: (details) {
                          nixState.combineSpacesIntoFolder(details.data, space.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Nova pasta criada por agrupamento.'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        builder: (context, candidateData, rejectedData) {
                          final isHoveredDrop = candidateData.isNotEmpty;
                          return Draggable<String>(
                            data: space.id,
                            feedback: Material(
                              color: Colors.transparent,
                              child: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: context.accentColor,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: NixColors.textPrimary, width: 1.5),
                                ),
                                child: Center(
                                  child: Text(
                                    space.initials,
                                    style: TextStyle(
                                      color: context.onAccentColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.3,
                              child: _SpaceCompactTile(
                                space: space,
                                isSelected: isSelected,
                                onTap: () {},
                              ),
                            ),
                            child: AnimatedContainer(
                              duration: NixTokens.motionFast,
                              decoration: isHoveredDrop
                                  ? BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: context.accentColor, width: 1.8),
                                    )
                                  : null,
                              child: _SpaceCompactTile(
                                space: space,
                                isSelected: isSelected,
                                onTap: () => nixState.selectSpace(space),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Divider(color: NixColors.surfaceBorder, height: 1),
          ),

          // 5. Editar Pastas (estilo Telegram "Edit")
          _DockCompactAction(
            key: const Key('manage_folders_button'),
            icon: Icons.tune_rounded,
            label: 'Editar',
            tooltip: 'Criar, Editar, Reordenar ou Excluir Pastas',
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => const ManageFoldersDialog(),
              );
            },
          ),
          const SizedBox(height: 4),

          // 6. Compartilhar Nix Offline (Estilo Briar)
          _DockCompactAction(
            key: const Key('dock_share_offline_button'),
            icon: Icons.wifi_tethering_rounded,
            label: 'Offline',
            tooltip: 'Compartilhar Nix Offline (Wi-Fi / Hotspot)',
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => const ShareAppOfflineDialog(),
              );
            },
          ),
          const SizedBox(height: 4),

          // 7. Explorar Grupos e Canais Públicos
          _DockCompactAction(
            key: const Key('dock_explore_button'),
            icon: Icons.explore_outlined,
            label: 'Explorar',
            isSelected: nixState.activeArea == NixActiveArea.explore,
            tooltip: 'Explorar Canais e Grupos Públicos',
            onTap: () => nixState.openExploreArea(),
          ),
          const SizedBox(height: 4),

          // 8. Adicionar Espaço / Grupo
          _DockCompactAction(
            key: const Key('dock_add_space_button'),
            icon: Icons.add_circle_outline_rounded,
            label: 'Novo',
            tooltip: 'Criar Novo Espaço / Grupo',
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => const CreateSpaceDialog(),
              );
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  int _computeFolderUnread(NixState state, SpaceFolder folder) {
    int count = 0;
    for (final sp in state.spaces) {
      if (folder.spaceIds.contains(sp.id)) count += sp.unreadCount;
    }
    for (final dm in state.directMessages) {
      if (folder.conversationIds.contains(dm.id)) count += dm.unreadCount;
    }
    return count;
  }
}

class _NixBrandProfileTrigger extends StatefulWidget {
  final bool isOverlayOpen;
  final VoidCallback onTap;

  const _NixBrandProfileTrigger({
    required this.isOverlayOpen,
    required this.onTap,
  });

  @override
  State<_NixBrandProfileTrigger> createState() => _NixBrandProfileTriggerState();
}

class _NixBrandProfileTriggerState extends State<_NixBrandProfileTrigger> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    return Tooltip(
      message: 'Pager e configurações',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: const Key('nix_brand_profile_trigger'),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: NixTokens.motionFast,
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: NixColors.surfaceCard,
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.isOverlayOpen || _hovered ? accent : NixColors.surfaceBorderStrong,
                width: widget.isOverlayOpen || _hovered ? 1.8 : 1.1,
              ),
              boxShadow: widget.isOverlayOpen || _hovered
                  ? [
                      BoxShadow(
                        color: context.glowColor,
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
            child: const NixUserAvatar(
              size: 40,
              showBorder: false,
            ),
          ),
        ),
      ),
    );
  }
}

class _TelegramFolderTab extends StatefulWidget {
  final IconData icon;
  final String label;
  final int unreadCount;
  final Color? customDotColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _TelegramFolderTab({
    super.key,
    required this.icon,
    required this.label,
    this.unreadCount = 0,
    this.customDotColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_TelegramFolderTab> createState() => _TelegramFolderTabState();
}

class _TelegramFolderTabState extends State<_TelegramFolderTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    final accentText = context.accentTextColor;

    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: NixTokens.motionFast,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? accent.withValues(alpha: 0.16)
                  : (_hovered ? NixColors.surfaceCardHover : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
              border: widget.isSelected
                  ? Border.all(color: accent.withValues(alpha: 0.5), width: 1.0)
                  : null,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.customDotColor != null) ...[
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 3),
                            decoration: BoxDecoration(
                              color: widget.customDotColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                        Icon(
                          widget.icon,
                          size: 20,
                          color: widget.isSelected ? accentText : NixColors.iconSecondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: widget.isSelected ? accentText : NixColors.textSecondary,
                        fontSize: 10,
                        fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                if (widget.unreadCount > 0)
                  Positioned(
                    right: 4,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: widget.isSelected ? accent : NixColors.surfaceElevatedHigh,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: NixColors.surfaceDock, width: 1.2),
                      ),
                      child: Text(
                        widget.unreadCount > 99 ? '99+' : '${widget.unreadCount}',
                        style: TextStyle(
                          color: widget.isSelected ? context.onAccentColor : NixColors.textPrimary,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpaceCompactTile extends StatelessWidget {
  final Space space;
  final bool isSelected;
  final VoidCallback onTap;

  const _SpaceCompactTile({
    required this.space,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    return Tooltip(
      message: '${space.name} (${space.categoryTag})',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          height: 44,
          decoration: BoxDecoration(
            color: isSelected ? accent : NixColors.surfaceCard,
            borderRadius: BorderRadius.circular(isSelected ? 14 : 22),
            border: Border.all(
              color: isSelected ? accent : NixColors.surfaceBorderStrong,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: NixSymbol(
                  space.iconEmoji ?? space.initials,
                  color: isSelected ? context.onAccentColor : NixColors.textPrimary,
                  size: 17,
                ),
              ),
              if (space.unreadCount > 0)
                Positioned(
                  right: -4,
                  bottom: -3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: NixColors.surfaceDock, width: 1.5),
                    ),
                    child: Text(
                      '${space.unreadCount}',
                      style: TextStyle(
                        color: context.onAccentColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockCompactAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  const _DockCompactAction({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    final accentText = context.accentTextColor;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? accent.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected ? Border.all(color: accent.withValues(alpha: 0.45)) : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? accentText : NixColors.iconSecondary,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? accentText : NixColors.textMuted,
                  fontSize: 9.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
