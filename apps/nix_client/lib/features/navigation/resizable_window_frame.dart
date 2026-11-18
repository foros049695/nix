import 'package:flutter/material.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';

/// Moldura de Janela Flutuante e Redimensionável (Seção 4).
/// Permite redimensionar interativamente pelas bordas e cantos do mouse no desktop,
/// com cursores de redimensionamento do sistema, cantos arredondados e tamanho mínimo de segurança (800x540).
class ResizableWindowFrame extends StatefulWidget {
  final Widget child;
  final bool isFloating;
  final double minWidth;
  final double minHeight;

  const ResizableWindowFrame({
    super.key,
    required this.child,
    this.isFloating = true,
    this.minWidth = 800,
    this.minHeight = 540,
  });

  @override
  State<ResizableWindowFrame> createState() => _ResizableWindowFrameState();
}

class _ResizableWindowFrameState extends State<ResizableWindowFrame> {
  double _width = 1152;
  double _height = 720;
  bool _isMaximized = false;
  bool _initialized = false;

  void _onHorizontalDrag(double delta) {
    if (_isMaximized) return;
    setState(() {
      _width = (_width + delta).clamp(widget.minWidth, 2560);
    });
  }

  void _onVerticalDrag(double delta) {
    if (_isMaximized) return;
    setState(() {
      _height = (_height + delta).clamp(widget.minHeight, 1440);
    });
  }

  void _toggleMaximize() {
    setState(() {
      _isMaximized = !_isMaximized;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isFloating) {
      return widget.child;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_initialized) {
          _width = constraints.maxWidth > 1152 ? 1152 : constraints.maxWidth.clamp(widget.minWidth, 1152);
          _height = constraints.maxHeight > 720 ? 720 : constraints.maxHeight.clamp(widget.minHeight, 720);
          _initialized = true;
        }

        final double currentWidth = _isMaximized
            ? constraints.maxWidth
            : _width.clamp(widget.minWidth, constraints.maxWidth);
        final double currentHeight = _isMaximized
            ? constraints.maxHeight
            : _height.clamp(widget.minHeight, constraints.maxHeight);

        final frameContent = Container(
          width: currentWidth,
          height: currentHeight,
          decoration: BoxDecoration(
            color: NixColors.background,
            borderRadius: _isMaximized ? BorderRadius.zero : NixTokens.borderMd,
            border: _isMaximized
                ? null
                : Border.all(color: NixColors.surfaceBorderStrong, width: 1.2),
            boxShadow: _isMaximized
                ? null
                : const [
                    BoxShadow(
                      color: Color(0xAA000000),
                      blurRadius: 36,
                      spreadRadius: 4,
                      offset: Offset(0, 16),
                    ),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: widget.child,
        );

        if (_isMaximized) {
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

                // 1. Borda Direita (Resize Horizontal)
                Positioned(
                  top: cornerGripSize,
                  bottom: cornerGripSize,
                  right: -gripThickness / 2,
                  width: gripThickness,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (details) => _onHorizontalDrag(details.delta.dx),
                    ),
                  ),
                ),

                // 2. Borda Esquerda (Resize Horizontal invertido)
                Positioned(
                  top: cornerGripSize,
                  bottom: cornerGripSize,
                  left: -gripThickness / 2,
                  width: gripThickness,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (details) => _onHorizontalDrag(-details.delta.dx),
                    ),
                  ),
                ),

                // 3. Borda Inferior (Resize Vertical)
                Positioned(
                  left: cornerGripSize,
                  right: cornerGripSize,
                  bottom: -gripThickness / 2,
                  height: gripThickness,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpDown,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragUpdate: (details) => _onVerticalDrag(details.delta.dy),
                    ),
                  ),
                ),

                // 4. Borda Superior (Resize Vertical invertido)
                Positioned(
                  left: cornerGripSize,
                  right: cornerGripSize,
                  top: -gripThickness / 2,
                  height: gripThickness,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpDown,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragUpdate: (details) => _onVerticalDrag(-details.delta.dy),
                      onDoubleTap: _toggleMaximize,
                    ),
                  ),
                ),

                // 5. Canto Inferior Direito (Resize Diagonal UpLeft/DownRight)
                Positioned(
                  right: -cornerGripSize / 2,
                  bottom: -cornerGripSize / 2,
                  width: cornerGripSize,
                  height: cornerGripSize,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpLeftDownRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (details) {
                        _onHorizontalDrag(details.delta.dx);
                        _onVerticalDrag(details.delta.dy);
                      },
                    ),
                  ),
                ),

                // 6. Canto Inferior Esquerdo (Resize Diagonal UpRight/DownLeft)
                Positioned(
                  left: -cornerGripSize / 2,
                  bottom: -cornerGripSize / 2,
                  width: cornerGripSize,
                  height: cornerGripSize,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpRightDownLeft,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (details) {
                        _onHorizontalDrag(-details.delta.dx);
                        _onVerticalDrag(details.delta.dy);
                      },
                    ),
                  ),
                ),

                // 7. Canto Superior Direito (Resize Diagonal UpRight/DownLeft)
                Positioned(
                  right: -cornerGripSize / 2,
                  top: -cornerGripSize / 2,
                  width: cornerGripSize,
                  height: cornerGripSize,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpRightDownLeft,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (details) {
                        _onHorizontalDrag(details.delta.dx);
                        _onVerticalDrag(-details.delta.dy);
                      },
                    ),
                  ),
                ),

                // 8. Canto Superior Esquerdo (Resize Diagonal UpLeft/DownRight)
                Positioned(
                  left: -cornerGripSize / 2,
                  top: -cornerGripSize / 2,
                  width: cornerGripSize,
                  height: cornerGripSize,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpLeftDownRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (details) {
                        _onHorizontalDrag(-details.delta.dx);
                        _onVerticalDrag(-details.delta.dy);
                      },
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
