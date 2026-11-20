import 'cultural_tracking.dart';

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
  String? get progressUnit => switch (this) {
    CulturalCategory.books => 'Páginas',
    CulturalCategory.series || CulturalCategory.anime => 'Episódios',
    CulturalCategory.manga => 'Capítulos',
    CulturalCategory.music => 'Faixas',
    _ => null,
  };

  String? get sequenceLabel => switch (this) {
    CulturalCategory.series || CulturalCategory.anime => 'Temporada',
    CulturalCategory.manga => 'Volume',
    _ => null,
  };

  String trackingLabel(CulturalStage stage) => switch ((stage, this)) {
    (CulturalStage.active, CulturalCategory.books || CulturalCategory.manga) => 'Lendo',
    (CulturalStage.active, CulturalCategory.music) => 'Ouvindo',
    (CulturalStage.active, CulturalCategory.movies || CulturalCategory.series || CulturalCategory.anime) => 'Assistindo',
    (CulturalStage.revisiting, CulturalCategory.books || CulturalCategory.manga) => 'Relendo',
    (CulturalStage.revisiting, CulturalCategory.music) => 'Ouvindo novamente',
    (CulturalStage.revisiting, CulturalCategory.movies || CulturalCategory.series || CulturalCategory.anime) => 'Reassistindo',
    _ => stage.label,
  };

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
  final String? coverMotif;
  final double cropScale;
  final bool isPublicInCardId;
  final String? repositoryUrl;
  final int? starsCount;
  final String? language;
  final String? license;
  final DateTime? updatedDate;
  final CulturalTracking tracking;

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
    this.coverMotif,
    this.cropScale = 1.0,
    this.isPublicInCardId = true,
    this.repositoryUrl,
    this.starsCount,
    this.language,
    this.license,
    this.updatedDate,
    this.tracking = const CulturalTracking(),
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
    String? coverMotif,
    bool clearLocalImage = false,
    double? cropScale,
    bool? isPublicInCardId,
    String? repositoryUrl,
    int? starsCount,
    String? language,
    String? license,
    DateTime? updatedDate,
    CulturalTracking? tracking,
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
      coverMotif: coverMotif ?? this.coverMotif,
      cropScale: cropScale ?? this.cropScale,
      isPublicInCardId: isPublicInCardId ?? this.isPublicInCardId,
      repositoryUrl: repositoryUrl ?? this.repositoryUrl,
      starsCount: starsCount ?? this.starsCount,
      language: language ?? this.language,
      license: license ?? this.license,
      updatedDate: updatedDate ?? this.updatedDate,
      tracking: tracking ?? this.tracking,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tracking': tracking.toJson(),
      'id': id,
      'title': title,
      'creatorOrYear': creatorOrYear,
      'category': category.name,
      'rating': rating,
      'monogram': monogram,
      'toneShade': toneShade,
      'isFeatured': isFeatured,
      'localImagePath': localImagePath,
      'coverMotif': coverMotif,
      'cropScale': cropScale,
      'isPublicInCardId': isPublicInCardId,
      'repositoryUrl': repositoryUrl,
      'starsCount': starsCount,
      'language': language,
      'license': license,
      'updatedDate': updatedDate?.toIso8601String(),
    };
  }

  factory CulturalItem.fromJson(Map<String, dynamic> json) {
    CulturalCategory cat = CulturalCategory.movies;
    if (json['category'] != null) {
      cat = CulturalCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => CulturalCategory.movies,
      );
    }
    return CulturalItem(
      id: json['id'] as String? ?? 'cult_${DateTime.now().millisecondsSinceEpoch}',
      title: json['title'] as String? ?? '',
      creatorOrYear: json['creatorOrYear'] as String? ?? '',
      tracking: json['tracking'] is Map<String, dynamic>
          ? CulturalTracking.fromJson(json['tracking'] as Map<String, dynamic>)
          : const CulturalTracking(),
      category: cat,
      rating: json['rating'] as String? ?? '9.5',
      monogram: json['monogram'] as String? ?? 'NX',
      toneShade: json['toneShade'] as int? ?? 42,
      isFeatured: json['isFeatured'] as bool? ?? false,
      localImagePath: json['localImagePath'] as String?,
      coverMotif: json['coverMotif'] as String?,
      cropScale: (json['cropScale'] as num?)?.toDouble() ?? 1.0,
      isPublicInCardId: json['isPublicInCardId'] as bool? ?? true,
      repositoryUrl: json['repositoryUrl'] as String?,
      starsCount: json['starsCount'] as int?,
      language: json['language'] as String?,
      license: json['license'] as String?,
      updatedDate: json['updatedDate'] != null ? DateTime.tryParse(json['updatedDate'] as String) : null,
    );
  }
}
