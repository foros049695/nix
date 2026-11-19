class Publication {
  final String id;
  final String channelId;
  final String title;
  final String authorPersona;
  final String authorFingerprint;
  final String contentMarkdown;
  final int claimsCount;
  final int refutationsCount;
  final String cidHash;
  final DateTime publishedAt;
  final bool isVerifiedSignature;
  final String? supersedesHash;
  final List<String> claims;
  final List<String> refutationSummaries;

  const Publication({
    required this.id,
    required this.channelId,
    required this.title,
    required this.authorPersona,
    required this.authorFingerprint,
    required this.contentMarkdown,
    required this.claimsCount,
    required this.refutationsCount,
    required this.cidHash,
    required this.publishedAt,
    this.isVerifiedSignature = true,
    this.supersedesHash,
    this.claims = const [],
    this.refutationSummaries = const [],
  });

  Publication copyWith({
    String? id,
    String? channelId,
    String? title,
    String? authorPersona,
    String? authorFingerprint,
    String? contentMarkdown,
    int? claimsCount,
    int? refutationsCount,
    String? cidHash,
    DateTime? publishedAt,
    bool? isVerifiedSignature,
    String? supersedesHash,
    List<String>? claims,
    List<String>? refutationSummaries,
  }) {
    return Publication(
      id: id ?? this.id,
      channelId: channelId ?? this.channelId,
      title: title ?? this.title,
      authorPersona: authorPersona ?? this.authorPersona,
      authorFingerprint: authorFingerprint ?? this.authorFingerprint,
      contentMarkdown: contentMarkdown ?? this.contentMarkdown,
      claimsCount: claimsCount ?? this.claimsCount,
      refutationsCount: refutationsCount ?? this.refutationsCount,
      cidHash: cidHash ?? this.cidHash,
      publishedAt: publishedAt ?? this.publishedAt,
      isVerifiedSignature: isVerifiedSignature ?? this.isVerifiedSignature,
      supersedesHash: supersedesHash ?? this.supersedesHash,
      claims: claims ?? this.claims,
      refutationSummaries: refutationSummaries ?? this.refutationSummaries,
    );
  }
}
