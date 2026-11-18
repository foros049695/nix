import 'package:flutter/material.dart';
import 'theme/nix_colors.dart';
import 'theme/nix_tokens.dart';
import 'theme/nix_palette.dart';

@immutable
class NixThemeExtension extends ThemeExtension<NixThemeExtension> {
  final NixPalette palette;
  final Color surfaceElevated;
  final Color surfaceElevatedHigh;

  const NixThemeExtension({
    required this.palette,
    required this.surfaceElevated,
    required this.surfaceElevatedHigh,
  });

  @override
  NixThemeExtension copyWith({
    NixPalette? palette,
    Color? surfaceElevated,
    Color? surfaceElevatedHigh,
  }) {
    return NixThemeExtension(
      palette: palette ?? this.palette,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceElevatedHigh: surfaceElevatedHigh ?? this.surfaceElevatedHigh,
    );
  }

  @override
  NixThemeExtension lerp(ThemeExtension<NixThemeExtension>? other, double t) {
    if (other is! NixThemeExtension) return this;
    return NixThemeExtension(
      palette: t < 0.5 ? palette : other.palette,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t) ?? surfaceElevated,
      surfaceElevatedHigh: Color.lerp(surfaceElevatedHigh, other.surfaceElevatedHigh, t) ?? surfaceElevatedHigh,
    );
  }
}

class NixTheme {
  static ThemeData get amoledMonochromeTheme => buildTheme();

  // Mantido para compatibilidade com código existente
  static ThemeData get tacticalDarkTheme => amoledMonochromeTheme;

  static ThemeData buildTheme({
    NixPalette palette = NixPalette.original,
    double fontScale = 1.0,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: NixColors.background,
      primaryColor: palette.primaryAccent,
      canvasColor: NixColors.surfaceSidebar,
      cardColor: NixColors.surfaceCard,
      dividerColor: NixColors.surfaceDivider,
      splashColor: palette.glowColor,
      highlightColor: Colors.white10,
      hoverColor: NixColors.surfaceCardHover,
      extensions: [
        NixThemeExtension(
          palette: palette,
          surfaceElevated: NixColors.surfaceElevated,
          surfaceElevatedHigh: NixColors.surfaceElevatedHigh,
        ),
      ],
      colorScheme: ColorScheme.dark(
        primary: palette.primaryAccent,
        onPrimary: Colors.black,
        secondary: palette.secondaryAccent,
        onSecondary: Colors.black,
        tertiary: palette.subtleAccent,
        surface: NixColors.surfaceCard,
        onSurface: NixColors.textPrimary,
        error: NixColors.accentDanger,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: NixColors.surfaceSidebar,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: NixColors.textPrimary,
          fontSize: 15 * fontScale,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        iconTheme: const IconThemeData(color: NixColors.iconSecondary, size: 20),
      ),
      cardTheme: CardTheme(
        color: NixColors.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: NixTokens.borderMd,
          side: const BorderSide(color: NixColors.surfaceBorder, width: 1),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: NixColors.surfaceCard,
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: NixTokens.borderLg,
          side: const BorderSide(color: NixColors.surfaceBorderStrong, width: 1),
        ),
        titleTextStyle: TextStyle(
          color: NixColors.textPrimary,
          fontSize: 17 * fontScale,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NixColors.surfaceInput,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: TextStyle(color: NixColors.textMuted, fontSize: 13 * fontScale),
        border: OutlineInputBorder(
          borderRadius: NixTokens.borderSm,
          borderSide: const BorderSide(color: NixColors.surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: NixTokens.borderSm,
          borderSide: const BorderSide(color: NixColors.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: NixTokens.borderSm,
          borderSide: BorderSide(color: palette.primaryAccent, width: 1.2),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.black;
          return NixColors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return palette.primaryAccent;
          return NixColors.surfaceActive;
        }),
        trackOutlineColor: WidgetStateProperty.all(NixColors.surfaceBorderStrong),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.primaryAccent,
        inactiveTrackColor: NixColors.surfaceActive,
        thumbColor: palette.primaryAccent,
        overlayColor: palette.glowColor,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primaryAccent,
          foregroundColor: Colors.black,
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
          foregroundColor: NixColors.textPrimary,
          side: const BorderSide(color: NixColors.surfaceBorderStrong),
          shape: RoundedRectangleBorder(borderRadius: NixTokens.borderSm),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: TextStyle(
            fontSize: 13 * fontScale,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
