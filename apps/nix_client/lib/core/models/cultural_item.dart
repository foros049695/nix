enum CulturalCategory {
  movies,
  series,
  anime,
  manga,
  books,
  music, // Exibido como disco de vinil com arte central
}

extension CulturalCategoryLabel on CulturalCategory {
  String get label {
    switch (this) {
      case CulturalCategory.movies:
        return 'Filmes';
      case CulturalCategory.series:
        return 'Séries';
      case CulturalCategory.anime:
        return 'Animes';
      case CulturalCategory.manga:
        return 'Mangás';
      case CulturalCategory.books:
        return 'Livros';
      case CulturalCategory.music:
        return 'Álbuns Musicais';
    }
  }
}

class CulturalItem {
  final String id;
  final String title;
  final String creatorOrYear;
  final CulturalCategory category;
  final String rating;
  final String monogram;
  final int toneShade; // 0-255 tom monocromático para arte de capa / selo de vinil
  final bool isFeatured;

  const CulturalItem({
    required this.id,
    required this.title,
    required this.creatorOrYear,
    required this.category,
    this.rating = '9.5',
    required this.monogram,
    this.toneShade = 42,
    this.isFeatured = false,
  });

  bool get isVinyl => category == CulturalCategory.music;
}
