enum CulturalCategory {
  movies,
  series,
  anime,
  manga,
  books,
  music,  // Exibido como disco de vinil com arte central
  github, // Repositórios GitHub salvos no Acervo
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
      case CulturalCategory.github:
        return 'Repositórios GitHub';
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
  final String? localImagePath;
  final double cropScale;
  final bool isPublicInCardId;
  final String? repositoryUrl;
  final int? starsCount;
  final String? language;
  final String? license;
  final DateTime? updatedDate;

  const CulturalItem({
    required this.id,
    required this.title,
    required this.creatorOrYear,
    required this.category,
    this.rating = '9.5',
    required this.monogram,
    this.toneShade = 42,
    this.isFeatured = false,
    this.localImagePath,
    this.cropScale = 1.0,
    this.isPublicInCardId = true,
    this.repositoryUrl,
    this.starsCount,
    this.language,
    this.license,
    this.updatedDate,
  });

  bool get isVinyl => category == CulturalCategory.music;
  bool get isGithubRepo => category == CulturalCategory.github;

  CulturalItem copyWith({
    String? id,
    String? title,
    String? creatorOrYear,
    CulturalCategory? category,
    String? rating,
    String? monogram,
    int? toneShade,
    bool? isFeatured,
    String? localImagePath,
    bool clearLocalImage = false,
    double? cropScale,
    bool? isPublicInCardId,
    String? repositoryUrl,
    int? starsCount,
    String? language,
    String? license,
    DateTime? updatedDate,
  }) {
    return CulturalItem(
      id: id ?? this.id,
      title: title ?? this.title,
      creatorOrYear: creatorOrYear ?? this.creatorOrYear,
      category: category ?? this.category,
      rating: rating ?? this.rating,
      monogram: monogram ?? this.monogram,
      toneShade: toneShade ?? this.toneShade,
      isFeatured: isFeatured ?? this.isFeatured,
      localImagePath: clearLocalImage ? null : (localImagePath ?? this.localImagePath),
      cropScale: cropScale ?? this.cropScale,
      isPublicInCardId: isPublicInCardId ?? this.isPublicInCardId,
      repositoryUrl: repositoryUrl ?? this.repositoryUrl,
      starsCount: starsCount ?? this.starsCount,
      language: language ?? this.language,
      license: license ?? this.license,
      updatedDate: updatedDate ?? this.updatedDate,
    );
  }
}
