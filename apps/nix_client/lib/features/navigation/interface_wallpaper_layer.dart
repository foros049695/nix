import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/models/interface_wallpaper.dart';
import '../../core/theme.dart';

class InterfaceWallpaperLayer extends StatefulWidget {
  const InterfaceWallpaperLayer({
    super.key,
    required this.wallpaper,
    required this.reducedMotion,
    required this.child,
  });

  final InterfaceWallpaper wallpaper;
  final bool reducedMotion;
  final Widget child;

  static bool visibleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WallpaperScope>()?.visible ??
      false;

  static bool translucentPanelsOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_WallpaperScope>();
    return (scope?.visible ?? false) && (scope?.wallpaper.translucentPanels ?? true);
  }

  static double panelOpacityOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_WallpaperScope>();
    if (scope == null || !scope.visible || !scope.wallpaper.translucentPanels) return 1.0;
    return scope.wallpaper.panelOpacity.clamp(0.05, 0.95);
  }

  @override
  State<InterfaceWallpaperLayer> createState() =>
      _InterfaceWallpaperLayerState();
}

class _InterfaceWallpaperLayerState extends State<InterfaceWallpaperLayer>
    with WidgetsBindingObserver {
  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => setState(() {});

  @override
  Widget build(BuildContext context) {
    final wallpaper = widget.wallpaper;
    final banner = wallpaper.image;
    final visible = banner != null && wallpaper.opacity > 0;
    final path = banner?.path.toLowerCase() ?? '';
    final isAnimatedMedia = wallpaper.animated ||
        path.endsWith('.webp') ||
        path.endsWith('.gif') ||
        path.endsWith('.mp4') ||
        path.endsWith('.webm');
    final animate = isAnimatedMedia &&
        _foreground &&
        !widget.reducedMotion &&
        !MediaQuery.disableAnimationsOf(context);
    final alignment = Alignment(banner?.x ?? 0, banner?.y ?? 0);
    final file = banner == null ? null : File(banner.path);
    final image = file == null
        ? const SizedBox.shrink()
        : animate
            ? Image.file(file,
                fit: BoxFit.cover,
                alignment: alignment,
                cacheWidth: 1600,
                errorBuilder: (_, __, ___) => const SizedBox.shrink())
            : _WallpaperStill(
                key: ValueKey(file.path), file: file, alignment: alignment);
    return _WallpaperScope(
      visible: visible,
      wallpaper: wallpaper,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: context.bgColor),
          if (visible && _foreground)
            IgnorePointer(
              child: Opacity(
                opacity: wallpaper.opacity,
                child: ImageFiltered(
                  enabled: wallpaper.blur > 0,
                  imageFilter: ui.ImageFilter.blur(
                      sigmaX: wallpaper.blur, sigmaY: wallpaper.blur),
                  child: Stack(fit: StackFit.expand, children: [
                    image,
                    if (wallpaper.shade > 0)
                      ColoredBox(
                          color:
                              Colors.black.withValues(alpha: wallpaper.shade)),
                  ]),
                ),
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

class _WallpaperScope extends InheritedWidget {
  const _WallpaperScope({
    required this.visible,
    required this.wallpaper,
    required super.child,
  });

  final bool visible;
  final InterfaceWallpaper wallpaper;

  @override
  bool updateShouldNotify(_WallpaperScope oldWidget) =>
      visible != oldWidget.visible ||
      wallpaper.translucentPanels != oldWidget.wallpaper.translucentPanels ||
      wallpaper.panelOpacity != oldWidget.wallpaper.panelOpacity;
}

class _WallpaperStill extends StatefulWidget {
  const _WallpaperStill(
      {super.key, required this.file, required this.alignment});

  final File file;
  final Alignment alignment;

  @override
  State<_WallpaperStill> createState() => _WallpaperStillState();
}

class _WallpaperStillState extends State<_WallpaperStill> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final buffer = await ui.ImmutableBuffer.fromFilePath(widget.file.path);
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (width, height) =>
            ui.TargetImageSize(width: width > 1600 ? 1600 : width),
      );
      try {
        final frame = await codec.getNextFrame();
        if (mounted) {
          setState(() => _image = frame.image);
        } else {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // A imagem pode ter sido removida do armazenamento local.
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RawImage(fit: BoxFit.cover, alignment: widget.alignment, image: _image);
}
