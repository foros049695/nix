import 'package:flutter/material.dart';

/// Paleta de cores tática, ultra-escura e compatível com painéis OLED do Projeto Nix.
class NixColors {
  // Fundos e Superfícies
  static const Color background = Color(0xFF0C0D0E);       // Fundo mestre quase preto
  static const Color surfaceSidebar = Color(0xFF131416);  // Barra lateral de canais e espaços
  static const Color surfaceDock = Color(0xFF0A0B0C);     // Dock ultra-escuro de servidores/espaços
  static const Color surfaceCard = Color(0xFF191B1F);     // Cartões, inputs e balões
  static const Color surfaceCardHover = Color(0xFF22252A);
  static const Color surfaceBorder = Color(0xFF282C34);   // Bordas sutis
  static const Color surfaceDivider = Color(0xFF1E2126);

  // Balões de Mensagem (Inspirados no Telegram Dark + Discord)
  static const Color messageReceived = Color(0xFF1A1C20);
  static const Color messageSent = Color(0xFF1C2C24);     // Verde militar sutil e discreto
  static const Color messageHighlight = Color(0xFF23352A);

  // Cores de Acento e Status
  static const Color accentGreen = Color(0xFF00E676);     // Sucesso / Criptografia Verificada
  static const Color accentCyan = Color(0xFF00B0FF);      // Links / Canais de Texto
  static const Color accentTor = Color(0xFFA855F7);       // Tor Onion / Privacidade Avançada
  static const Color accentVoice = Color(0xFF10B981);     // Canais de Call / Voz Ativa
  static const Color accentPublication = Color(0xFFF59E0B);// Nix Archive / Dossiês
  static const Color accentWarning = Color(0xFFFFB300);   // Alertas
  static const Color accentDanger = Color(0xFFFF5252);    // Desconectar / Erro / PIN Coação

  // Tipografia
  static const Color textPrimary = Color(0xFFF3F4F6);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color textDim = Color(0xFF4B5563);
}
