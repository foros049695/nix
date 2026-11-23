import 'package:flutter/material.dart' show Color;

enum PagerCaseColor {
  violet('Violeta original', 0xFF4A3469),
  emerald('Verde esmeralda', 0xFF194A3D),
  onyx('Preto ônix', 0xFF1E1E24),
  slate('Cinza ardósia', 0xFF353D45),
  amber('Âmbar quente', 0xFF69431E),
  ruby('Vermelho rubi', 0xFF5C1E2A),
  sapphire('Azul safira', 0xFF1E335C),
  cobalt('Azul cobalto', 0xFF152A4A),
  graphite('Grafite escuro', 0xFF2A2D32),
  silver('Prata fosco', 0xFF4D535A),
  coral('Coral queimado', 0xFF5E2B20),
  pine('Verde pinho', 0xFF1B3A28),
  plum('Ameixa escuro', 0xFF3E1E42),
  copper('Cobre envelhecido', 0xFF52331C),
  jade('Jade', 0xFF2A5C4A);

  const PagerCaseColor(this.label, this.rgb);

  final String label;
  final int rgb;

  static PagerCaseColor read(Object? value) => values.firstWhere(
        (color) => color.name == value,
        orElse: () => violet,
      );
}

enum PagerLcdColor {
  cyan('Ciano', 0xFFAEE9ED),
  lime('Lima', 0xFFD8ED92),
  amber('Âmbar', 0xFFFFDC9F),
  pearl('Pérola', 0xFFF3EEE7),
  lilac('Lilás', 0xFFE4D5FA),
  rose('Rosa', 0xFFF7CDDC),
  mint('Menta', 0xFFBDEADC),
  peach('Pêssego', 0xFFF9CBAC),
  lavender('Lavanda azul', 0xFFCBD8FC),
  sunset('Pôr do sol', 0xFFFFBEA6),
  ivory('Marfim', 0xFFFAEEC3),
  frost('Gelo azulado', 0xFFDEF6FF),
  pistachio('Pistache', 0xFFE4ECAF),
  black('Preto', 0xFF0D0D0E); // Visor preto com alto contraste (Seção 12)

  const PagerLcdColor(this.label, this.rgb);

  final String label;
  final int rgb;

  bool get isBlack => this == black;
  Color get inkColor => isBlack ? const Color(0xFFF1F5F9) : const Color(0xFF10262D);
  Color get surfaceColor => Color(rgb);

  static PagerLcdColor read(Object? value) => values.firstWhere(
        (color) => color.name == value,
        orElse: () => cyan,
      );
}
