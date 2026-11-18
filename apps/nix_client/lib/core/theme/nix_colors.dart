import 'package:flutter/material.dart';
import 'nix_palette.dart';

/// Sistema de Cores Reativo NIX V4 (Dark Yellow, Light Yellow e variação AMOLED).
/// Os tokens de superfície e tipografia acompanham automaticamente o modo ativo,
/// mantendo as cores semânticas de segurança/confiança sempre reconhecíveis.
class NixColors {
  static NixSurfaceScheme _scheme = NixSurfaceScheme.darkYellow;
  static NixPalette _palette = NixPalette.yellow;

  /// Sincronizado por `NixTheme.buildTheme` e `NixState` ao trocar o tema ou brilho.
  static void sync(NixSurfaceScheme scheme, NixPalette palette) {
    _scheme = scheme;
    _palette = palette;
  }

  static NixSurfaceScheme get activeScheme => _scheme;
  static NixPalette get activePalette => _palette;
  static bool get isLight => _scheme.isLight;

  // Fundos e Superfícies (Reativos ao modo: Dark Yellow, Light Yellow, AMOLED)
  static Color get background => _scheme.background;
  static Color get surfaceDock => _scheme.surfaceDock;
  static Color get surfaceSidebar => _scheme.surfaceSidebar;
  static Color get surfaceElevated => _scheme.surfaceElevated;
  static Color get surfaceElevatedHigh => _scheme.surfaceElevatedHigh;
  static Color get surfaceCard => _scheme.surfaceCard;
  static Color get surfaceCardHover => _scheme.surfaceCardHover;
  static Color get surfaceActive => _scheme.surfaceActive;
  static Color get surfaceInput => _scheme.surfaceInput;

  // Divisórias e Bordas
  static Color get surfaceBorder => _scheme.surfaceBorder;
  static Color get surfaceBorderStrong => _scheme.surfaceBorderStrong;
  static Color get surfaceDivider => _scheme.surfaceDivider;

  // Metal AMOLED Black Reluzente (Identidade visual do Card ID)
  static const Color metalBlackStart = Color(0xFF08090B);
  static const Color metalBlackMid = Color(0xFF17191E);
  static const Color metalBlackSheen = Color(0xFF292C33);
  static const Color metalEdgeHighlight = Color(0xFF434756);
  static const Color platinumAccent = Color(0xFFE5E7EB);
  static const Color brushedSilver = Color(0xFF9CA3AF);

  // Balões de Mensagem
  static Color get messageReceived => _scheme.messageReceived;
  static Color get messageSent => _scheme.messageSent;
  static Color get messageHighlight => _scheme.messageHighlight;

  // Tipografia
  static Color get textPrimary => _scheme.textPrimary;
  static Color get textSecondary => _scheme.textSecondary;
  static Color get textMuted => _scheme.textMuted;
  static Color get textDim => _scheme.textDim;
  static Color get textDisabled => _scheme.textDisabled;

  // Ícones
  static Color get iconPrimary => _scheme.iconPrimary;
  static Color get iconSecondary => _scheme.iconSecondary;
  static Color get iconMuted => _scheme.iconMuted;

  // Cores Semânticas de Segurança (Legíveis nos temas claro e escuro)
  // Modelo de Confiança em Três Níveis (Nix Trust Levels):
  static Color get trustLevel1Red =>
      _scheme.isLight ? const Color(0xFFDC2626) : const Color(0xFFEF4444);
  static Color get trustLevel2Yellow =>
      _scheme.isLight ? const Color(0xFFD97706) : const Color(0xFFF59E0B);
  static Color get trustLevel3Green =>
      _scheme.isLight ? const Color(0xFF059669) : const Color(0xFF10B981);
  static Color get trustBadgeVerified =>
      _scheme.isLight ? const Color(0xFF059669) : const Color(0xFF10B981);
  static Color get securityShield => trustBadgeVerified;

  // Acentos Reativos ao Tema
  static Color get accentPrimary => _palette.primaryAccent;
  static Color get accentSecondary => _palette.secondaryAccent;
  static Color get accentSubtle => _palette.subtleAccent;
  static Color get accentText => _palette.readableAccentOn(_scheme);
  static Color get onAccent => _palette.onAccentColor;

  static const Color accentYellow = Color(0xFFFFC928);
  static const Color accentDanger = Color(0xFFEF4444);
  static Color get accentGreen => trustLevel3Green;
  static const Color accentCyan = Color(0xFF0EA5E9);
  static Color get accentTor => _palette.readableAccentOn(_scheme);
  static Color get accentVoice => _scheme.iconPrimary;
  static Color get accentPublication => _scheme.textSecondary;
  static Color get accentWarning => trustLevel2Yellow;
}
