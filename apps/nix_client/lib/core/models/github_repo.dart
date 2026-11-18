class GithubRepository {
  final String id;
  final String name;
  final String owner;
  final String description;
  final String language;
  final int starsCount;
  final int forksCount;
  final String license;
  final List<String> topics;
  final DateTime updatedDate;
  final String htmlUrl;
  final bool isSavedInAcervo;
  final String category;
  final String area;
  final int starsThisWeek;
  final int starsWhenPicked;
  final bool isTrending;

  const GithubRepository({
    required this.id,
    required this.name,
    required this.owner,
    required this.description,
    required this.language,
    required this.starsCount,
    this.forksCount = 0,
    required this.license,
    required this.topics,
    required this.updatedDate,
    required this.htmlUrl,
    this.isSavedInAcervo = false,
    this.category = 'Open Source',
    this.area = 'dev',
    this.starsThisWeek = 0,
    this.starsWhenPicked = 0,
    this.isTrending = false,
  });

  String get fullName => '$owner/$name';

  String get formattedStars {
    if (starsCount >= 1000) {
      return '${(starsCount / 1000).toStringAsFixed(1)}k';
    }
    return starsCount.toString();
  }

  factory GithubRepository.fromStarwireJson(Map<String, dynamic> json) {
    final rawRepo = (json['repo'] as String? ?? '').trim();
    final parts = rawRepo.split('/');
    final owner = parts.isNotEmpty ? parts[0] : 'github';
    final name = parts.length > 1 ? parts[1] : (rawRepo.isNotEmpty ? rawRepo : 'repo');
    final id = 'starwire_${owner}_$name'.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');

    final rawTopics = <String>[];
    if (json['topics'] is List) {
      rawTopics.addAll((json['topics'] as List).map((e) => e.toString()));
    }
    if (json['tags'] is List) {
      for (final t in json['tags'] as List) {
        final str = t.toString();
        if (!rawTopics.contains(str)) rawTopics.add(str);
      }
    }

    DateTime updated = DateTime.now();
    if (json['pushedAt'] != null) {
      try {
        updated = DateTime.parse(json['pushedAt'].toString());
      } catch (_) {}
    }

    return GithubRepository(
      id: id,
      name: name,
      owner: owner,
      description: (json['description'] as String?) ?? (json['line'] as String?) ?? '',
      language: (json['language'] as String?) ?? 'Markdown',
      starsCount: (json['stars'] as num?)?.toInt() ?? 0,
      forksCount: (json['forks'] as num?)?.toInt() ?? 0,
      license: (json['license'] as String?) ?? 'Open Source',
      topics: rawTopics,
      updatedDate: updated,
      htmlUrl: (json['url'] as String?) ?? 'https://github.com/$owner/$name',
      category: (json['category'] as String?) ?? 'Developer Tools',
      area: (json['area'] as String?) ?? 'dev',
      starsThisWeek: (json['starsThisWeek'] as num?)?.toInt() ?? 0,
      starsWhenPicked: (json['starsWhenPicked'] as num?)?.toInt() ?? 0,
      isTrending: (json['trending'] as bool?) ?? false,
    );
  }

  GithubRepository copyWith({
    String? id,
    String? name,
    String? owner,
    String? description,
    String? language,
    int? starsCount,
    int? forksCount,
    String? license,
    List<String>? topics,
    DateTime? updatedDate,
    String? htmlUrl,
    bool? isSavedInAcervo,
    String? category,
    String? area,
    int? starsThisWeek,
    int? starsWhenPicked,
    bool? isTrending,
  }) {
    return GithubRepository(
      id: id ?? this.id,
      name: name ?? this.name,
      owner: owner ?? this.owner,
      description: description ?? this.description,
      language: language ?? this.language,
      starsCount: starsCount ?? this.starsCount,
      forksCount: forksCount ?? this.forksCount,
      license: license ?? this.license,
      topics: topics ?? this.topics,
      updatedDate: updatedDate ?? this.updatedDate,
      htmlUrl: htmlUrl ?? this.htmlUrl,
      isSavedInAcervo: isSavedInAcervo ?? this.isSavedInAcervo,
      category: category ?? this.category,
      area: area ?? this.area,
      starsThisWeek: starsThisWeek ?? this.starsThisWeek,
      starsWhenPicked: starsWhenPicked ?? this.starsWhenPicked,
      isTrending: isTrending ?? this.isTrending,
    );
  }
}
