class Message {
  final String id;
  final String channelId;
  final String senderName;
  final String senderFingerprint;
  final bool isMe;
  final String text;
  final DateTime timestamp;
  final int ephemeralSeconds; // 0 = sem auto-destruição
  final int remainingSeconds;
  final bool isVerified;
  final List<String> attachments;

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
  });

  bool get isEphemeral => ephemeralSeconds > 0;
}
