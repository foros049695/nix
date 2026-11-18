import 'package:flutter/material.dart';

/// NIX AMOLED — Sistema de Cores Monocromático de Alta Discrição.
/// Paleta obrigatória: Preto AMOLED absoluto (#000000), superfícies #080808 a #121212,
/// elementos interativos em cinza neutro e tipografia/ícones brancos monocromáticos.
/// Zero verde neon ou estética hacker.
class NixColors {
  // Fundos AMOLED & Superfícies Secundárias
  static const Color background = Color(0xFF000000);       // Preto AMOLED absoluto
  static const Color surfaceDock = Color(0xFF050505);      // Dock lateral profundo
  static const Color surfaceSidebar = Color(0xFF080808);   // Painel lateral secundário
  static const Color surfaceElevated = Color(0xFF0D0D0D);  // Cabeçalhos e barras
  static const Color surfaceCard = Color(0xFF121212);      // Cartões e superfícies secundárias
  static const Color surfaceCardHover = Color(0xFF1B1B1B); // Hover sutil em cinza neutro
  static const Color surfaceActive = Color(0xFF242424);    // Item ativo/selecionado
  static const Color surfaceInput = Color(0xFF141414);     // Campos de entrada

  // Divisórias e Bordas
  static const Color surfaceBorder = Color(0xFF222222);    // Borda discreta em cinza
  static const Color surfaceBorderStrong = Color(0xFF383838);
  static const Color surfaceDivider = Color(0xFF181818);

  // Metal AMOLED Black Reluzente (Card ID)
  static const Color metalBlackStart = Color(0xFF060607);
  static const Color metalBlackMid = Color(0xFF16171A);
  static const Color metalBlackSheen = Color(0xFF2C2E33);
  static const Color metalEdgeHighlight = Color(0xFF4A4D55);
  static const Color platinumAccent = Color(0xFFE5E7EB);
  static const Color brushedSilver = Color(0xFF9CA3AF);

  // Balões de Mensagem Monocromáticos
  static const Color messageReceived = Color(0xFF0F0F0F);
  static const Color messageSent = Color(0xFF1C1C1E);
  static const Color messageHighlight = Color(0xFF262629);

  // Tipografia (Branco e Opacidades Reduzidas)
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xB3FFFFFF);    // 70% opacidade
  static const Color textMuted = Color(0x80FFFFFF);        // 50% opacidade
  static const Color textDim = Color(0x59FFFFFF);          // 35% opacidade
  static const Color textDisabled = Color(0x38FFFFFF);     // 22% opacidade

  // Ícones e Acentos Monocromáticos (Sem verde neon / sem cores vibrantes)
  static const Color iconPrimary = Color(0xFFFFFFFF);
  static const Color iconSecondary = Color(0xB3FFFFFF);
  static const Color iconMuted = Color(0x73FFFFFF);

  // Mapeamentos semânticos monocromáticos (preservando compatibilidade sem usar cores neon)
  static const Color accentPrimary = Color(0xFFFFFFFF);
  static const Color accentSecondary = Color(0xFFD1D5DB);
  static const Color accentSubtle = Color(0xFF9CA3AF);
  static const Color accentDanger = Color(0xFFD4D4D8);     // Cinza claro de alto contraste para alertas

  // Aliases legados redirecionados para a paleta monocromática NIX AMOLED
  static const Color accentGreen = Color(0xFFFFFFFF);
  static const Color accentCyan = Color(0xFFD1D5DB);
  static const Color accentTor = Color(0xFFE5E7EB);
  static const Color accentVoice = Color(0xFFFFFFFF);
  static const Color accentPublication = Color(0xFFD4D4D8);
  static const Color accentWarning = Color(0xFFA1A1AA);
}
