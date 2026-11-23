import 'package:flutter/material.dart';

enum NixNotificationType {
  message,
  mention,
  invite,
  contactRequest,
  topicReply,
  communityActivity,
  tradeUpdate,
}

extension NixNotificationTypeX on NixNotificationType {
  String get label => switch (this) {
        NixNotificationType.message => 'Mensagem',
        NixNotificationType.mention => 'Menção',
        NixNotificationType.invite => 'Convite',
        NixNotificationType.contactRequest => 'Solicitação',
        NixNotificationType.topicReply => 'Fórum',
        NixNotificationType.communityActivity => 'Comunidade',
        NixNotificationType.tradeUpdate => 'Mercado Cripto',
      };

  IconData get icon => switch (this) {
        NixNotificationType.message => Icons.chat_bubble_outline_rounded,
        NixNotificationType.mention => Icons.alternate_email_rounded,
        NixNotificationType.invite => Icons.mail_outline_rounded,
        NixNotificationType.contactRequest => Icons.person_add_outlined,
        NixNotificationType.topicReply => Icons.forum_outlined,
        NixNotificationType.communityActivity => Icons.groups_outlined,
        NixNotificationType.tradeUpdate => Icons.currency_exchange_rounded,
      };
}

class NixNotification {
  final String id;
  final NixNotificationType type;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool isRead;
  final String? targetArea; // 'homePrivate', 'spaces', 'moneroP2p', 'forum'
  final String? targetId;

  const NixNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
    this.targetArea,
    this.targetId,
  });

  NixNotification copyWith({
    String? id,
    NixNotificationType? type,
    String? title,
    String? body,
    DateTime? timestamp,
    bool? isRead,
    String? targetArea,
    String? targetId,
  }) {
    return NixNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      targetArea: targetArea ?? this.targetArea,
      targetId: targetId ?? this.targetId,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'title': title,
        'body': body,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'isRead': isRead,
        'targetArea': targetArea,
        'targetId': targetId,
      };

  factory NixNotification.fromMap(Map<String, dynamic> map) {
    return NixNotification(
      id: map['id'] as String,
      type: NixNotificationType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => NixNotificationType.message,
      ),
      title: map['title'] as String,
      body: map['body'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      isRead: map['isRead'] as bool? ?? false,
      targetArea: map['targetArea'] as String?,
      targetId: map['targetId'] as String?,
    );
  }
}
