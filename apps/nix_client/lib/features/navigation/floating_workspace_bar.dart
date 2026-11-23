import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../state/nix_state.dart';
import '../dialogs/create_space_dialog.dart';
import '../design/nix_glass.dart';
import 'workspace_frame.dart';

class FloatingWorkspaceBar extends StatelessWidget {
  const FloatingWorkspaceBar({super.key, required this.state});

  final NixState state;

  @override
  Widget build(BuildContext context) {
    final selected = WorkspaceTab.forArea(state.activeArea);
    final colors = context.nixScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(10, 5, 10, 8),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: Row(
            children: [
              Expanded(
                child: NixGlass(
                  key: const Key('floating_workspace_tabs'),
                  radius: 28,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      children: [
                        for (final tab in WorkspaceTab.mobileTabs)
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: tab == selected,
                              label: tab.label,
                              child: Tooltip(
                                message: tab.label,
                                excludeFromSemantics: true,
                                child: InkWell(
                                  key: ValueKey(
                                      'mobile_workspace_tab_${tab.name}'),
                                  onTap: () => tab.open(state),
                                  customBorder: const StadiumBorder(),
                                  child: Ink(
                                    height: 48,
                                    decoration: ShapeDecoration(
                                      shape: const StadiumBorder(),
                                      color: tab == selected
                                          ? context.accentColor
                                          : Colors.transparent,
                                    ),
                                    child: ExcludeSemantics(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                              tab == selected
                                                  ? tab.activeIcon
                                                  : tab.icon,
                                              size: 19,
                                              color: tab == selected
                                                  ? context.onAccentColor
                                                  : colors.textPrimary),
                                          const SizedBox(height: 2),
                                          Text(tab.label,
                                              maxLines: 1,
                                              softWrap: false,
                                              overflow: TextOverflow.ellipsis,
                                              textScaler: MediaQuery
                                                      .textScalerOf(context)
                                                  .clamp(maxScaleFactor: 1.1),
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: tab == selected
                                                      ? context.onAccentColor
                                                      : colors.textPrimary)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              NixGlass(
                radius: 28,
                child: PopupMenuButton<_WorkspaceAction>(
                  key: const Key('workspace_quick_menu'),
                  tooltip: 'Ações rápidas',
                  icon: const Icon(Icons.add_rounded, size: 22),
                  onSelected: (action) {
                    switch (action) {
                      case _WorkspaceAction.space:
                        showDialog<void>(
                            context: context,
                            builder: (_) => const CreateSpaceDialog());
                      case _WorkspaceAction.downloads:
                        state.openDownloadsArea();
                      case _WorkspaceAction.pager:
                        state.openProfileOverlay();
                      case _WorkspaceAction.settings:
                        state.openProfileOverlay(startInSettings: true);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: _WorkspaceAction.space,
                        child: Text('Novo espaço')),
                    PopupMenuItem(
                        value: _WorkspaceAction.downloads,
                        child: Text('Downloads & Torrents')),
                    PopupMenuItem(
                        value: _WorkspaceAction.pager,
                        child: Text('Pager e perfil')),
                    PopupMenuItem(
                        value: _WorkspaceAction.settings,
                        child: Text('Configurações do Nix')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _WorkspaceAction { space, downloads, pager, settings }
