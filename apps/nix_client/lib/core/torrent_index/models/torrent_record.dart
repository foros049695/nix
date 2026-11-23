import 'dart:convert';

/// Categorias canônicas para obras e conteúdos indexados no Nix Torrent Index.
enum TorrentCategory {
  movies('movies', 'Filmes'),
  tv('tv', 'Séries'),
  anime('anime', 'Animes'),
  manga('manga', 'Mangás'),
  books('books', 'Livros'),
  games('games', 'Jogos'),
  software('software', 'Software'),
  music('music', 'Música'),
  other('other', 'Outros');

  final String slug;
  final String label;
  const TorrentCategory(this.slug, this.label);

  static TorrentCategory fromSlug(String? slug) {
    if (slug == null || slug.isEmpty) return TorrentCategory.other;
    final normalized = slug.trim().toLowerCase();
    for (final cat in TorrentCategory.values) {
      if (cat.slug == normalized || cat.label.toLowerCase() == normalized) {
        return cat;
      }
    }
    if (normalized.contains('movie') || normalized.contains('filme')) {
      return TorrentCategory.movies;
    }
    if (normalized.contains('tv') || normalized.contains('serie') || normalized.contains('show')) {
      return TorrentCategory.tv;
    }
    if (normalized.contains('anime')) return TorrentCategory.anime;
    if (normalized.contains('manga')) return TorrentCategory.manga;
    if (normalized.contains('book') || normalized.contains('livro') || normalized.contains('ebook')) {
      return TorrentCategory.books;
    }
    if (normalized.contains('game') || normalized.contains('jogo')) {
      return TorrentCategory.games;
    }
    if (normalized.contains('soft') || normalized.contains('app')) {
      return TorrentCategory.software;
    }
    if (normalized.contains('music') || normalized.contains('audio') || normalized.contains('musica')) {
      return TorrentCategory.music;
    }
    return TorrentCategory.other;
  }
}

/// Registro de proveniência de uma fonte específica para um torrent indexado.
/// Preserva o momento de observação e contagens reportadas sem inventar dados.
class TorrentSourceProvenance {
  final String sourceId;
  final String sourceName;
  final String? sourceUrl;
  final int? seeders;
  final int? leechers;
  final DateTime observedAt;

  const TorrentSourceProvenance({
    required this.sourceId,
    required this.sourceName,
    this.sourceUrl,
    this.seeders,
    this.leechers,
    required this.observedAt,
  });

  Map<String, dynamic> toMap() => {
    'sourceId': sourceId,
    'sourceName': sourceName,
    if (sourceUrl != null) 'sourceUrl': sourceUrl,
    if (seeders != null) 'seeders': seeders,
    if (leechers != null) 'leechers': leechers,
    'observedAt': observedAt.toIso8601String(),
  };

  factory TorrentSourceProvenance.fromMap(Map<String, dynamic> map) {
    return TorrentSourceProvenance(
      sourceId: map['sourceId'] as String? ?? 'unknown',
      sourceName: map['sourceName'] as String? ?? 'Desconhecida',
      sourceUrl: map['sourceUrl'] as String?,
      seeders: map['seeders'] as int?,
      leechers: map['leechers'] as int?,
      observedAt: DateTime.tryParse(map['observedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Modelo estruturado canônico para metadados de torrents indexados no Nix.
/// Regra inegociável: campos ausentes NUNCA são preenchidos com dados fictícios.
class TorrentIndexRecord {
  final String id;
  final String sourceId;
  final String sourceName;
  final String? sourceUrl;
  final String title;
  final String normalizedTitle;
  final TorrentCategory category;
  final String? subcategory;
  final int? sizeBytes;
  final DateTime? publicationDate;
  final String? infoHashV1;
  final String? infoHashV2;
  final String? magnetUri;
  final String? torrentFileUrl;
  final int? seeders;
  final int? leechers;
  final String? language;
  final String? description;
  final List<String> tags;
  final String? trustMetadata;
  final DateTime indexedAt;
  final DateTime lastSeenAt;
  final List<TorrentSourceProvenance> provenances;

  const TorrentIndexRecord({
    required this.id,
    required this.sourceId,
    required this.sourceName,
    this.sourceUrl,
    required this.title,
    required this.normalizedTitle,
    required this.category,
    this.subcategory,
    this.sizeBytes,
    this.publicationDate,
    this.infoHashV1,
    this.infoHashV2,
    this.magnetUri,
    this.torrentFileUrl,
    this.seeders,
    this.leechers,
    this.language,
    this.description,
    this.tags = const [],
    this.trustMetadata,
    required this.indexedAt,
    required this.lastSeenAt,
    this.provenances = const [],
  });

  /// Formatação legível do tamanho em bytes.
  String get formattedSize {
    if (sizeBytes == null || sizeBytes! <= 0) return 'Não informado';
    final bytes = sizeBytes!;
    if (bytes >= 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
    }
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  /// Formatação da data de publicação.
  String get formattedDate {
    if (publicationDate == null) return 'Não informada';
    final d = publicationDate!;
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year.toString();
    return '$day/$month/$year';
  }

  /// Informação segura do infoHash canônico.
  String? get canonicalHash => infoHashV1 ?? infoHashV2;

  TorrentIndexRecord copyWith({
    String? id,
    String? sourceId,
    String? sourceName,
    String? sourceUrl,
    String? title,
    String? normalizedTitle,
    TorrentCategory? category,
    String? subcategory,
    int? sizeBytes,
    DateTime? publicationDate,
    String? infoHashV1,
    String? infoHashV2,
    String? magnetUri,
    String? torrentFileUrl,
    int? seeders,
    int? leechers,
    String? language,
    String? description,
    List<String>? tags,
    String? trustMetadata,
    DateTime? indexedAt,
    DateTime? lastSeenAt,
    List<TorrentSourceProvenance>? provenances,
  }) {
    return TorrentIndexRecord(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      title: title ?? this.title,
      normalizedTitle: normalizedTitle ?? this.normalizedTitle,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      publicationDate: publicationDate ?? this.publicationDate,
      infoHashV1: infoHashV1 ?? this.infoHashV1,
      infoHashV2: infoHashV2 ?? this.infoHashV2,
      magnetUri: magnetUri ?? this.magnetUri,
      torrentFileUrl: torrentFileUrl ?? this.torrentFileUrl,
      seeders: seeders ?? this.seeders,
      leechers: leechers ?? this.leechers,
      language: language ?? this.language,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      trustMetadata: trustMetadata ?? this.trustMetadata,
      indexedAt: indexedAt ?? this.indexedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      provenances: provenances ?? this.provenances,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sourceId': sourceId,
      'sourceName': sourceName,
      if (sourceUrl != null) 'sourceUrl': sourceUrl,
      'title': title,
      'normalizedTitle': normalizedTitle,
      'category': category.slug,
      if (subcategory != null) 'subcategory': subcategory,
      if (sizeBytes != null) 'sizeBytes': sizeBytes,
      if (publicationDate != null) 'publicationDate': publicationDate!.toIso8601String(),
      if (infoHashV1 != null) 'infoHashV1': infoHashV1,
      if (infoHashV2 != null) 'infoHashV2': infoHashV2,
      if (magnetUri != null) 'magnetUri': magnetUri,
      if (torrentFileUrl != null) 'torrentFileUrl': torrentFileUrl,
      if (seeders != null) 'seeders': seeders,
      if (leechers != null) 'leechers': leechers,
      if (language != null) 'language': language,
      if (description != null) 'description': description,
      'tags': tags,
      if (trustMetadata != null) 'trustMetadata': trustMetadata,
      'indexedAt': indexedAt.toIso8601String(),
      'lastSeenAt': lastSeenAt.toIso8601String(),
      'provenances': provenances.map((p) => p.toMap()).toList(),
    };
  }

  factory TorrentIndexRecord.fromMap(Map<String, dynamic> map) {
    final rawProvenances = map['provenances'] as List<dynamic>? ?? const [];
    final provenances = rawProvenances
        .whereType<Map<String, dynamic>>()
        .map((m) => TorrentSourceProvenance.fromMap(m))
        .toList();

    final rawTags = map['tags'];
    List<String> tags = [];
    if (rawTags is List) {
      tags = rawTags.map((e) => e.toString()).toList();
    } else if (rawTags is String && rawTags.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTags);
        if (decoded is List) {
          tags = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {
        tags = rawTags.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
    }

    return TorrentIndexRecord(
      id: map['id'] as String? ?? (map['infoHashV1'] as String? ?? 'rec_${DateTime.now().microsecondsSinceEpoch}'),
      sourceId: map['sourceId'] as String? ?? 'unknown',
      sourceName: map['sourceName'] as String? ?? 'Desconhecida',
      sourceUrl: map['sourceUrl'] as String?,
      title: map['title'] as String? ?? 'Sem título',
      normalizedTitle: map['normalizedTitle'] as String? ?? (map['title'] as String? ?? 'Sem título'),
      category: TorrentCategory.fromSlug(map['category'] as String?),
      subcategory: map['subcategory'] as String?,
      sizeBytes: map['sizeBytes'] as int?,
      publicationDate: map['publicationDate'] != null
          ? DateTime.tryParse(map['publicationDate'] as String)
          : null,
      infoHashV1: map['infoHashV1'] as String?,
      infoHashV2: map['infoHashV2'] as String?,
      magnetUri: map['magnetUri'] as String?,
      torrentFileUrl: map['torrentFileUrl'] as String?,
      seeders: map['seeders'] as int?,
      leechers: map['leechers'] as int?,
      language: map['language'] as String?,
      description: map['description'] as String?,
      tags: tags,
      trustMetadata: map['trustMetadata'] as String?,
      indexedAt: DateTime.tryParse(map['indexedAt'] as String? ?? '') ?? DateTime.now(),
      lastSeenAt: DateTime.tryParse(map['lastSeenAt'] as String? ?? '') ?? DateTime.now(),
      provenances: provenances,
    );
  }
}
