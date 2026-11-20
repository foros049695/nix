enum PagerCaseColor {
  violet('Roxo original', 0xFF7F699D),
  graphite('Grafite', 0xFF575A66),
  silver('Prata', 0xFFA6A7AE),
  navy('Azul-marinho', 0xFF4F6A99),
  jade('Jade', 0xFF4C836F),
  burgundy('Vinho', 0xFF9A526C),
  bronze('Bronze', 0xFF9E7554);

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
  mint('Menta', 0xFFBDEADC);

  const PagerLcdColor(this.label, this.rgb);

  final String label;
  final int rgb;

  static PagerLcdColor read(Object? value) => values.firstWhere(
        (color) => color.name == value,
        orElse: () => cyan,
      );
}
