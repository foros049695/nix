import 'message.dart';
import 'member.dart';

enum HomeSubTab {
  cardId,          // Estado inicial vazio da Home -> preenchido pelo CARD ID
  friends,         // Amigos verificados
  requests,        // Solicitações de contato (com hover preview de Card ID)
  moneroP2p,       // Monero Non-Custodial P2P Marketplace (Trocador style)
  githubDiscovery, // Descoberta de Repositórios GitHub (starwire style)
  transactions,    // Histórico de transações XMR da carteira
  updates,         // Atualizações do ecossistema Nix
  directChat,      // Conversa privada selecionada (Card ID sai de cena e abre-se o chat)
}

class DirectMessageThread {
  final String id;
  final String peerName;
  final String peerPublicId;
  final String statusText;
  final bool isOnline;
  final bool isVerified;
  final NixTrustLevel trustLevel;
  final int unreadCount;
  final List<Message> messages;

  const DirectMessageThread({
    required this.id,
    required this.peerName,
    required this.peerPublicId,
    required this.statusText,
    this.isOnline = true,
    this.isVerified = true,
    this.trustLevel = NixTrustLevel.level3Green,
    this.unreadCount = 0,
    required this.messages,
  });

  String get lastMessagePreview =>
      messages.isNotEmpty ? messages.last.text : 'Sessão Double Ratchet estabelecida.';

  DirectMessageThread copyWith({
    int? unreadCount,
    List<Message>? messages,
    NixTrustLevel? trustLevel,
    bool? isOnline,
    bool? isVerified,
  }) {
    return DirectMessageThread(
      id: id,
      peerName: peerName,
      peerPublicId: peerPublicId,
      statusText: statusText,
      isOnline: isOnline ?? this.isOnline,
      isVerified: isVerified ?? this.isVerified,
      trustLevel: trustLevel ?? this.trustLevel,
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
  final NixTrustLevel trustLevel;
  final String bio;
  final List<String> culturalHighlights;

  const ContactRequest({
    required this.id,
    required this.peerName,
    required this.peerPublicId,
    required this.note,
    required this.timestamp,
    this.isIncoming = true,
    this.trustLevel = NixTrustLevel.level1Red,
    this.bio = 'Membro da rede Tor Onion com interesse em criptografia e privacidade.',
    this.culturalHighlights = const ['Ghost Dog', 'Mobile Suit Gundam Hathaway', '12 Angry Men'],
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
