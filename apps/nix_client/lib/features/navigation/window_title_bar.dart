import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/user_settings.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import '../profile/pager_housing.dart';
import 'interface_wallpaper_layer.dart';

/// Barra de título e controles responsivos de janela Desktop (Seção 5).
class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final settings = nixState.settings;
    final size = MediaQuery.of(context).size;
    final wallpaperVisible = InterfaceWallpaperLayer.visibleOf(context);

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: wallpaperVisible ? NixColors.surfaceDock.withValues(alpha: 0.25) : NixColors.surfaceDock,
        border: Border(bottom: BorderSide(color: NixColors.surfaceBorder, width: 1)),
      ),
      child: Row(
        children: [
          Image.asset(
            context.brandLogoAsset128,
            width: 16,
            height: 16,
            errorBuilder: (_, __, ___) =>
                Icon(Icons.shield_moon_outlined, size: 14, color: context.accentTextColor),
          ),
          const SizedBox(width: 7),
          Text(
            'NIX',
            style: TextStyle(
              color: NixColors.textPrimary,
              fontSize: 15,
              fontFamily: pagerDisplayFont,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 11, color: NixColors.surfaceBorderStrong),
          const SizedBox(width: 10),

          // Indicador honesto de dimensões e atalho para Aparência
          InkWell(
            onTap: () => nixState.openProfileOverlay(
              startInSettings: true,
              category: SettingsCategory.appearance,
            ),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    nixState.isWindowMaximized
                        ? Icons.fullscreen_rounded
                        : Icons.aspect_ratio_rounded,
                    size: 12,
                    color: NixColors.textMuted,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    nixState.isWindowMaximized
                        ? 'Janela Maximizada · ${size.width.toInt()}×${size.height.toInt()}'
                        : 'Janela Redimensionável · ${size.width.toInt()}×${size.height.toInt()}',
                    style: TextStyle(
                      color: NixColors.textMuted,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Indicador rápido Tor Onion
          InkWell(
            onTap: () => nixState.openProfileOverlay(
              startInSettings: true,
              category: SettingsCategory.connections,
            ),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: context.accentColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.accentColor.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: nixState.isTorRunning ? NixColors.trustLevel3Green : NixColors.accentDanger,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    nixState.isTorRunning ? 'ONION V3' : 'FAIL-CLOSED',
                    style: TextStyle(
                      color: context.accentTextColor,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Alternar Modo Janela Flutuante / Restrita
          _WindowControlIcon(
            icon: settings.floatingWindowMode ? Icons.crop_square_rounded : Icons.fit_screen_rounded,
            tooltip: settings.floatingWindowMode
                ? (nixState.isWindowMaximized ? 'Restaurar Janela' : 'Maximizar Janela')
                : 'Ativar Janela Flutuante Redimensionável',
            onTap: () {
              if (!settings.floatingWindowMode) {
                nixState.toggleFloatingWindowMode(true);
              } else {
                nixState.toggleWindowMaximized();
              }
            },
          ),
          _WindowControlIcon(
            icon: Icons.palette_outlined,
            tooltip: 'Configurações → Aparência → Temas',
            onTap: () => nixState.openProfileOverlay(
              startInSettings: true,
              category: SettingsCategory.appearance,
            ),
          ),
          if (nixState.isWindowMaximized)
            _WindowControlIcon(
              icon: Icons.fullscreen_exit_rounded,
              tooltip: 'Sair do Modo Maximizado',
              onTap: () => nixState.toggleWindowMaximized(),
            ),
        ],
      ),
    );
  }
}

class _WindowControlIcon extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _WindowControlIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_WindowControlIcon> createState() => _WindowControlIconState();
}

class _WindowControlIconState extends State<_WindowControlIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 28,
            height: 24,
            decoration: BoxDecoration(
              color: _hovered ? NixColors.surfaceActive : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.icon,
              size: 13,
              color: _hovered ? NixColors.textPrimary : NixColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
