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
  });
}
