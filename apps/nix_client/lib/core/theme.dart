import 'package:flutter/material.dart';
import 'theme/nix_colors.dart';
import 'theme/nix_tokens.dart';

class NixTheme {
  static ThemeData get amoledMonochromeTheme => buildTheme(fontScale: 1.0);

  // Mantido como alias para compatibilidade com testes existentes
  static ThemeData get tacticalDarkTheme => amoledMonochromeTheme;

  static ThemeData buildTheme({double fontScale = 1.0}) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: NixColors.background,
      primaryColor: NixColors.textPrimary,
      canvasColor: NixColors.surfaceSidebar,
      cardColor: NixColors.surfaceCard,
      dividerColor: NixColors.surfaceDivider,
      splashColor: Colors.white10,
      highlightColor: Colors.white10,
      hoverColor: NixColors.surfaceCardHover,
      colorScheme: const ColorScheme.dark(
        primary: NixColors.textPrimary,
        onPrimary: Colors.black,
        secondary: NixColors.accentSecondary,
        onSecondary: Colors.black,
        tertiary: NixColors.accentSubtle,
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
          borderSide: const BorderSide(color: NixColors.textPrimary, width: 1.2),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.black;
          return NixColors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return NixColors.textPrimary;
          return NixColors.surfaceActive;
        }),
        trackOutlineColor: WidgetStateProperty.all(NixColors.surfaceBorderStrong),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: NixColors.textPrimary,
        inactiveTrackColor: NixColors.surfaceActive,
        thumbColor: NixColors.textPrimary,
        overlayColor: Colors.white12,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF181818),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: NixColors.surfaceBorderStrong),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 11.5),
        waitDuration: const Duration(milliseconds: 350),
      ),
    );
  }
}
