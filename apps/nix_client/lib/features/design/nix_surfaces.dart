import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/theme/nix_tokens.dart';

const nixDisplayFont = 'PixelifySans';
const nixDesktopBreakpoint = 820.0;

BoxDecoration nixFrameDecoration(
  BuildContext context, {
  Color? background,
  double radius = 13,
  bool raised = true,
}) {
  final colors = context.nixScheme;
  return BoxDecoration(
    color: background ?? colors.surfaceCard,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: colors.surfaceBorderStrong),
    boxShadow: raised
        ? [
            BoxShadow(
              color: context.accentColor
                  .withValues(alpha: colors.isLight ? .76 : .37),
              offset: const Offset(3, 3),
            ),
          ]
        : null,
  );
}

class NixFrame extends StatelessWidget {
  final Widget child;
  final Color? background;
  final EdgeInsetsGeometry? padding;
  final bool raised;

  const NixFrame({
    super.key,
    required this.child,
    this.background,
    this.padding,
    this.raised = true,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration:
            nixFrameDecoration(context, background: background, raised: raised),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      );
}

class NixPanelTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? leading;

  const NixPanelTitle({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.leading,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          leading ?? Container(
            decoration: nixFrameDecoration(context,
                background: context.surfaceActiveColor, raised: false),
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: context.accentTextColor, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.textPrimaryColor,
                    fontFamily: nixDisplayFont,
                    fontSize: 19,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                        color: context.textSecondaryColor, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      );
}

/// Profundidade apenas durante a interação. Respeita o movimento reduzido.
class NixMotionCard extends StatefulWidget {
  final Widget child;
  const NixMotionCard({super.key, required this.child});

  @override
  State<NixMotionCard> createState() => _NixMotionCardState();
}

class _NixMotionCardState extends State<NixMotionCard> {
  Offset _pointer = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onHover: reduce
          ? null
          : (event) {
              final size = context.size;
              if (size == null || size.isEmpty) return;
              setState(() => _pointer = Offset(
                    (event.localPosition.dx / size.width - .5).clamp(-.5, .5),
                    (event.localPosition.dy / size.height - .5).clamp(-.5, .5),
                  ));
            },
      onExit: reduce ? null : (_) => setState(() => _pointer = Offset.zero),
      child: TweenAnimationBuilder<Offset>(
        tween: Tween(end: reduce ? Offset.zero : _pointer),
        duration: reduce ? Duration.zero : NixTokens.motionFast,
        curve: NixTokens.curveStandard,
        builder: (_, value, child) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .0015)
            ..rotateX(value.dy * .14)
            ..rotateY(-value.dx * .16),
          child: child,
        ),
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}
