class Message {
  final String id;
  final String channelId;
  final String senderName;
  final String senderFingerprint;
  final bool isMe;
  final String text;
  final DateTime timestamp;
  final DateTime? editedAt;
  final int ephemeralSeconds;
  final int remainingSeconds;
  final bool isVerified;
  final bool isPinned;
  final String? replyToMessageId;
  final String? replyToSenderName;
  final String? replyToExcerpt;
  final String? forwardedFrom;
  final List<String> attachments;
  final Map<String, int> reactions;
  final Set<String> myReactions;
  final String deliveryState;
  final String? deliveryError;

  const Message({
    required this.id,
    required this.channelId,
    required this.senderName,
    required this.senderFingerprint,
    required this.isMe,
    required this.text,
    required this.timestamp,
    this.editedAt,
    this.ephemeralSeconds = 0,
    this.remainingSeconds = 0,
    this.isVerified = true,
    this.isPinned = false,
    this.replyToMessageId,
    this.replyToSenderName,
    this.replyToExcerpt,
    this.forwardedFrom,
    this.attachments = const [],
    this.reactions = const {},
    this.myReactions = const {},
    this.deliveryState = 'queued',
    this.deliveryError,
  });

  bool get isEphemeral => ephemeralSeconds > 0;
  bool get isEdited => editedAt != null;

  Message copyWith({
    String? text,
    DateTime? editedAt,
    bool? isVerified,
    bool? isPinned,
    String? replyToMessageId,
    String? replyToSenderName,
    String? replyToExcerpt,
    String? forwardedFrom,
    List<String>? attachments,
    Map<String, int>? reactions,
    Set<String>? myReactions,
    String? deliveryState,
    String? deliveryError,
    bool clearDeliveryError = false,
  }) {
    return Message(
      id: id,
      channelId: channelId,
      senderName: senderName,
      senderFingerprint: senderFingerprint,
      isMe: isMe,
      text: text ?? this.text,
      timestamp: timestamp,
      editedAt: editedAt ?? this.editedAt,
      ephemeralSeconds: ephemeralSeconds,
      remainingSeconds: remainingSeconds,
      isVerified: isVerified ?? this.isVerified,
      isPinned: isPinned ?? this.isPinned,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      replyToExcerpt: replyToExcerpt ?? this.replyToExcerpt,
      forwardedFrom: forwardedFrom ?? this.forwardedFrom,
      attachments: attachments ?? this.attachments,
      reactions: reactions ?? this.reactions,
      myReactions: myReactions ?? this.myReactions,
      deliveryState: deliveryState ?? this.deliveryState,
      deliveryError: clearDeliveryError ? null : (deliveryError ?? this.deliveryError),
    );
  }
}
