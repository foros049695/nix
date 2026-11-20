enum PagerCaseColor {
  violet('Roxo original', 0xFF7F699D),
  graphite('Grafite', 0xFF575A66),
  silver('Prata', 0xFFA6A7AE),
  navy('Azul-marinho', 0xFF4F6A99),
  jade('Jade', 0xFF4C836F),
  burgundy('Vinho', 0xFF9A526C),
  bronze('Bronze', 0xFF9E7554),
  copper('Cobre', 0xFFBC7057),
  midnight('Meia-noite', 0xFF504365),
  champagne('Champanhe', 0xFFAF9A71),
  coral('Coral', 0xFFBD697C),
  ice('Gelo', 0xFF7698AD);

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
  pistachio('Pistache', 0xFFE4ECAF);

  const PagerLcdColor(this.label, this.rgb);

  final String label;
  final int rgb;

  static PagerLcdColor read(Object? value) => values.firstWhere(
        (color) => color.name == value,
        orElse: () => cyan,
      );
}
