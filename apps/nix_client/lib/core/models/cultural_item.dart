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

  // BookManager & Kavita/Komga integration fields
  final String? format; // 'cbz', 'cbr', 'epub', 'pdf', 'mobi', 'azw3'
  final int? totalVolumes;
  final int? currentVolume;
  final List<int> ownedVolumes;
  final int? totalChapters;
  final int? currentChapter;
  final Map<String, dynamic> comicInfo;
  final String? kavitaSeriesId;
  final String? komgaSeriesId;
  final String? readingDirection; // 'ltr', 'rtl', 'vertical'

  const CulturalItem({
    required this.id,
    required this.title,
    required this.creatorOrYear,
    required this.category,
    this.rating = '',
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
    this.format,
    this.totalVolumes,
    this.currentVolume,
    this.ownedVolumes = const [],
    this.totalChapters,
    this.currentChapter,
    this.comicInfo = const {},
    this.kavitaSeriesId,
    this.komgaSeriesId,
    this.readingDirection,
  });

  bool get isVinyl => category == CulturalCategory.music;
  bool get isGithubRepo => category == CulturalCategory.github;
  bool get isBookOrManga => category == CulturalCategory.books || category == CulturalCategory.manga;

  /// Lista de volumes faltantes para completar a coleção (estilo BookManager / Kavita / Komga)
  List<int> get missingVolumes {
    if (totalVolumes == null || totalVolumes! <= 0) return const [];
    final maxV = totalVolumes!;
    final owned = ownedVolumes.isNotEmpty
        ? ownedVolumes.toSet()
        : (currentVolume != null && currentVolume! > 0
            ? List.generate(currentVolume!, (i) => i + 1).toSet()
            : <int>{});
    final missing = <int>[];
    for (int v = 1; v <= maxV; v++) {
      if (!owned.contains(v)) {
        missing.add(v);
      }
    }
    return missing;
  }

  /// Resumo textual de volumes ausentes (ex: 'Faltam: Vol. 3, 5' ou 'Coleção completa')
  String get missingVolumesSummary {
    if (totalVolumes == null || totalVolumes! <= 0) return '';
    final missing = missingVolumes;
    if (missing.isEmpty) return 'Coleção completa';
    if (missing.length <= 4) {
      return 'Faltam: Vol. ${missing.join(', ')}';
    }
    return 'Faltam ${missing.length} volumes';
  }

  /// Indica se a obra possui metadados suficientes para exportação / biblioteca Kavita ou Komga
  bool get isKavitaKomgaReady =>
      (format != null && format!.isNotEmpty) ||
      comicInfo.isNotEmpty ||
      (kavitaSeriesId != null || komgaSeriesId != null);

  /// Distintivo de formato do arquivo ou mídia (ex: CBZ, CBR, EPUB, PDF)
  String get formatBadge {
    if (format != null && format!.trim().isNotEmpty) {
      return format!.trim().toUpperCase();
    }
    if (category == CulturalCategory.manga) return 'MANGÁ';
    if (category == CulturalCategory.books) return 'LIVRO';
    return category.label.toUpperCase();
  }

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
    String? format,
    int? totalVolumes,
    int? currentVolume,
    List<int>? ownedVolumes,
    int? totalChapters,
    int? currentChapter,
    Map<String, dynamic>? comicInfo,
    String? kavitaSeriesId,
    String? komgaSeriesId,
    String? readingDirection,
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
      format: format ?? this.format,
      totalVolumes: totalVolumes ?? this.totalVolumes,
      currentVolume: currentVolume ?? this.currentVolume,
      ownedVolumes: ownedVolumes ?? this.ownedVolumes,
      totalChapters: totalChapters ?? this.totalChapters,
      currentChapter: currentChapter ?? this.currentChapter,
      comicInfo: comicInfo ?? this.comicInfo,
      kavitaSeriesId: kavitaSeriesId ?? this.kavitaSeriesId,
      komgaSeriesId: komgaSeriesId ?? this.komgaSeriesId,
      readingDirection: readingDirection ?? this.readingDirection,
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
      if (format != null) 'format': format,
      if (totalVolumes != null) 'totalVolumes': totalVolumes,
      if (currentVolume != null) 'currentVolume': currentVolume,
      if (ownedVolumes.isNotEmpty) 'ownedVolumes': ownedVolumes,
      if (totalChapters != null) 'totalChapters': totalChapters,
      if (currentChapter != null) 'currentChapter': currentChapter,
      if (comicInfo.isNotEmpty) 'comicInfo': comicInfo,
      if (kavitaSeriesId != null) 'kavitaSeriesId': kavitaSeriesId,
      if (komgaSeriesId != null) 'komgaSeriesId': komgaSeriesId,
      if (readingDirection != null) 'readingDirection': readingDirection,
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
      format: json['format'] as String?,
      totalVolumes: (json['totalVolumes'] as num?)?.toInt(),
      currentVolume: (json['currentVolume'] as num?)?.toInt(),
      ownedVolumes: (json['ownedVolumes'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? const [],
      totalChapters: (json['totalChapters'] as num?)?.toInt(),
      currentChapter: (json['currentChapter'] as num?)?.toInt(),
      comicInfo: json['comicInfo'] is Map<String, dynamic> ? json['comicInfo'] as Map<String, dynamic> : const {},
      kavitaSeriesId: json['kavitaSeriesId'] as String?,
      komgaSeriesId: json['komgaSeriesId'] as String?,
      readingDirection: json['readingDirection'] as String?,
    );
  }
}
