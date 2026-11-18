import 'package:flutter/material.dart';
import 'theme/nix_colors.dart';
import 'theme/nix_tokens.dart';
import 'theme/nix_palette.dart';

@immutable
class NixThemeExtension extends ThemeExtension<NixThemeExtension> {
  final NixPalette palette;
  final NixSurfaceScheme scheme;
  final Color surfaceElevated;
  final Color surfaceElevatedHigh;

  const NixThemeExtension({
    required this.palette,
    required this.scheme,
    required this.surfaceElevated,
    required this.surfaceElevatedHigh,
  });

  @override
  NixThemeExtension copyWith({
    NixPalette? palette,
    NixSurfaceScheme? scheme,
    Color? surfaceElevated,
    Color? surfaceElevatedHigh,
  }) {
    return NixThemeExtension(
      palette: palette ?? this.palette,
      scheme: scheme ?? this.scheme,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceElevatedHigh: surfaceElevatedHigh ?? this.surfaceElevatedHigh,
    );
  }

  @override
  NixThemeExtension lerp(ThemeExtension<NixThemeExtension>? other, double t) {
    if (other is! NixThemeExtension) return this;
    return NixThemeExtension(
      palette: t < 0.5 ? palette : other.palette,
      scheme: t < 0.5 ? scheme : other.scheme,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t) ?? surfaceElevated,
      surfaceElevatedHigh:
          Color.lerp(surfaceElevatedHigh, other.surfaceElevatedHigh, t) ?? surfaceElevatedHigh,
    );
  }
}

class NixTheme {
  static ThemeData get darkYellowTheme =>
      buildTheme(scheme: NixSurfaceScheme.darkYellow, palette: NixPalette.yellow);

  static ThemeData get lightYellowTheme =>
      buildTheme(scheme: NixSurfaceScheme.lightYellow, palette: NixPalette.yellow);

  static ThemeData get amoledMonochromeTheme =>
      buildTheme(scheme: NixSurfaceScheme.amoled, palette: NixPalette.yellow);

  // Mantido para compatibilidade
  static ThemeData get tacticalDarkTheme => darkYellowTheme;

  static ThemeData buildTheme({
    NixSurfaceScheme scheme = NixSurfaceScheme.darkYellow,
    NixPalette palette = NixPalette.yellow,
    double fontScale = 1.0,
  }) {
    final isLight = scheme.isLight;
    final onPrimary = palette.onAccentColor;

    final baseScheme = isLight
        ? ColorScheme.light(
            primary: palette.primaryAccent,
            onPrimary: onPrimary,
            secondary: palette.secondaryAccent,
            onSecondary: onPrimary,
            tertiary: palette.subtleAccent,
            surface: scheme.surfaceCard,
            onSurface: scheme.textPrimary,
            error: NixColors.accentDanger,
          )
        : ColorScheme.dark(
            primary: palette.primaryAccent,
            onPrimary: onPrimary,
            secondary: palette.secondaryAccent,
            onSecondary: onPrimary,
            tertiary: palette.subtleAccent,
            surface: scheme.surfaceCard,
            onSurface: scheme.textPrimary,
            error: NixColors.accentDanger,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      scaffoldBackgroundColor: scheme.background,
      primaryColor: palette.primaryAccent,
      canvasColor: scheme.surfaceSidebar,
      cardColor: scheme.surfaceCard,
      dividerColor: scheme.surfaceDivider,
      splashColor: palette.glowColor,
      highlightColor: isLight ? const Color(0x0D17191E) : Colors.white10,
      hoverColor: scheme.surfaceCardHover,
      extensions: [
        NixThemeExtension(
          palette: palette,
          scheme: scheme,
          surfaceElevated: scheme.surfaceElevated,
          surfaceElevatedHigh: scheme.surfaceElevatedHigh,
        ),
      ],
      colorScheme: baseScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceSidebar,
        foregroundColor: scheme.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.textPrimary,
          fontSize: 15 * fontScale,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(color: scheme.iconSecondary, size: 20),
      ),
      cardTheme: CardTheme(
        color: scheme.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: NixTokens.borderMd,
          side: BorderSide(color: scheme.surfaceBorder, width: 1),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: scheme.surfaceCard,
        elevation: 20,
        shape: RoundedRectangleBorder(
          borderRadius: NixTokens.borderLg,
          side: BorderSide(color: scheme.surfaceBorderStrong, width: 1),
        ),
        titleTextStyle: TextStyle(
          color: scheme.textPrimary,
          fontSize: 17 * fontScale,
          fontWeight: FontWeight.w700,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surfaceElevatedHigh,
        contentTextStyle: TextStyle(color: scheme.textPrimary, fontSize: 13 * fontScale),
        shape: RoundedRectangleBorder(
          borderRadius: NixTokens.borderSm,
          side: BorderSide(color: palette.primaryAccent.withValues(alpha: 0.4)),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceElevated,
        textStyle: TextStyle(color: scheme.textPrimary, fontSize: 13 * fontScale),
        shape: RoundedRectangleBorder(
          borderRadius: NixTokens.borderMd,
          side: BorderSide(color: scheme.surfaceBorderStrong),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceInput,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: TextStyle(color: scheme.textMuted, fontSize: 13 * fontScale),
        labelStyle: TextStyle(color: scheme.textSecondary, fontSize: 13 * fontScale),
        border: OutlineInputBorder(
          borderRadius: NixTokens.borderSm,
          borderSide: BorderSide(color: scheme.surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: NixTokens.borderSm,
          borderSide: BorderSide(color: scheme.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: NixTokens.borderSm,
          borderSide: BorderSide(color: palette.primaryAccent, width: 1.5),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return onPrimary;
          return scheme.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return palette.primaryAccent;
          return scheme.surfaceActive;
        }),
        trackOutlineColor: WidgetStateProperty.all(scheme.surfaceBorderStrong),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return palette.primaryAccent;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(onPrimary),
        side: BorderSide(color: scheme.surfaceBorderStrong, width: 1.5),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.primaryAccent,
        inactiveTrackColor: scheme.surfaceActive,
        thumbColor: palette.primaryAccent,
        overlayColor: palette.glowColor,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primaryAccent,
          foregroundColor: onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: NixTokens.borderSm),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: TextStyle(
            fontSize: 13 * fontScale,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.textPrimary,
          side: BorderSide(color: scheme.surfaceBorderStrong),
          shape: RoundedRectangleBorder(borderRadius: NixTokens.borderSm),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: TextStyle(
            fontSize: 13 * fontScale,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.readableAccentOn(scheme),
        ),
      ),
    );
  }
}

extension NixThemeContext on BuildContext {
  NixThemeExtension? get _ext => Theme.of(this).extension<NixThemeExtension>();

  NixPalette get nixPalette => _ext?.palette ?? NixPalette.yellow;
  NixSurfaceScheme get nixScheme => _ext?.scheme ?? NixSurfaceScheme.darkYellow;

  bool get isLightTheme => nixScheme.isLight;
  Color get accentColor => Theme.of(this).colorScheme.primary;
  Color get onAccentColor => nixPalette.onAccentColor;
  Color get accentTextColor => nixPalette.readableAccentOn(nixScheme);
  Color get glowColor => nixPalette.glowColor;

  Color get bgColor => nixScheme.background;
  Color get surfaceColor => nixScheme.surfaceCard;
  Color get surfaceDockColor => nixScheme.surfaceDock;
  Color get surfaceSidebarColor => nixScheme.surfaceSidebar;
  Color get surfaceElevatedColor => nixScheme.surfaceElevated;
  Color get surfaceElevatedHighColor => nixScheme.surfaceElevatedHigh;
  Color get surfaceInputColor => nixScheme.surfaceInput;
  Color get surfaceHoverColor => nixScheme.surfaceCardHover;
  Color get surfaceActiveColor => nixScheme.surfaceActive;
  Color get borderColor => nixScheme.surfaceBorder;
  Color get borderStrongColor => nixScheme.surfaceBorderStrong;
  Color get textPrimaryColor => nixScheme.textPrimary;
  Color get textSecondaryColor => nixScheme.textSecondary;
  Color get textMutedColor => nixScheme.textMuted;

  /// Asset da logo Nix adaptado automaticamente ao tema claro/escuro ativo.
  String get brandLogoAsset =>
      isLightTheme ? 'assets/images/nix_logo_ink.png' : 'assets/images/nix_logo_light.png';
  String get brandLogoAsset128 =>
      isLightTheme ? 'assets/images/nix_logo_ink_128.png' : 'assets/images/nix_logo_128.png';
}
