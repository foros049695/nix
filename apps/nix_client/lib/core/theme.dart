import 'package:flutter/material.dart';
import 'theme/nix_colors.dart';

class NixTheme {
  static ThemeData get tacticalDarkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: NixColors.background,
      primaryColor: NixColors.accentGreen,
      canvasColor: NixColors.surfaceSidebar,
      cardColor: NixColors.surfaceCard,
      dividerColor: NixColors.surfaceDivider,
      colorScheme: const ColorScheme.dark(
        primary: NixColors.accentGreen,
        secondary: NixColors.accentCyan,
        tertiary: NixColors.accentTor,
        surface: NixColors.surfaceCard,
        error: NixColors.accentDanger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: NixColors.surfaceSidebar,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: NixColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: NixColors.textSecondary, size: 20),
      ),
      cardTheme: CardTheme(
        color: NixColors.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: NixColors.surfaceBorder, width: 1),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: NixColors.surfaceCard,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: NixColors.surfaceBorder, width: 1),
        ),
        titleTextStyle: const TextStyle(
          color: NixColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NixColors.surfaceCardHover,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: const TextStyle(color: NixColors.textMuted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: NixColors.surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: NixColors.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: NixColors.accentGreen, width: 1.5),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF282C34),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        waitDuration: const Duration(milliseconds: 400),
      ),
    );
  }
}
