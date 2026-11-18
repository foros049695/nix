import 'package:flutter/material.dart';
import 'nix_colors.dart';

/// Tokens do Design System NIX AMOLED — Espaçamentos, Raios, Animações e Sombras.
class NixTokens {
  // Espaçamento Sistemático (Base 4px)
  static const double spaceXxs = 2.0;
  static const double spaceXs = 4.0;
  static const double spaceSm = 8.0;
  static const double spaceMd = 12.0;
  static const double spaceLg = 16.0;
  static const double spaceXl = 24.0;
  static const double spaceXxl = 32.0;
  static const double spaceHuge = 48.0;

  // Raios de Borda Consistentes
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 22.0;
  static const double radiusCardId = 18.0;
  static const double radiusPill = 999.0;

  static final BorderRadius borderSm = BorderRadius.circular(radiusSm);
  static final BorderRadius borderMd = BorderRadius.circular(radiusMd);
  static final BorderRadius borderLg = BorderRadius.circular(radiusLg);
  static final BorderRadius borderXl = BorderRadius.circular(radiusXl);

  // Fluid Motion — Durações e Curvas de Interpolação
  static const Duration motionFast = Duration(milliseconds: 140);
  static const Duration motionMedium = Duration(milliseconds: 240);
  static const Duration motionFluid = Duration(milliseconds: 380);
  static const Duration motionSlow = Duration(milliseconds: 520);

  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveFluid = Curves.easeInOutCubicEmphasized;
  static const Curve curveSpring = Curves.easeOutBack;

  // Sombras Discretas (Sem brilho colorido)
  static List<BoxShadow> get elevationSubtle => const [
        BoxShadow(
          color: Color(0x88000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get elevationModal => const [
        BoxShadow(
          color: Color(0xCC000000),
          blurRadius: 36,
          spreadRadius: 4,
          offset: Offset(0, 12),
        ),
      ];

  // Gradiente Metálico AMOLED Black Reluzente (exclusivo para o Card ID)
  static const LinearGradient amoledMetalGradient = LinearGradient(
    begin: Alignment(-0.9, -0.8),
    end: Alignment(0.9, 0.8),
    colors: [
      Color(0xFF060607),
      Color(0xFF141517),
      Color(0xFF232529),
      Color(0xFF101113),
      Color(0xFF050506),
    ],
    stops: [0.0, 0.32, 0.50, 0.72, 1.0],
  );

  // Reflexo especular de borda metálica
  static const LinearGradient metalBorderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF52555E),
      Color(0xFF23252A),
      Color(0xFF6B707B),
      Color(0xFF1B1C20),
    ],
  );

  // Estilos tipográficos base
  static TextStyle headingLarge([double scale = 1.0]) => TextStyle(
        color: NixColors.textPrimary,
        fontSize: 22 * scale,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      );

  static TextStyle headingMedium([double scale = 1.0]) => TextStyle(
        color: NixColors.textPrimary,
        fontSize: 16 * scale,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      );

  static TextStyle labelUppercase([double scale = 1.0]) => TextStyle(
        color: NixColors.textMuted,
        fontSize: 11 * scale,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
      );

  static TextStyle bodyRegular([double scale = 1.0]) => TextStyle(
        color: NixColors.textPrimary,
        fontSize: 14 * scale,
        height: 1.4,
      );

  static TextStyle monoCode([double scale = 1.0]) => TextStyle(
        color: NixColors.textSecondary,
        fontSize: 12 * scale,
        fontFamily: 'monospace',
        letterSpacing: 0.5,
      );
}
