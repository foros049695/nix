class ArchiveReaction {
  static const schema = 'nix.archive.reaction.v1';
  static const labels = {
    '👍': 'Gostei',
    '❤️': 'Amei',
    '💡': 'Informativo',
    '🤔': 'Me fez pensar',
    '👏': 'Aplausos',
  };
  static final _hex = RegExp(r'^[a-f0-9]{64}$');

  final String target;
  final String author;
  final int revision;
  final String? emoji;

  ArchiveReaction({
    required this.target,
    required this.author,
    required this.revision,
    required this.emoji,
  }) {
    if (!_hex.hasMatch(target) ||
        !_hex.hasMatch(author) ||
        revision < 1 ||
        revision > 0x7fffffff ||
        (emoji != null && !labels.containsKey(emoji))) {
      throw const FormatException('Reação do Archive inválida.');
    }
  }

  factory ArchiveReaction.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != schema ||
        json.length != 5 ||
        json['targetObjectHash'] is! String ||
        json['authorEd25519'] is! String ||
        json['revision'] is! int ||
        !json.containsKey('emoji') ||
        (json['emoji'] != null && json['emoji'] is! String)) {
      throw const FormatException('Reação do Archive inválida.');
    }
    return ArchiveReaction(
      target: json['targetObjectHash'] as String,
      author: json['authorEd25519'] as String,
      revision: json['revision'] as int,
      emoji: json['emoji'] as String?,
    );
  }

  Map<String, Object?> toJson() => {
        'schema': schema,
        'targetObjectHash': target,
        'authorEd25519': author,
        'revision': revision,
        'emoji': emoji,
      };
}
