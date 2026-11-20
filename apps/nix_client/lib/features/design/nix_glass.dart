import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme.dart';

class NixGlass extends StatelessWidget {
  const NixGlass(
      {super.key, required this.child, this.radius = 22, this.mirror = false});

  final Widget child;
  final double radius;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    final scheme = context.nixScheme;
    final border = BorderRadius.circular(radius);
    final base = scheme.surfaceElevated;
    return ClipRRect(
      borderRadius: border,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: border,
            border: Border.all(
                color: scheme.surfaceBorderStrong.withValues(alpha: .80)),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                          context.accentColor
                              .withValues(alpha: mirror ? .21 : .09),
                          base)
                      .withValues(alpha: scheme.isLight ? .94 : .89),
                  base.withValues(alpha: scheme.isLight ? .77 : .70),
                  Color.alphaBlend(
                          context.accentColor
                              .withValues(alpha: mirror ? .18 : .06),
                          base)
                      .withValues(alpha: .91),
                ],
                stops: const [0, .54, 1],
              ),
              borderRadius: border,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: mirror
                    ? const LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          Color(0x4DFFFFFF),
                          Color(0x0EFFFFFF),
                          Colors.transparent,
                          Color(0x197A91A7)
                        ],
                        stops: [0, .22, .65, 1],
                      )
                    : null,
              ),
              child: Material(type: MaterialType.transparency, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
