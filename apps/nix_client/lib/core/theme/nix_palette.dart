import 'package:flutter/material.dart';

enum NixPaletteType {
  original, // Prata / Branco Platina
  violet,   // Violeta profundo
  blue,     // Azul ciber / Sky
  crimson,  // Carmesim / Red
  amber,    // Âmbar tático
  rose,     // Rosa suave
  custom,   // Personalizado livre
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

  static const NixPalette original = NixPalette(
    type: NixPaletteType.original,
    name: 'Nix Original',
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
        final c = customColor ?? const Color(0xFF10B981);
        return NixPalette(
          type: NixPaletteType.custom,
          name: 'Personalizado',
          primaryAccent: c,
          secondaryAccent: Color.lerp(c, Colors.white, 0.3) ?? c,
          subtleAccent: Color.lerp(c, Colors.black, 0.3) ?? c,
          glowColor: c.withOpacity(0.25),
        );
    }
  }

  static const List<NixPalette> standardPalettes = [
    original,
    violet,
    blue,
    crimson,
    amber,
    rose,
  ];
}
