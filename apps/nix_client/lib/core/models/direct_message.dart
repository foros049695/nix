import 'message.dart';

enum HomeSubTab {
  cardId,       // Estado inicial vazio da Home -> preenchido pelo CARD ID
  friends,      // Amigos verificados
  requests,     // Solicitações de contato
  transactions, // Transações Monero (XMR) isoladas
  updates,      // Atualizações do ecossistema Nix
  directChat,   // Conversa privada selecionada (Card ID sai de cena e abre-se o chat)
}

class DirectMessageThread {
  final String id;
  final String peerName;
  final String peerPublicId;
  final String statusText;
  final bool isOnline;
  final bool isVerified;
  final int unreadCount;
  final List<Message> messages;

  const DirectMessageThread({
    required this.id,
    required this.peerName,
    required this.peerPublicId,
    required this.statusText,
    this.isOnline = true,
    this.isVerified = true,
    this.unreadCount = 0,
    required this.messages,
  });

  String get lastMessagePreview =>
      messages.isNotEmpty ? messages.last.text : 'Sessão Double Ratchet estabelecida.';

  DirectMessageThread copyWith({
    int? unreadCount,
    List<Message>? messages,
  }) {
    return DirectMessageThread(
      id: id,
      peerName: peerName,
      peerPublicId: peerPublicId,
      statusText: statusText,
      isOnline: isOnline,
      isVerified: isVerified,
      unreadCount: unreadCount ?? this.unreadCount,
      messages: messages ?? this.messages,
    );
  }
}

class ContactRequest {
  final String id;
  final String peerName;
  final String peerPublicId;
  final String note;
  final DateTime timestamp;
  final bool isIncoming;

  const ContactRequest({
    required this.id,
    required this.peerName,
    required this.peerPublicId,
    required this.note,
    required this.timestamp,
    this.isIncoming = true,
  });
}

class XmrTransactionRecord {
  final String id;
  final String title;
  final String amountXmr;
  final String subaddressPreview;
  final DateTime timestamp;
  final int confirmations;
  final bool isIncoming;

  const XmrTransactionRecord({
    required this.id,
    required this.title,
    required this.amountXmr,
    required this.subaddressPreview,
    required this.timestamp,
    required this.confirmations,
    required this.isIncoming,
  });
}

class SystemUpdateRecord {
  final String id;
  final String version;
  final String title;
  final String summary;
  final String dateLabel;
  final List<String> highlights;

  const SystemUpdateRecord({
    required this.id,
    required this.version,
    required this.title,
    required this.summary,
    required this.dateLabel,
    required this.highlights,
  });
}
