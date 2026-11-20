import '../models/cultural_item.dart';
import 'catalog_database.dart';

CulturalItem culturalItemFromCatalog(CatalogWork work) {
  final category = switch (work.kind) {
    'series' => CulturalCategory.series,
    'anime' => CulturalCategory.anime,
    'manga' => CulturalCategory.manga,
    'book' => CulturalCategory.books,
    'music' || 'album' || 'track' => CulturalCategory.music,
    _ => CulturalCategory.movies,
  };
  final thumb = work.coverThumb;
  return CulturalItem(
    id: 'catalog:${work.id}',
    title: work.title,
    creatorOrYear: [
      if (work.creators case final creators? when creators.isNotEmpty) creators,
      if (work.kind == 'track' && work.originalTitle != null) work.originalTitle!,
      if (work.releaseYear case final year?) '$year',
    ].join(' · '),
    category: category,
    monogram: String.fromCharCodes(work.title.runes.take(2)).toUpperCase(),
    coverMotif:
        thumb != null && thumb.startsWith('placeholder:') && thumb.length < 100
            ? thumb
            : null,
    isPublicInCardId: false,
  );
}

