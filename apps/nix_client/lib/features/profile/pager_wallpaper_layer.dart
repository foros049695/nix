import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../state/nix_state.dart';

class PagerWallpaperLayer extends StatelessWidget {
  const PagerWallpaperLayer(
      {super.key, required this.state, this.readable = false});

  final NixState state;
  final bool readable;

  @override
  Widget build(BuildContext context) {
    final settings = state.settings;
    final blur = settings.pagerWallpaperBlur;
    return Image(
      key: ValueKey(state.pagerWallpaperRevision),
      image: NixState.pagerWallpaperImage,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      frameBuilder: (context, child, frame, synchronous) {
        if (frame == null && !synchronous) return child;
        final display = Color(settings.pagerLcdColor.rgb);
        return Stack(fit: StackFit.expand, children: [
          ImageFiltered(
              enabled: blur > 0,
              imageFilter: ImageFilter.blur(
                  sigmaX: blur, sigmaY: blur, tileMode: TileMode.clamp),
              child: child),
          ColoredBox(
              color:
                  Colors.black.withValues(alpha: settings.pagerWallpaperShade)),
          if (readable) ColoredBox(color: display.withValues(alpha: .73)),
        ]);
      },
    );
  }
}
