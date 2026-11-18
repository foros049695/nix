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
  });

  String get fullName => '$owner/$name';

  String get formattedStars {
    if (starsCount >= 1000) {
      return '${(starsCount / 1000).toStringAsFixed(1)}k';
    }
    return starsCount.toString();
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
    );
  }
}
