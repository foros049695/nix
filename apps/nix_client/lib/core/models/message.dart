class Message {
  final String id;
  final String channelId;
  final String senderName;
  final String senderFingerprint;
  final bool isMe;
  final String text;
  final DateTime timestamp;
  final int ephemeralSeconds;
  final int remainingSeconds;
  final bool isVerified;
  final List<String> attachments;
  final Map<String, int> reactions;

  const Message({
    required this.id,
    required this.channelId,
    required this.senderName,
    required this.senderFingerprint,
    required this.isMe,
    required this.text,
    required this.timestamp,
    this.ephemeralSeconds = 0,
    this.remainingSeconds = 0,
    this.isVerified = true,
    this.attachments = const [],
    this.reactions = const {},
  });

  bool get isEphemeral => ephemeralSeconds > 0;

  Message copyWith({
    Map<String, int>? reactions,
  }) {
    return Message(
      id: id,
      channelId: channelId,
      senderName: senderName,
      senderFingerprint: senderFingerprint,
      isMe: isMe,
      text: text,
      timestamp: timestamp,
      ephemeralSeconds: ephemeralSeconds,
      remainingSeconds: remainingSeconds,
      isVerified: isVerified,
      attachments: attachments,
      reactions: reactions ?? this.reactions,
    );
  }
}
