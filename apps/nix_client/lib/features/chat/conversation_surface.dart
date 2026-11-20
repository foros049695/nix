import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../design/nix_surfaces.dart';

class ConversationSurface extends StatelessWidget {
  final Widget child;

  const ConversationSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.bgColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _DotPattern(
                    context.accentColor
                        .withValues(alpha: context.isLightTheme ? .12 : .18),
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _DotPattern extends CustomPainter {
  final Color color;
  const _DotPattern(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final points = Path();
    for (var y = 12.0; y < size.height; y += 20) {
      for (var x = 12.0; x < size.width; x += 20) {
        points.addRect(Rect.fromLTWH(x, y, 1, 1));
      }
    }
    canvas.drawPath(points, paint);
  }

  @override
  bool shouldRepaint(_DotPattern oldDelegate) => color != oldDelegate.color;
}

BoxDecoration messageDecoration(
  BuildContext context, {
  required bool outgoing,
  bool selected = false,
}) {
  final scheme = context.nixScheme;
  final base = nixFrameDecoration(
    context,
    background: selected
        ? scheme.messageHighlight
        : outgoing
            ? scheme.messageSent
            : scheme.messageReceived,
    raised: false,
  );
  return base.copyWith(
    border: Border.all(
      color: selected
          ? context.accentColor
          : outgoing
              ? context.accentColor.withValues(alpha: .55)
              : scheme.surfaceBorderStrong,
    ),
    borderRadius: BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: Radius.circular(outgoing ? 12 : 4),
      bottomRight: Radius.circular(outgoing ? 4 : 12),
    ),
    boxShadow: [
      BoxShadow(
        color: (outgoing ? context.accentColor : scheme.surfaceBorderStrong)
            .withValues(alpha: .30),
        offset: const Offset(2, 2),
      ),
    ],
  );
}
