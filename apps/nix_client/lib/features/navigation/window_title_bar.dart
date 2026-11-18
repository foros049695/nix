import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/user_settings.dart';
import '../../core/security/window_privacy_guard.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';

/// Barra de título e controles de janela Desktop com indicador de proteção Antifingerprinting (Seção 7).
class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final settings = nixState.settings;
    final rawSize = MediaQuery.of(context).size;
    final reportedSize = settings.quantizeViewportDimensions
        ? WindowPrivacyGuard.quantizeSize(rawSize)
        : rawSize;

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: NixColors.surfaceDock,
        border: Border(bottom: BorderSide(color: NixColors.surfaceBorder, width: 1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_moon_outlined, size: 13, color: NixColors.textSecondary),
          const SizedBox(width: 6),
          const Text(
            'NIX',
            style: TextStyle(
              color: NixColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 11, color: NixColors.surfaceBorderStrong),
          const SizedBox(width: 10),

          // Indicador de Viewport Discretizado (Anti-Fingerprinting)
          InkWell(
            onTap: () => nixState.openProfileOverlay(
              startInSettings: true,
              category: SettingsCategory.survival,
            ),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    settings.quantizeViewportDimensions
                        ? Icons.aspect_ratio_rounded
                        : Icons.crop_free_rounded,
                    size: 12,
                    color: NixColors.textMuted,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    settings.quantizeViewportDimensions
                        ? 'Viewport Protegido: ${reportedSize.width.toInt()}×${reportedSize.height.toInt()}'
                        : 'Janela Livre',
                    style: const TextStyle(
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

          // Controles de Janela (Minimizar, Restaurar/Maximizar, Fechar)
          _WindowControlIcon(
            icon: Icons.remove_rounded,
            tooltip: 'Minimizar Janela',
            onTap: () {},
          ),
          _WindowControlIcon(
            icon: Icons.crop_square_rounded,
            tooltip: 'Alternar Modo Janela Padrão (1152×720)',
            onTap: () {
              nixState.updateSettings(
                settings.copyWith(
                  quantizeViewportDimensions: !settings.quantizeViewportDimensions,
                ),
              );
            },
          ),
          _WindowControlIcon(
            icon: Icons.close_rounded,
            tooltip: 'Fechar',
            onTap: () {},
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
            color: _hovered ? NixColors.surfaceActive : Colors.transparent,
            child: Icon(
              widget.icon,
              size: 13,
              color: _hovered ? Colors.white : NixColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
