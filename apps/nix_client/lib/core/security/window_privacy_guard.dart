import 'package:flutter/material.dart';

/// Mecanismo de Proteção contra Fingerprinting de Tela e Janela (Seção 7).
///
/// Padroniza e discretiza dimensões e densidade de pixels reportadas a contextos
/// controlados/remotos em múltiplos de buckets fixos (ex: 1152x720, 1024x640),
/// evitando que objetos externos infiram a resolução exata do monitor ou barras do SO.
///
/// Limite técnico documentado:
/// - Efetivo contra conteúdos em sandbox, plugins e renderizadores internos.
/// - Processos locais executando no mesmo sistema operacional com acesso ao servidor
///   gráfico (X11/Wayland) continuam capazes de consultar o hardware diretamente.
class WindowPrivacyGuard {
  static const Size defaultWindowSize = Size(1152, 720);
  static const Size minimumWindowSize = Size(800, 540);

  /// Arredonda uma dimensão real para o bucket padronizado mais próximo (múltiplos de 64px).
  static Size quantizeSize(Size rawSize) {
    final double qWidth = ((rawSize.width / 64.0).floor() * 64.0).clamp(640.0, 1920.0);
    final double qHeight = ((rawSize.height / 64.0).floor() * 64.0).clamp(480.0, 1080.0);
    return Size(qWidth, qHeight);
  }

  /// Retorna um MediaQueryData sanitizado para sub-árvores que renderizam conteúdos externos.
  static MediaQueryData sanitizedMediaQuery(
    MediaQueryData original, {
    required bool quantizeDimensions,
    required bool reducedMotion,
  }) {
    return original.copyWith(
      size: quantizeDimensions ? quantizeSize(original.size) : original.size,
      devicePixelRatio: quantizeDimensions ? 1.0 : original.devicePixelRatio,
      disableAnimations: reducedMotion || original.disableAnimations,
       accessibleNavigation: original.accessibleNavigation,
    );
  }
}
