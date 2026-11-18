import 'package:flutter/material.dart';

/// NIX LIVING AMOLED — Sistema de Cores V2.
/// Fundo AMOLED absoluto (#000000), superfícies elevadas (#101014, #19191F),
/// tipografia (#FFFFFF, #B8B8C2), bordas translúcidas sutis e níveis de confiança semânticos.
class NixColors {
  // Fundos AMOLED & Superfícies Elevadas (V2)
  static const Color background = Color(0xFF000000);         // Preto AMOLED absoluto
  static const Color surfaceDock = Color(0xFF050507);        // Dock lateral mais profundo
  static const Color surfaceSidebar = Color(0xFF0A0A0E);     // Painel lateral secundário
  static const Color surfaceElevated = Color(0xFF101014);    // Superfície elevada base
  static const Color surfaceElevatedHigh = Color(0xFF19191F);// Superfície com maior elevação
  static const Color surfaceCard = Color(0xFF101014);        // Cartões
  static const Color surfaceCardHover = Color(0xFF1C1C24);   // Hover refinado
  static const Color surfaceActive = Color(0xFF24242E);      // Item ativo/selecionado
  static const Color surfaceInput = Color(0xFF0D0D11);       // Campos de entrada

  // Divisórias e Bordas com Baixa Opacidade
  static const Color surfaceBorder = Color(0x1FFFFFFF);      // ~12% opacidade
  static const Color surfaceBorderStrong = Color(0x33FFFFFF);// ~20% opacidade
  static const Color surfaceDivider = Color(0x14FFFFFF);     // ~8% opacidade

  // Metal AMOLED Black Reluzente (Card ID)
  static const Color metalBlackStart = Color(0xFF08080C);
  static const Color metalBlackMid = Color(0xFF15161C);
  static const Color metalBlackSheen = Color(0xFF2A2D38);
  static const Color metalEdgeHighlight = Color(0xFF434756);
  static const Color platinumAccent = Color(0xFFE5E7EB);
  static const Color brushedSilver = Color(0xFF9CA3AF);

  // Balões de Mensagem Monocromáticos / Elevados
  static const Color messageReceived = Color(0xFF101015);
  static const Color messageSent = Color(0xFF1C1C24);
  static const Color messageHighlight = Color(0xFF282833);

  // Tipografia (Especificação V2: #FFFFFF e #B8B8C2)
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB8B8C2);      // Texto secundário V2
  static const Color textMuted = Color(0x80FFFFFF);          // 50% opacidade
  static const Color textDim = Color(0x59FFFFFF);            // 35% opacidade
  static const Color textDisabled = Color(0x38FFFFFF);       // 22% opacidade

  // Ícones
  static const Color iconPrimary = Color(0xFFFFFFFF);
  static const Color iconSecondary = Color(0xFFB8B8C2);
  static const Color iconMuted = Color(0x73FFFFFF);

  // Cores Semânticas de Segurança (NUNCA alteradas por temas decorativos)
  // Modelo de Confiança em Três Níveis (Nix Trust Levels):
  static const Color trustLevel1Red = Color(0xFFEF4444);     // Nível 1: Não verificado / Externo
  static const Color trustLevel2Yellow = Color(0xFFF59E0B);  // Nível 2: Contexto de espaço compartilhado
  static const Color trustLevel3Green = Color(0xFF10B981);   // Nível 3: Verificado diretamente por chave / QR
  static const Color trustBadgeVerified = Color(0xFF10B981); // Distintivo de verificação criptográfica
  static const Color securityShield = Color(0xFF10B981);

  // Acentos Padrão (Nix Original)
  static const Color accentPrimary = Color(0xFFFFFFFF);
  static const Color accentSecondary = Color(0xFFE5E7EB);
  static const Color accentSubtle = Color(0xFF9CA3AF);
  static const Color accentDanger = Color(0xFFEF4444);

  // Aliases legados preservando compatibilidade
  static const Color accentGreen = Color(0xFF10B981);
  static const Color accentCyan = Color(0xFF0EA5E9);
  static const Color accentTor = Color(0xFFE5E7EB);
  static const Color accentVoice = Color(0xFFFFFFFF);
  static const Color accentPublication = Color(0xFFD4D4D8);
  static const Color accentWarning = Color(0xFFF59E0B);
}
