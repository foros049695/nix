import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/space.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../dialogs/create_space_dialog.dart';
import '../dialogs/manage_folders_dialog.dart';

class SpacesDock extends StatelessWidget {
  const SpacesDock({super.key});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final folders = nixState.folders;
    final folderedIds = folders.expand((f) => f.spaceIds).toSet();
    final standaloneSpaces =
        nixState.spaces.where((s) => !folderedIds.contains(s.id)).toList();

    return Container(
      width: 74,
      decoration: const BoxDecoration(
        color: NixColors.surfaceDock,
        border: Border(
          right: BorderSide(color: NixColors.surfaceBorder, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),

          // 1. Ponto de Acesso Reconhecível ao Perfil / Card ID (Ícone Oficial Nix)
          _NixBrandProfileTrigger(
            isOverlayOpen: nixState.isProfileOverlayOpen,
            onTap: () => nixState.openProfileOverlay(),
          ),
          const SizedBox(height: 10),

          // 2. Área Inicial de Conversas Privadas (Home: DMs, Friends, Requests, Transações + Card ID)
          _DockNavButton(
            key: const Key('dock_home_private_button'),
            icon: Icons.forum_outlined,
            tooltip: 'Conversas Privadas, Amigos, Transações & Card ID',
            isSelected: nixState.activeArea == NixActiveArea.homePrivate,
            badgeCount: nixState.contactRequests.length,
            onTap: () => nixState.openHomePrivateArea(),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Divider(color: NixColors.surfaceBorder, height: 1),
          ),

          // 3. Lista de Espaços Soltos + Pastas de Grupos (Folders 2x2 / Expansíveis)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 2),
              children: [
                // Espaços individuais
                ...standaloneSpaces.map((space) {
                  final isSelected = nixState.activeArea == NixActiveArea.spaces &&
                      space.id == nixState.currentSpace.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SpaceItem(
                      space: space,
                      isSelected: isSelected,
                      onTap: () => nixState.selectSpace(space),
                    ),
                  );
                }),

                // Pastas de Grupos (Estilo Discord / Android Folders — Imagem 7)
                ...folders.map((folder) {
                  final folderSpaces = nixState.spaces
                      .where((s) => folder.spaceIds.contains(s.id))
                      .toList();
                  if (folderSpaces.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SpaceFolderWidget(
                      folder: folder,
                      spaces: folderSpaces,
                      currentSpaceId: nixState.activeArea == NixActiveArea.spaces
                          ? nixState.currentSpace.id
                          : '',
                      onToggleExpand: () => nixState.toggleFolderExpanded(folder.id),
                      onSelectSpace: (sp) => nixState.selectSpace(sp),
                    ),
                  );
                }),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Divider(color: NixColors.surfaceBorder, height: 1),
          ),

          // 4. Botão Unir Grupos em Pasta
          _DockActionButton(
            key: const Key('dock_manage_folders_button'),
            icon: Icons.create_new_folder_outlined,
            tooltip: 'Unir Grupos em Pasta',
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => const ManageFoldersDialog(),
              );
            },
          ),
          const SizedBox(height: 8),

          // 5. Botão Adicionar Espaço
          _DockActionButton(
            key: const Key('dock_add_space_button'),
            icon: Icons.add_rounded,
            tooltip: 'Criar Novo Espaço / Comunidade',
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => const CreateSpaceDialog(),
              );
            },
          ),
          const SizedBox(height: 8),

          // 6. Botão Explorar Comunidades Públicas (Do menos populoso ao mais populoso)
          _DockNavButton(
            key: const Key('dock_explore_button'),
            icon: Icons.explore_outlined,
            tooltip: 'Explorar Canais e Grupos Públicos',
            isSelected: nixState.activeArea == NixActiveArea.explore,
            onTap: () => nixState.openExploreArea(),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

/// Ponto de acesso ao perfil a partir do ícone oficial do Nix (Seção 3).
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
    return Tooltip(
      message: 'Identidade Pública & Perfil Nix (Card ID)',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: const Key('nix_brand_profile_trigger'),
          onTap: widget.onTap,
          child: Row(
            children: [
              AnimatedContainer(
                duration: NixTokens.motionFast,
                width: 4,
                height: widget.isOverlayOpen ? 36 : (_hovered ? 20 : 8),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: NixTokens.motionMedium,
                curve: NixTokens.curveStandard,
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: NixColors.surfaceCard,
                  borderRadius: BorderRadius.circular(
                    widget.isOverlayOpen || _hovered ? 14 : 24,
                  ),
                  border: Border.all(
                    color: widget.isOverlayOpen || _hovered
                        ? Colors.white
                        : NixColors.surfaceBorderStrong,
                    width: widget.isOverlayOpen ? 1.8 : 1.2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/images/nix_logo_128.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text(
                      'NX',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
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

class _SpaceItem extends StatelessWidget {
  final Space space;
  final bool isSelected;
  final VoidCallback onTap;

  const _SpaceItem({
    required this.space,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedContainer(
          duration: NixTokens.motionFast,
          width: 4,
          height: isSelected ? 34 : 0,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: '${space.name} (${space.memberCount} membros)',
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(isSelected ? 14 : 24),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: NixTokens.motionFast,
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : NixColors.surfaceCard,
                    borderRadius: BorderRadius.circular(isSelected ? 14 : 24),
                    border: Border.all(
                      color: isSelected ? Colors.white : NixColors.surfaceBorderStrong,
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      space.initials,
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                if (space.unreadCount > 0)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: NixColors.surfaceDock, width: 2),
                      ),
                      child: Text(
                        '${space.unreadCount}',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Pasta de Grupos no Dock (Grade 2x2 quando fechada, Pílula Vertical quando aberta — Imagem 7).
class _SpaceFolderWidget extends StatelessWidget {
  final SpaceFolder folder;
  final List<Space> spaces;
  final String currentSpaceId;
  final VoidCallback onToggleExpand;
  final ValueChanged<Space> onSelectSpace;

  const _SpaceFolderWidget({
    required this.folder,
    required this.spaces,
    required this.currentSpaceId,
    required this.onToggleExpand,
    required this.onSelectSpace,
  });

  @override
  Widget build(BuildContext context) {
    final totalUnread = spaces.fold<int>(0, (sum, s) => sum + s.unreadCount);
    final hasActiveChild = spaces.any((s) => s.id == currentSpaceId);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: NixTokens.motionFast,
          margin: const EdgeInsets.only(top: 12),
          width: 4,
          height: hasActiveChild ? 24 : 8,
          decoration: BoxDecoration(
            color: hasActiveChild ? Colors.white : NixColors.textMuted,
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
          ),
        ),
        const SizedBox(width: 8),
        AnimatedContainer(
          duration: NixTokens.motionMedium,
          curve: NixTokens.curveStandard,
          width: 48,
          padding: EdgeInsets.symmetric(vertical: folder.isExpanded ? 6 : 0),
          decoration: BoxDecoration(
            color: folder.isExpanded ? NixColors.surfaceCard : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: folder.isExpanded
                ? Border.all(color: NixColors.surfaceBorderStrong)
                : null,
          ),
          child: folder.isExpanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Botão superior para recolher a pasta
                    Tooltip(
                      message: 'Recolher Pasta: ${folder.name}',
                      child: InkWell(
                        onTap: onToggleExpand,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 38,
                          height: 34,
                          decoration: BoxDecoration(
                            color: NixColors.surfaceActive,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.folder_open_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...spaces.map((sp) {
                      final selected = sp.id == currentSpaceId;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Tooltip(
                          message: sp.name,
                          child: InkWell(
                            onTap: () => onSelectSpace(sp),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: selected ? Colors.white : NixColors.background,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: NixColors.surfaceBorderStrong),
                              ),
                              child: Center(
                                child: Text(
                                  sp.initials,
                                  style: TextStyle(
                                    color: selected ? Colors.black : Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                )
              : Tooltip(
                  message: 'Pasta: ${folder.name} (${spaces.length} grupos)',
                  child: InkWell(
                    onTap: onToggleExpand,
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: NixColors.surfaceCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: NixColors.surfaceBorderStrong),
                          ),
                          // Grade 2x2 de miniaturas (igual à Imagem 7)
                          child: GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 3,
                              mainAxisSpacing: 3,
                            ),
                            itemCount: spaces.take(4).length,
                            itemBuilder: (context, i) {
                              final sp = spaces[i];
                              return Container(
                                decoration: BoxDecoration(
                                  color: NixColors.surfaceActive,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Center(
                                  child: Text(
                                    sp.initials[0],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        if (totalUnread > 0)
                          Positioned(
                            right: -3,
                            bottom: -3,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: NixColors.surfaceDock, width: 2),
                              ),
                              child: Text(
                                '$totalUnread',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _DockNavButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final int badgeCount;
  final VoidCallback onTap;

  const _DockNavButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    this.badgeCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedContainer(
          duration: NixTokens.motionFast,
          width: 4,
          height: isSelected ? 32 : 0,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(isSelected ? 14 : 24),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: NixTokens.motionFast,
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : NixColors.surfaceCard,
                    borderRadius: BorderRadius.circular(isSelected ? 14 : 24),
                    border: Border.all(
                      color: isSelected ? Colors.white : NixColors.surfaceBorderStrong,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? Colors.black : Colors.white,
                    size: 20,
                  ),
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: NixColors.surfaceDock, width: 2),
                      ),
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DockActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _DockActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: NixColors.surfaceBorderStrong),
          ),
          child: Icon(icon, color: NixColors.textSecondary, size: 19),
        ),
      ),
    );
  }
}
