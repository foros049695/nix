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
    (CulturalStage.planned, CulturalCategory.movies || CulturalCategory.series || CulturalCategory.anime) => 'Quero assistir',
    (CulturalStage.planned, CulturalCategory.books || CulturalCategory.manga) => 'Quero ler',
    (CulturalStage.planned, CulturalCategory.music) => 'Quero ouvir',
    (CulturalStage.planned, _) => 'Pretendo',

    (CulturalStage.active, CulturalCategory.movies || CulturalCategory.series || CulturalCategory.anime) => 'Assistindo',
    (CulturalStage.active, CulturalCategory.books || CulturalCategory.manga) => 'Lendo',
    (CulturalStage.active, CulturalCategory.music) => 'Ouvindo',
    (CulturalStage.active, _) => 'Em andamento',

    (CulturalStage.paused, _) => 'Em pausa',

    (CulturalStage.finished, CulturalCategory.movies) => 'Assistido',
    (CulturalStage.finished, CulturalCategory.books) => 'Lido',
    (CulturalStage.finished, _) => 'Concluído',

    (CulturalStage.dropped, _) => 'Abandonado',

    (CulturalStage.revisiting, CulturalCategory.movies || CulturalCategory.series || CulturalCategory.anime) => 'Reassistindo',
    (CulturalStage.revisiting, CulturalCategory.books || CulturalCategory.manga) => 'Relendo',
    (CulturalStage.revisiting, CulturalCategory.music) => 'Ouvindo novamente',
    (CulturalStage.revisiting, _) => 'Revisitando',
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

  // Novos campos para metadados reais, proveniência e ficha técnica rica (Seção 5, 6, 10)
  final String? originalTitle;
  final String? creator;
  final int? releaseYear;
  final String? synopsis;
  final List<String> genres;
  final Map<String, dynamic> externalIds;
  final String? source; // 'manual', 'catalog', 'wikidata', 'openlibrary', 'musicbrainz', 'csv_import', 'html_import'
  final String? provenanceConfidence; // 'exact_id', 'strong_attributes', 'ambiguous', 'not_found', 'manual'
  final String? bannerPath;
  final Map<String, String>? storeLinks;

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
    this.originalTitle,
    this.creator,
    this.releaseYear,
    this.synopsis,
    this.genres = const [],
    this.externalIds = const {},
    this.source,
    this.provenanceConfidence,
    this.bannerPath,
    this.storeLinks,
  });

  bool get isVinyl => category == CulturalCategory.music;
  bool get isGithubRepo => category == CulturalCategory.github;

  /// Formata os termos otimizados de busca para o Torrent Index conforme a Seção 6.1:
  /// - Filme: <Título> <Ano>
  /// - Série: <Título>
  /// - Anime: <Título original> (ou título principal)
  /// - Livro: <Título> <Autor>
  /// - Música: <Artista> <Título> ou <Artista> <Álbum>
  /// Preserva estritamente a privacidade: nenhuma avaliação, nota pessoal ou status de acompanhamento é exposto.
  String get torrentSearchQuery {
    switch (category) {
      case CulturalCategory.movies:
        if (releaseYear != null && releaseYear! > 1800) {
          return '$title $releaseYear'.trim();
        }
        return title.trim();
      case CulturalCategory.series:
        return title.trim();
      case CulturalCategory.anime:
        if (originalTitle != null && originalTitle!.trim().isNotEmpty) {
          return originalTitle!.trim();
        }
        return title.trim();
      case CulturalCategory.books:
      case CulturalCategory.manga:
        final author = creator?.trim();
        if (author != null && author.isNotEmpty) {
          return '$title $author'.trim();
        }
        return title.trim();
      case CulturalCategory.music:
        final artist = creator?.trim();
        if (artist != null && artist.isNotEmpty) {
          return '$artist $title'.trim();
        }
        return title.trim();
      case CulturalCategory.github:
        return title.trim();
    }
  }

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
    String? originalTitle,
    String? creator,
    int? releaseYear,
    String? synopsis,
    List<String>? genres,
    Map<String, dynamic>? externalIds,
    String? source,
    String? provenanceConfidence,
    String? bannerPath,
    Map<String, String>? storeLinks,
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
      originalTitle: originalTitle ?? this.originalTitle,
      creator: creator ?? this.creator,
      releaseYear: releaseYear ?? this.releaseYear,
      synopsis: synopsis ?? this.synopsis,
      genres: genres ?? this.genres,
      externalIds: externalIds ?? this.externalIds,
      source: source ?? this.source,
      provenanceConfidence: provenanceConfidence ?? this.provenanceConfidence,
      bannerPath: bannerPath ?? this.bannerPath,
      storeLinks: storeLinks ?? this.storeLinks,
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
      if (originalTitle != null) 'originalTitle': originalTitle,
      if (creator != null) 'creator': creator,
      if (releaseYear != null) 'releaseYear': releaseYear,
      if (synopsis != null) 'synopsis': synopsis,
      if (genres.isNotEmpty) 'genres': genres,
      if (externalIds.isNotEmpty) 'externalIds': externalIds,
      if (source != null) 'source': source,
      if (provenanceConfidence != null) 'provenanceConfidence': provenanceConfidence,
      if (bannerPath != null) 'bannerPath': bannerPath,
      if (storeLinks != null) 'storeLinks': storeLinks,
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
      rating: json['rating'] as String? ?? '',
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
      originalTitle: json['originalTitle'] as String?,
      creator: json['creator'] as String?,
      releaseYear: (json['releaseYear'] as num?)?.toInt(),
      synopsis: json['synopsis'] as String?,
      genres: (json['genres'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      externalIds: json['externalIds'] is Map<String, dynamic> ? json['externalIds'] as Map<String, dynamic> : const {},
      source: json['source'] as String?,
      provenanceConfidence: json['provenanceConfidence'] as String?,
      bannerPath: json['bannerPath'] as String?,
      storeLinks: json['storeLinks'] is Map ? (json['storeLinks'] as Map).cast<String, String>() : null,
    );
  }
}
