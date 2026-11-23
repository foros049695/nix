import 'workspace_banner.dart';

class InterfaceWallpaper {
  const InterfaceWallpaper({
    this.image,
    this.opacity = .24,
    this.shade = 0,
    this.blur = 0,
    this.animated = false,
    this.translucentPanels = true,
    this.panelOpacity = .28,
  });

  final WorkspaceBanner? image;
  final double opacity;
  final double shade;
  final double blur;
  final bool animated;
  final bool translucentPanels;
  final double panelOpacity;

  static InterfaceWallpaper fromJson(Object? value) {
    if (value is! Map) return const InterfaceWallpaper();
    double number(String key, double fallback, double max) {
      final number = value[key];
      return number is num && number.isFinite
          ? number.clamp(0, max).toDouble()
          : fallback;
    }

    return InterfaceWallpaper(
      image: WorkspaceBanner.fromJson(value['image']),
      opacity: number('opacity', .24, .42),
      shade: number('shade', 0, .75),
      blur: number('blur', 0, 12),
      animated: value['animated'] == true,
      translucentPanels: value['translucentPanels'] != false,
      panelOpacity: number('panelOpacity', .28, .95),
    );
  }

  Map<String, Object?> toJson() => {
        'image': image?.toJson(),
        'opacity': opacity,
        'shade': shade,
        'blur': blur,
        'animated': animated,
        'translucentPanels': translucentPanels,
        'panelOpacity': panelOpacity,
      };

  InterfaceWallpaper copyWith({
    WorkspaceBanner? image,
    double? opacity,
    double? shade,
    double? blur,
    bool? animated,
    bool? translucentPanels,
    double? panelOpacity,
  }) =>
      InterfaceWallpaper(
        image: image ?? this.image,
        opacity: opacity ?? this.opacity,
        shade: shade ?? this.shade,
        blur: blur ?? this.blur,
        animated: animated ?? this.animated,
        translucentPanels: translucentPanels ?? this.translucentPanels,
        panelOpacity: panelOpacity ?? this.panelOpacity,
      );
}
