import 'package:flutter/material.dart';

/// Modos oficiais de tema e superfície do Projeto Nix (V4).
enum NixThemeMode {
  darkYellow,  // Tema 1 (Padrão Inicial): #08090B bg, #17191E surface, #292C33 elevated, #FFC928 accent
  lightYellow, // Tema 2: #FFFFFF bg, #F6F7F9 surface, #E9EBEF elevated, #FFC928 accent
  amoled,      // Variação AMOLED Puro: #000000 bg, #0A0A0E surface, #14141A elevated
  system,      // Segue o brilho do sistema operacional (Light Yellow / Dark Yellow)
}

/// Paletas de cor de destaque personalizáveis.
enum NixPaletteType {
  yellow,   // Padrão V4: Amarelo Nix (#FFC928)
  original, // Prata / Monocromático
  violet,   // Violeta profundo
  blue,     // Azul ciber / Sky
  crimson,  // Carmesim / Red
  amber,    // Âmbar tático
  rose,     // Rosa suave
  custom,   // Personalizado livre
}

/// Esquema completo de superfícies e tipografia para o modo ativo.
@immutable
class NixSurfaceScheme {
  final Brightness brightness;
  final String label;
  final Color background;
  final Color surfaceDock;
  final Color surfaceSidebar;
  final Color surfaceCard;
  final Color surfaceCardHover;
  final Color surfaceElevated;
  final Color surfaceElevatedHigh;
  final Color surfaceActive;
  final Color surfaceInput;
  final Color surfaceBorder;
  final Color surfaceBorderStrong;
  final Color surfaceDivider;
  final Color messageReceived;
  final Color messageSent;
  final Color messageHighlight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDim;
  final Color textDisabled;
  final Color iconPrimary;
  final Color iconSecondary;
  final Color iconMuted;

  const NixSurfaceScheme({
    required this.brightness,
    required this.label,
    required this.background,
    required this.surfaceDock,
    required this.surfaceSidebar,
    required this.surfaceCard,
    required this.surfaceCardHover,
    required this.surfaceElevated,
    required this.surfaceElevatedHigh,
    required this.surfaceActive,
    required this.surfaceInput,
    required this.surfaceBorder,
    required this.surfaceBorderStrong,
    required this.surfaceDivider,
    required this.messageReceived,
    required this.messageSent,
    required this.messageHighlight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDim,
    required this.textDisabled,
    required this.iconPrimary,
    required this.iconSecondary,
    required this.iconMuted,
  });

  bool get isLight => brightness == Brightness.light;

  /// Tema 1 — Nix Dark Yellow (Especificação V4 Oficial)
  static const NixSurfaceScheme darkYellow = NixSurfaceScheme(
    brightness: Brightness.dark,
    label: 'Nix Dark Yellow',
    background: Color(0xFF08090B),
    surfaceDock: Color(0xFF0E1014),
    surfaceSidebar: Color(0xFF17191E),
    surfaceCard: Color(0xFF17191E),
    surfaceCardHover: Color(0xFF21242B),
    surfaceElevated: Color(0xFF292C33),
    surfaceElevatedHigh: Color(0xFF32363F),
    surfaceActive: Color(0xFF292C33),
    surfaceInput: Color(0xFF121418),
    surfaceBorder: Color(0x22FFFFFF),
    surfaceBorderStrong: Color(0x3DFFFFFF),
    surfaceDivider: Color(0x18FFFFFF),
    messageReceived: Color(0xFF17191E),
    messageSent: Color(0xFF292C33),
    messageHighlight: Color(0xFF333742),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB7BAC4),
    textMuted: Color(0x99B7BAC4),
    textDim: Color(0x70B7BAC4),
    textDisabled: Color(0x45B7BAC4),
    iconPrimary: Color(0xFFFFFFFF),
    iconSecondary: Color(0xFFB7BAC4),
    iconMuted: Color(0x88B7BAC4),
  );

  /// Tema 2 — Nix Light Yellow (Especificação V4 Oficial)
  static const NixSurfaceScheme lightYellow = NixSurfaceScheme(
    brightness: Brightness.light,
    label: 'Nix Light Yellow',
    background: Color(0xFFFFFFFF),
    surfaceDock: Color(0xFFE9EBEF),
    surfaceSidebar: Color(0xFFF6F7F9),
    surfaceCard: Color(0xFFF6F7F9),
    surfaceCardHover: Color(0xFFE9EBEF),
    surfaceElevated: Color(0xFFE9EBEF),
    surfaceElevatedHigh: Color(0xFFDCDFE5),
    surfaceActive: Color(0xFFE9EBEF),
    surfaceInput: Color(0xFFF6F7F9),
    surfaceBorder: Color(0x1F17191E),
    surfaceBorderStrong: Color(0x3317191E),
    surfaceDivider: Color(0x1617191E),
    messageReceived: Color(0xFFF6F7F9),
    messageSent: Color(0xFFE9EBEF),
    messageHighlight: Color(0xFFFFF4CC),
    textPrimary: Color(0xFF17191E),
    textSecondary: Color(0xFF60646C),
    textMuted: Color(0xB860646C),
    textDim: Color(0x8A60646C),
    textDisabled: Color(0x5560646C),
    iconPrimary: Color(0xFF17191E),
    iconSecondary: Color(0xFF60646C),
    iconMuted: Color(0x8C60646C),
  );

  /// Variação AMOLED Puro (#000000)
  static const NixSurfaceScheme amoled = NixSurfaceScheme(
    brightness: Brightness.dark,
    label: 'Nix AMOLED',
    background: Color(0xFF000000),
    surfaceDock: Color(0xFF050507),
    surfaceSidebar: Color(0xFF0A0A0E),
    surfaceCard: Color(0xFF101014),
    surfaceCardHover: Color(0xFF1C1C24),
    surfaceElevated: Color(0xFF19191F),
    surfaceElevatedHigh: Color(0xFF22222A),
    surfaceActive: Color(0xFF24242E),
    surfaceInput: Color(0xFF0D0D11),
    surfaceBorder: Color(0x1FFFFFFF),
    surfaceBorderStrong: Color(0x33FFFFFF),
    surfaceDivider: Color(0x14FFFFFF),
    messageReceived: Color(0xFF101015),
    messageSent: Color(0xFF1C1C24),
    messageHighlight: Color(0xFF282833),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB7BAC4),
    textMuted: Color(0x88FFFFFF),
    textDim: Color(0x60FFFFFF),
    textDisabled: Color(0x38FFFFFF),
    iconPrimary: Color(0xFFFFFFFF),
    iconSecondary: Color(0xFFB7BAC4),
    iconMuted: Color(0x73FFFFFF),
  );

  static NixSurfaceScheme resolve(NixThemeMode mode, [Brightness systemBrightness = Brightness.dark]) {
    switch (mode) {
      case NixThemeMode.darkYellow:
        return darkYellow;
      case NixThemeMode.lightYellow:
        return lightYellow;
      case NixThemeMode.amoled:
        return amoled;
      case NixThemeMode.system:
        return systemBrightness == Brightness.light ? lightYellow : darkYellow;
    }
  }
}

class NixPalette {
  final NixPaletteType type;
  final String name;
  final Color primaryAccent;
  final Color secondaryAccent;
  final Color subtleAccent;
  final Color glowColor;

  const NixPalette({
    required this.type,
    required this.name,
    required this.primaryAccent,
    required this.secondaryAccent,
    required this.subtleAccent,
    required this.glowColor,
  });

  /// Padrão Oficial V4: Amarelo Nix (#FFC928)
  static const NixPalette yellow = NixPalette(
    type: NixPaletteType.yellow,
    name: 'Nix Yellow',
    primaryAccent: Color(0xFFFFC928),
    secondaryAccent: Color(0xFFFFD859),
    subtleAccent: Color(0xFFD9A300),
    glowColor: Color(0x38FFC928),
  );

  static const NixPalette original = NixPalette(
    type: NixPaletteType.original,
    name: 'Nix Platinum',
    primaryAccent: Color(0xFFFFFFFF),
    secondaryAccent: Color(0xFFE5E7EB),
    subtleAccent: Color(0xFF9CA3AF),
    glowColor: Color(0x33FFFFFF),
  );

  static const NixPalette violet = NixPalette(
    type: NixPaletteType.violet,
    name: 'Nix Violet',
    primaryAccent: Color(0xFF8B5CF6),
    secondaryAccent: Color(0xFFA78BFA),
    subtleAccent: Color(0xFF7C3AED),
    glowColor: Color(0x338B5CF6),
  );

  static const NixPalette blue = NixPalette(
    type: NixPaletteType.blue,
    name: 'Nix Blue',
    primaryAccent: Color(0xFF0EA5E9),
    secondaryAccent: Color(0xFF38BDF8),
    subtleAccent: Color(0xFF0284C7),
    glowColor: Color(0x330EA5E9),
  );

  static const NixPalette crimson = NixPalette(
    type: NixPaletteType.crimson,
    name: 'Nix Crimson',
    primaryAccent: Color(0xFFEF4444),
    secondaryAccent: Color(0xFFF87171),
    subtleAccent: Color(0xFFDC2626),
    glowColor: Color(0x33EF4444),
  );

  static const NixPalette amber = NixPalette(
    type: NixPaletteType.amber,
    name: 'Nix Amber',
    primaryAccent: Color(0xFFF59E0B),
    secondaryAccent: Color(0xFFFBBF24),
    subtleAccent: Color(0xFFD97706),
    glowColor: Color(0x33F59E0B),
  );

  static const NixPalette rose = NixPalette(
    type: NixPaletteType.rose,
    name: 'Nix Rose',
    primaryAccent: Color(0xFFF43F5E),
    secondaryAccent: Color(0xFFFB7185),
    subtleAccent: Color(0xFFE11D48),
    glowColor: Color(0x33F43F5E),
  );

  static NixPalette fromType(NixPaletteType type, [Color? customColor]) {
    switch (type) {
      case NixPaletteType.yellow:
        return yellow;
      case NixPaletteType.original:
        return original;
      case NixPaletteType.violet:
        return violet;
      case NixPaletteType.blue:
        return blue;
      case NixPaletteType.crimson:
        return crimson;
      case NixPaletteType.amber:
        return amber;
      case NixPaletteType.rose:
        return rose;
      case NixPaletteType.custom:
        final c = customColor ?? const Color(0xFFFFC928);
        return NixPalette(
          type: NixPaletteType.custom,
          name: 'Personalizado',
          primaryAccent: c,
          secondaryAccent: Color.lerp(c, Colors.white, 0.3) ?? c,
          subtleAccent: Color.lerp(c, Colors.black, 0.3) ?? c,
          glowColor: c.withValues(alpha: 0.25),
        );
    }
  }

  /// Retorna a cor legível de texto/ícone de contraste sobre a cor de destaque.
  Color get onAccentColor =>
      ThemeData.estimateBrightnessForColor(primaryAccent) == Brightness.light
          ? const Color(0xFF17191E)
          : Colors.white;

  /// Cor segura de destaque para texto/ícones sobre o fundo do esquema ativo.
  Color readableAccentOn(NixSurfaceScheme scheme) {
    if (!scheme.isLight) {
      if (primaryAccent == const Color(0xFF17191E)) return Colors.white;
      return primaryAccent;
    }
    // Em fundos claros, garante contraste mínimo para texto/ícones amarelos ou brancos.
    final lum = primaryAccent.computeLuminance();
    if (lum > 0.45) {
      return Color.lerp(primaryAccent, const Color(0xFF17191E), 0.48) ?? const Color(0xFF8C6900);
    }
    return primaryAccent;
  }

  static const List<NixPalette> standardPalettes = [
    yellow,
    original,
    violet,
    blue,
    crimson,
    amber,
    rose,
  ];
}
