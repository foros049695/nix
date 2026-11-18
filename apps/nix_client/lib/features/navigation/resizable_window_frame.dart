import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

/// Moldura de Janela Desktop Redimensionável (Seção 5).
/// Suporta redimensionamento horizontal, vertical e diagonal pelas 8 bordas/cantos,
/// dimensões mínimas seguras (720×500), cantos arredondados e persistência opcional.
class ResizableWindowFrame extends StatefulWidget {
  final Widget child;
  final bool isFloating;
  final double minWidth;
  final double minHeight;

  const ResizableWindowFrame({
    super.key,
    required this.child,
    this.isFloating = true,
    this.minWidth = 720,
    this.minHeight = 500,
  });

  @override
  State<ResizableWindowFrame> createState() => _ResizableWindowFrameState();
}

class _ResizableWindowFrameState extends State<ResizableWindowFrame> {
  double _width = 1152;
  double _height = 720;
  bool _initialized = false;

  void _onHorizontalDrag(double delta) {
    final nixState = context.read<NixState>();
    if (nixState.isWindowMaximized) return;
    setState(() {
      _width = (_width + delta).clamp(widget.minWidth, 2560);
    });
  }

  void _onVerticalDrag(double delta) {
    final nixState = context.read<NixState>();
    if (nixState.isWindowMaximized) return;
    setState(() {
      _height = (_height + delta).clamp(widget.minHeight, 1440);
    });
  }

  void _commitGeometry() {
    context.read<NixState>().updateWindowGeometry(width: _width, height: _height);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isFloating) {
      return widget.child;
    }

    final nixState = context.watch<NixState>();
    final isMaximized = nixState.isWindowMaximized;
    final settings = nixState.settings;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_initialized) {
          final prefW = settings.persistWindowGeometry ? settings.windowWidth : 1152.0;
          final prefH = settings.persistWindowGeometry ? settings.windowHeight : 720.0;
          _width = constraints.maxWidth > prefW
              ? prefW
              : constraints.maxWidth.clamp(widget.minWidth, 2560.0);
          _height = constraints.maxHeight > prefH
              ? prefH
              : constraints.maxHeight.clamp(widget.minHeight, 1440.0);
          _initialized = true;
        }

        final safeMinW =
            constraints.maxWidth < widget.minWidth ? constraints.maxWidth : widget.minWidth;
        final safeMinH =
            constraints.maxHeight < widget.minHeight ? constraints.maxHeight : widget.minHeight;

        final double currentWidth =
            isMaximized ? constraints.maxWidth : _width.clamp(safeMinW, constraints.maxWidth);
        final double currentHeight =
            isMaximized ? constraints.maxHeight : _height.clamp(safeMinH, constraints.maxHeight);

        final frameContent = Container(
          width: currentWidth,
          height: currentHeight,
          decoration: BoxDecoration(
            color: NixColors.background,
            borderRadius: isMaximized ? BorderRadius.zero : NixTokens.borderMd,
            border: isMaximized
                ? null
                : Border.all(color: NixColors.surfaceBorderStrong, width: 1.2),
            boxShadow: isMaximized
                ? null
                : [
                    BoxShadow(
                      color: NixColors.isLight ? const Color(0x28000000) : const Color(0xAA000000),
                      blurRadius: 32,
                      spreadRadius: 2,
                      offset: const Offset(0, 12),
                    ),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: widget.child,
        );

        if (isMaximized) {
          return frameContent;
        }

        const double gripThickness = 6.0;
        const double cornerGripSize = 14.0;

        return Center(
          child: SizedBox(
            width: currentWidth,
            height: currentHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: frameContent),

                // 1. Borda Direita
                Positioned(
                  top: cornerGripSize,
                  bottom: cornerGripSize,
                  right: -gripThickness / 2,
                  width: gripThickness,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (d) => _onHorizontalDrag(d.delta.dx),
                      onHorizontalDragEnd: (_) => _commitGeometry(),
                    ),
                  ),
                ),

                // 2. Borda Esquerda
                Positioned(
                  top: cornerGripSize,
                  bottom: cornerGripSize,
                  left: -gripThickness / 2,
                  width: gripThickness,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (d) => _onHorizontalDrag(-d.delta.dx),
                      onHorizontalDragEnd: (_) => _commitGeometry(),
                    ),
                  ),
                ),

                // 3. Borda Inferior
                Positioned(
                  left: cornerGripSize,
                  right: cornerGripSize,
                  bottom: -gripThickness / 2,
                  height: gripThickness,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpDown,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragUpdate: (d) => _onVerticalDrag(d.delta.dy),
                      onVerticalDragEnd: (_) => _commitGeometry(),
                    ),
                  ),
                ),

                // 4. Borda Superior
                Positioned(
                  left: cornerGripSize,
                  right: cornerGripSize,
                  top: -gripThickness / 2,
                  height: gripThickness,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpDown,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragUpdate: (d) => _onVerticalDrag(-d.delta.dy),
                      onVerticalDragEnd: (_) => _commitGeometry(),
                      onDoubleTap: () => nixState.toggleWindowMaximized(),
                    ),
                  ),
                ),

                // 5. Canto Inferior Direito
                Positioned(
                  right: -cornerGripSize / 2,
                  bottom: -cornerGripSize / 2,
                  width: cornerGripSize,
                  height: cornerGripSize,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpLeftDownRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) {
                        _onHorizontalDrag(d.delta.dx);
                        _onVerticalDrag(d.delta.dy);
                      },
                      onPanEnd: (_) => _commitGeometry(),
                    ),
                  ),
                ),

                // 6. Canto Inferior Esquerdo
                Positioned(
                  left: -cornerGripSize / 2,
                  bottom: -cornerGripSize / 2,
                  width: cornerGripSize,
                  height: cornerGripSize,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpRightDownLeft,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) {
                        _onHorizontalDrag(-d.delta.dx);
                        _onVerticalDrag(d.delta.dy);
                      },
                      onPanEnd: (_) => _commitGeometry(),
                    ),
                  ),
                ),

                // 7. Canto Superior Direito
                Positioned(
                  right: -cornerGripSize / 2,
                  top: -cornerGripSize / 2,
                  width: cornerGripSize,
                  height: cornerGripSize,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpRightDownLeft,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) {
                        _onHorizontalDrag(d.delta.dx);
                        _onVerticalDrag(-d.delta.dy);
                      },
                      onPanEnd: (_) => _commitGeometry(),
                    ),
                  ),
                ),

                // 8. Canto Superior Esquerdo
                Positioned(
                  left: -cornerGripSize / 2,
                  top: -cornerGripSize / 2,
                  width: cornerGripSize,
                  height: cornerGripSize,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpLeftDownRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) {
                        _onHorizontalDrag(-d.delta.dx);
                        _onVerticalDrag(-d.delta.dy);
                      },
                      onPanEnd: (_) => _commitGeometry(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
