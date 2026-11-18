import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';

/// Divisor redimensionável vertical para painéis de chat desktop (V4.1).
///
/// Suporta:
/// - Cursor `col-resize`
/// - Arraste com delta horizontal
/// - Indicador visual discreto durante hover/arraste
/// - Duplo clique para restaurar a largura padrão
class PanelResizeDivider extends StatefulWidget {
  final ValueChanged<double> onDeltaDrag;
  final VoidCallback onDoubleTapReset;
  final String tooltip;

  const PanelResizeDivider({
    super.key,
    required this.onDeltaDrag,
    required this.onDoubleTapReset,
    this.tooltip = 'Arraste para redimensionar (Duplo clique para restaurar)',
  });

  @override
  State<PanelResizeDivider> createState() => _PanelResizeDividerState();
}

class _PanelResizeDividerState extends State<PanelResizeDivider> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    final isActive = _isHovered || _isDragging;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 700),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => setState(() => _isDragging = true),
          onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
          onHorizontalDragCancel: () => setState(() => _isDragging = false),
          onHorizontalDragUpdate: (details) => widget.onDeltaDrag(details.delta.dx),
          onDoubleTap: widget.onDoubleTapReset,
          child: Container(
            width: 7,
            height: double.infinity,
            alignment: Alignment.center,
            color: Colors.transparent,
            child: AnimatedContainer(
              duration: NixTokens.motionFast,
              width: isActive ? 2.5 : 1.0,
              height: double.infinity,
              decoration: BoxDecoration(
                color: isActive ? accent : NixColors.surfaceBorder,
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: context.glowColor,
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
