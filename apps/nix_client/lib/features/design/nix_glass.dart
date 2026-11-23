import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../navigation/interface_wallpaper_layer.dart';

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
    final wallpaperVisible = InterfaceWallpaperLayer.visibleOf(context);
    final isTranslucent = InterfaceWallpaperLayer.translucentPanelsOf(context);
    final userAlpha = InterfaceWallpaperLayer.panelOpacityOf(context);
    final alphaTop = isTranslucent ? userAlpha : (scheme.isLight ? .94 : .89);
    final alphaMid = isTranslucent ? (userAlpha * 0.6).clamp(0.08, 0.8) : (scheme.isLight ? .77 : .70);
    final alphaBot = isTranslucent ? (userAlpha * 0.85).clamp(0.12, 0.88) : .91;

    return ClipRRect(
      borderRadius: border,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: border,
            border: Border.all(
                color: scheme.surfaceBorderStrong
                    .withValues(alpha: isTranslucent ? .35 : .80)),
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
                      .withValues(alpha: alphaTop),
                  base.withValues(alpha: alphaMid),
                  Color.alphaBlend(
                          context.accentColor
                              .withValues(alpha: mirror ? .18 : .06),
                          base)
                      .withValues(alpha: alphaBot),
                ],
                stops: const [0, .54, 1],
              ),
              borderRadius: border,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: mirror
                    ? LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          Color(wallpaperVisible ? 0x18FFFFFF : 0x4DFFFFFF),
                          Color(wallpaperVisible ? 0x08FFFFFF : 0x0EFFFFFF),
                          Colors.transparent,
                          Color(wallpaperVisible ? 0x0E7A91A7 : 0x197A91A7),
                        ],
                        stops: const [0, .22, .65, 1],
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
