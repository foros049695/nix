import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/cultural_item.dart';
import '../models/cultural_tracking.dart';

enum CollectionSourceType {
  letterboxd,
  goodreads,
  myanimelist,
  genericCsv,
  genericHtml,
}

class ImportedItemPreview {
  final String id;
  final String title;
  final String creatorOrYear;
  final CulturalCategory category;
  final String rating;
  final CulturalStage stage;
  final int? current;
  final int? total;
  final String review;
  final List<String> tags;
  final bool isPotentialDuplicate;

  const ImportedItemPreview({
    required this.id,
    required this.title,
    required this.creatorOrYear,
    required this.category,
    required this.rating,
    required this.stage,
    this.current,
    this.total,
    this.review = '',
    this.tags = const [],
    this.isPotentialDuplicate = false,
  });

  CulturalItem toCulturalItem() {
    final monogram = title.isNotEmpty ? title.trim().substring(0, 1).toUpperCase() : '?';
    return CulturalItem(
      id: id,
      title: title,
      creatorOrYear: creatorOrYear,
      category: category,
      rating: rating,
      monogram: monogram,
      tracking: CulturalTracking(
        stage: stage,
        current: current,
        total: total,
        review: review,
        tags: tags,
      ),
    );
  }
}

class ImportedCollectionPreview {
  final CollectionSourceType sourceType;
  final String sourceLabel;
  final List<String> detectedColumns;
  final List<ImportedItemPreview> items;
  final int duplicateCount;

  const ImportedCollectionPreview({
    required this.sourceType,
    required this.sourceLabel,
    required this.detectedColumns,
    required this.items,
    required this.duplicateCount,
  });
}

class CollectionImporter {
  static const int maxFileSizeBytes = 10 * 1024 * 1024; // 10MB
  static const int maxRowsAllowed = 10000;

  /// Analisa o conteúdo CSV ou HTML local e gera uma pré-visualização segura
  /// com detecção de plataforma, mapeamento de campos e checagem de duplicatas.
  static ImportedCollectionPreview parse({
    required String rawContent,
    required String fileName,
    List<CulturalItem> existingItems = const [],
  }) {
    if (rawContent.length > maxFileSizeBytes) {
      throw const FormatException('O arquivo excede o limite máximo de segurança de 10 MB.');
    }

    final trimmed = rawContent.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('O arquivo de importação está vazio.');
    }

    final lowerName = fileName.toLowerCase();
    final isHtml = lowerName.endsWith('.html') || lowerName.endsWith('.htm') || trimmed.startsWith('<');

    if (isHtml) {
      return _parseHtml(trimmed, existingItems);
    } else {
      return _parseCsv(trimmed, existingItems);
    }
  }

  static ImportedCollectionPreview _parseCsv(String content, List<CulturalItem> existing) {
    final lines = _splitCsvLines(content);
    if (lines.isEmpty) {
      throw const FormatException('Nenhuma linha encontrada no CSV.');
    }

    final headers = lines.first.map((h) => h.trim()).toList();
    final headerLower = headers.map((h) => h.toLowerCase()).toList();

    // Identifica plataforma
    CollectionSourceType sourceType = CollectionSourceType.genericCsv;
    String sourceLabel = 'CSV Genérico';

    if (headerLower.contains('letterboxd uri') ||
        (headerLower.contains('name') && headerLower.contains('year') && headerLower.contains('rating'))) {
      sourceType = CollectionSourceType.letterboxd;
      sourceLabel = 'Letterboxd (CSV)';
    } else if (headerLower.contains('isbn') ||
        (headerLower.contains('title') && headerLower.contains('author') && headerLower.contains('bookshelves'))) {
      sourceType = CollectionSourceType.goodreads;
      sourceLabel = 'Goodreads (CSV)';
    } else if (headerLower.contains('series_title') || headerLower.contains('my_watched_episodes')) {
      sourceType = CollectionSourceType.myanimelist;
      sourceLabel = 'MyAnimeList (CSV)';
    }

    final existingTitles = existing.map((i) => i.title.trim().toLowerCase()).toSet();
    final items = <ImportedItemPreview>[];
    int dupCount = 0;

    for (var i = 1; i < lines.length && items.length < maxRowsAllowed; i++) {
      final row = lines[i];
      if (row.isEmpty || row.every((c) => c.trim().isEmpty)) continue;

      final rowMap = <String, String>{};
      for (var col = 0; col < headers.length && col < row.length; col++) {
        rowMap[headerLower[col]] = row[col].trim();
      }

      ImportedItemPreview? item;
      switch (sourceType) {
        case CollectionSourceType.letterboxd:
          item = _mapLetterboxdRow(rowMap, existingTitles);
        case CollectionSourceType.goodreads:
          item = _mapGoodreadsRow(rowMap, existingTitles);
        case CollectionSourceType.myanimelist:
          item = _mapMalRow(rowMap, existingTitles);
        case CollectionSourceType.genericCsv:
        case CollectionSourceType.genericHtml:
          item = _mapGenericRow(rowMap, existingTitles);
      }

      if (item != null) {
        if (item.isPotentialDuplicate) dupCount++;
        items.add(item);
      }
    }

    return ImportedCollectionPreview(
      sourceType: sourceType,
      sourceLabel: sourceLabel,
      detectedColumns: headers,
      items: items,
      duplicateCount: dupCount,
    );
  }

  static ImportedCollectionPreview _parseHtml(String content, List<CulturalItem> existing) {
    // Sanitização segura contra scripts e entidades maliciosas
    final safeHtml = content
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '');

    // Verifica se é MyAnimeList XML/HTML export
    if (safeHtml.contains('<anime>') || safeHtml.contains('<series_title>')) {
      return _parseMalHtml(safeHtml, existing);
    }

    // Extrai tabela HTML
    final tableMatch = RegExp(r'<table[^>]*>([\s\S]*?)</table>', caseSensitive: false).firstMatch(safeHtml);
    if (tableMatch == null) {
      throw const FormatException('Nenhuma tabela de dados encontrada no arquivo HTML.');
    }

    final tableContent = tableMatch.group(1)!;
    final rowMatches = RegExp(r'<tr[^>]*>([\s\S]*?)</tr>', caseSensitive: false).allMatches(tableContent).toList();
    if (rowMatches.isEmpty) {
      throw const FormatException('Tabela HTML sem linhas válidas.');
    }

    // Extrai cabeçalhos
    final headerRow = rowMatches.first.group(1)!;
    final headerCells = RegExp(r'<th[^>]*>([\s\S]*?)</th>', caseSensitive: false).allMatches(headerRow).map((m) => _stripHtml(m.group(1)!)).toList();
    final columns = headerCells.isNotEmpty
        ? headerCells
        : RegExp(r'<td[^>]*>([\s\S]*?)</td>', caseSensitive: false).allMatches(headerRow).map((m) => _stripHtml(m.group(1)!)).toList();

    final headerLower = columns.map((c) => c.toLowerCase()).toList();
    final existingTitles = existing.map((i) => i.title.trim().toLowerCase()).toSet();
    final items = <ImportedItemPreview>[];
    int dupCount = 0;

    for (var i = 1; i < rowMatches.length && items.length < maxRowsAllowed; i++) {
      final cellMatches = RegExp(r'<td[^>]*>([\s\S]*?)</td>', caseSensitive: false).allMatches(rowMatches[i].group(1)!);
      final cells = cellMatches.map((m) => _stripHtml(m.group(1)!)).toList();
      if (cells.isEmpty) continue;

      final rowMap = <String, String>{};
      for (var col = 0; col < headerLower.length && col < cells.length; col++) {
        rowMap[headerLower[col]] = cells[col];
      }

      final item = _mapGenericRow(rowMap, existingTitles);
      if (item != null) {
        if (item.isPotentialDuplicate) dupCount++;
        items.add(item);
      }
    }

    return ImportedCollectionPreview(
      sourceType: CollectionSourceType.genericHtml,
      sourceLabel: 'HTML Local',
      detectedColumns: columns,
      items: items,
      duplicateCount: dupCount,
    );
  }

  static ImportedCollectionPreview _parseMalHtml(String content, List<CulturalItem> existing) {
    final existingTitles = existing.map((i) => i.title.trim().toLowerCase()).toSet();
    final animeBlocks = RegExp(r'<anime>([\s\S]*?)</anime>', caseSensitive: false).allMatches(content);
    final items = <ImportedItemPreview>[];
    int dupCount = 0;

    for (final match in animeBlocks) {
      if (items.length >= maxRowsAllowed) break;
      final block = match.group(1)!;

      final title = _extractTag(block, 'series_title');
      if (title.isEmpty) continue;

      final episodesWatched = int.tryParse(_extractTag(block, 'my_watched_episodes'));
      final totalEpisodes = int.tryParse(_extractTag(block, 'series_episodes'));
      final myScore = _extractTag(block, 'my_score');
      final myStatus = _extractTag(block, 'my_status').toLowerCase();

      final stage = switch (myStatus) {
        'completed' || '1' => CulturalStage.finished,
        'watching' || '2' => CulturalStage.active,
        'on-hold' || 'paused' || '3' => CulturalStage.paused,
        'dropped' || '4' => CulturalStage.dropped,
        'plan to watch' || '6' => CulturalStage.planned,
        _ => CulturalStage.finished,
      };

      final isDup = existingTitles.contains(title.toLowerCase());
      if (isDup) dupCount++;

      items.add(ImportedItemPreview(
        id: _generateImportId('mal', title),
        title: title,
        creatorOrYear: totalEpisodes != null && totalEpisodes > 0 ? '$totalEpisodes eps' : 'Anime',
        category: CulturalCategory.anime,
        rating: myScore.isNotEmpty && myScore != '0' ? myScore : '8.5',
        stage: stage,
        current: episodesWatched,
        total: totalEpisodes,
        isPotentialDuplicate: isDup,
      ));
    }

    return ImportedCollectionPreview(
      sourceType: CollectionSourceType.myanimelist,
      sourceLabel: 'MyAnimeList (XML/HTML)',
      detectedColumns: ['series_title', 'my_score', 'my_status', 'my_watched_episodes', 'series_episodes'],
      items: items,
      duplicateCount: dupCount,
    );
  }

  static ImportedItemPreview? _mapLetterboxdRow(Map<String, String> row, Set<String> existingTitles) {
    final title = row['name'] ?? row['title'] ?? '';
    if (title.isEmpty) return null;

    final year = row['year'] ?? '';
    final ratingStr = row['rating'] ?? '4.5';
    final parsedRating = double.tryParse(ratingStr) ?? 4.0;
    // Escala Letterboxd (0.5 a 5.0) para base 10
    final normalizedRating = (parsedRating <= 5.0 ? parsedRating * 2 : parsedRating).toStringAsFixed(1);

    final isDup = existingTitles.contains(title.toLowerCase());
    return ImportedItemPreview(
      id: _generateImportId('lbxd', '$title$year'),
      title: title,
      creatorOrYear: year.isNotEmpty ? year : 'Filme',
      category: CulturalCategory.movies,
      rating: normalizedRating,
      stage: CulturalStage.finished,
      review: row['review'] ?? row['rewatch'] ?? '',
      isPotentialDuplicate: isDup,
    );
  }

  static ImportedItemPreview? _mapGoodreadsRow(Map<String, String> row, Set<String> existingTitles) {
    final title = row['title'] ?? '';
    if (title.isEmpty) return null;

    final author = row['author'] ?? row['author l-f'] ?? '';
    final year = row['year published'] ?? row['original publication year'] ?? '';
    final creatorOrYear = [author, year].where((s) => s.isNotEmpty).join(' · ');

    final ratingStr = row['my rating'] ?? '5';
    final parsedRating = double.tryParse(ratingStr) ?? 4.0;
    final normalizedRating = (parsedRating <= 5.0 && parsedRating > 0 ? parsedRating * 2 : parsedRating).toStringAsFixed(1);

    final pages = int.tryParse(row['number of pages'] ?? '');
    final shelf = (row['bookshelves'] ?? row['exclusive shelf'] ?? '').toLowerCase();

    final stage = shelf.contains('currently-reading')
        ? CulturalStage.active
        : shelf.contains('to-read')
            ? CulturalStage.planned
            : CulturalStage.finished;

    final isDup = existingTitles.contains(title.toLowerCase());
    return ImportedItemPreview(
      id: _generateImportId('gr', '$title$author'),
      title: title,
      creatorOrYear: creatorOrYear.isNotEmpty ? creatorOrYear : 'Livro',
      category: CulturalCategory.books,
      rating: normalizedRating != '0.0' ? normalizedRating : '8.0',
      stage: stage,
      total: pages,
      review: row['my review'] ?? '',
      isPotentialDuplicate: isDup,
    );
  }

  static ImportedItemPreview? _mapMalRow(Map<String, String> row, Set<String> existingTitles) {
    final title = row['series_title'] ?? row['title'] ?? '';
    if (title.isEmpty) return null;

    final eps = int.tryParse(row['my_watched_episodes'] ?? '');
    final rating = row['my_score'] ?? '8.0';
    final status = (row['my_status'] ?? '').toLowerCase();

    final stage = status.contains('watching')
        ? CulturalStage.active
        : status.contains('plan')
            ? CulturalStage.planned
            : status.contains('drop')
                ? CulturalStage.dropped
                : CulturalStage.finished;

    final isDup = existingTitles.contains(title.toLowerCase());
    return ImportedItemPreview(
      id: _generateImportId('mal', title),
      title: title,
      creatorOrYear: 'Anime',
      category: CulturalCategory.anime,
      rating: rating != '0' ? rating : '8.0',
      stage: stage,
      current: eps,
      isPotentialDuplicate: isDup,
    );
  }

  static ImportedItemPreview? _mapGenericRow(Map<String, String> row, Set<String> existingTitles) {
    final titleKey = row.keys.firstWhere(
      (k) => k.contains('title') || k.contains('titulo') || k.contains('título') || k.contains('name') || k.contains('nome') || k.contains('obra'),
      orElse: () => '',
    );
    final title = titleKey.isNotEmpty ? row[titleKey]! : (row.values.isNotEmpty ? row.values.first : '');
    if (title.trim().isEmpty) return null;

    final creatorKey = row.keys.firstWhere(
      (k) => k.contains('author') || k.contains('autor') || k.contains('director') || k.contains('diretor') || k.contains('creator') || k.contains('artista'),
      orElse: () => '',
    );
    final creator = creatorKey.isNotEmpty ? row[creatorKey]! : '';

    final yearKey = row.keys.firstWhere((k) => k.contains('year') || k.contains('ano'), orElse: () => '');
    final year = yearKey.isNotEmpty ? row[yearKey]! : '';

    final creatorOrYear = [creator, year].where((s) => s.isNotEmpty).join(' · ');

    final catKey = row.keys.firstWhere((k) => k.contains('type') || k.contains('tipo') || k.contains('category') || k.contains('categoria') || k.contains('media'), orElse: () => '');
    final catVal = catKey.isNotEmpty ? row[catKey]!.toLowerCase() : '';

    final category = catVal.contains('book') || catVal.contains('livro')
        ? CulturalCategory.books
        : catVal.contains('manga') || catVal.contains('mangá')
            ? CulturalCategory.manga
            : catVal.contains('anime')
                ? CulturalCategory.anime
                : catVal.contains('series') || catVal.contains('série')
                    ? CulturalCategory.series
                    : catVal.contains('music') || catVal.contains('musica') || catVal.contains('álbum')
                        ? CulturalCategory.music
                        : CulturalCategory.movies;

    final ratingKey = row.keys.firstWhere((k) => k.contains('rating') || k.contains('nota') || k.contains('score'), orElse: () => '');
    final ratingVal = ratingKey.isNotEmpty ? row[ratingKey]! : '8.5';

    final reviewKey = row.keys.firstWhere((k) => k.contains('review') || k.contains('resenha') || k.contains('notes') || k.contains('comentário'), orElse: () => '');
    final reviewVal = reviewKey.isNotEmpty ? row[reviewKey]! : '';

    final isDup = existingTitles.contains(title.toLowerCase());
    return ImportedItemPreview(
      id: _generateImportId('gen', '$title$creatorOrYear'),
      title: title,
      creatorOrYear: creatorOrYear.isNotEmpty ? creatorOrYear : category.label,
      category: category,
      rating: ratingVal.isNotEmpty ? ratingVal : '8.5',
      stage: CulturalStage.finished,
      review: reviewVal,
      isPotentialDuplicate: isDup,
    );
  }

  static String _extractTag(String block, String tag) {
    final match = RegExp('<$tag>(.*?)</$tag>', caseSensitive: false).firstMatch(block);
    return match != null ? _stripHtml(match.group(1)!) : '';
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();
  }

  static String _generateImportId(String prefix, String seed) {
    final digest = sha256.convert(utf8.encode(seed)).toString().substring(0, 10);
    return 'imp_${prefix}_$digest';
  }

  static List<List<String>> _splitCsvLines(String text) {
    final rows = <List<String>>[];
    final currentField = StringBuffer();
    final currentRow = <String>[];
    bool inQuotes = false;

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '"') {
        if (inQuotes && i + 1 < text.length && text[i + 1] == '"') {
          currentField.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        currentRow.add(currentField.toString());
        currentField.clear();
      } else if ((char == '\n' || char == '\r') && !inQuotes) {
        if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
          i++;
        }
        currentRow.add(currentField.toString());
        currentField.clear();
        if (currentRow.any((c) => c.trim().isNotEmpty)) {
          rows.add(List.from(currentRow));
        }
        currentRow.clear();
      } else {
        currentField.write(char);
      }
    }

    if (currentField.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(currentField.toString());
      if (currentRow.any((c) => c.trim().isNotEmpty)) {
        rows.add(currentRow);
      }
    }

    return rows;
  }
}
