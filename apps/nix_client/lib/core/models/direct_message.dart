import 'message.dart';
import 'member.dart';

enum HomeSubTab {
  cardId,          // Estado inicial vazio / Gerenciamento do Card ID
  friends,         // Amigos verificados
  requests,        // Solicitações de contato (com hover preview restrito a avatar/nome)
  moneroP2p,       // Monero Non-Custodial P2P Marketplace
  githubDiscovery, // Descoberta de Repositórios GitHub (Starwire)
  transactions,    // Histórico local XMR
  updates,         // Atualizações do ecossistema Nix
  directChat,      // Conversa privada selecionada (ou Mensagens Salvas)
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
  final bool isSavedMessages;
  final bool isPinned;
  final bool isMuted;
  final String? peerMailboxId;
  final bool hasActiveSession;
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
    this.isSavedMessages = false,
    this.isPinned = false,
    this.isMuted = false,
    this.peerMailboxId,
    this.hasActiveSession = false,
    required this.messages,
  });

  String get lastMessagePreview {
    if (messages.isEmpty) {
      return isSavedMessages
          ? 'Notas criptografadas, links, arquivos e encaminhamentos privados.'
          : 'Sessão Double Ratchet estabelecida.';
    }
    return messages.last.text;
  }

  DateTime? get lastActivityAt => messages.isNotEmpty ? messages.last.timestamp : null;

  DirectMessageThread copyWith({
    String? peerName,
    String? peerPublicId,
    String? statusText,
    int? unreadCount,
    bool? isSavedMessages,
    bool? isPinned,
    bool? isMuted,
    String? peerMailboxId,
    bool? hasActiveSession,
    List<Message>? messages,
    NixTrustLevel? trustLevel,
    bool? isOnline,
    bool? isVerified,
  }) {
    return DirectMessageThread(
      id: id,
      peerName: peerName ?? this.peerName,
      peerPublicId: peerPublicId ?? this.peerPublicId,
      statusText: statusText ?? this.statusText,
      isOnline: isOnline ?? this.isOnline,
      isVerified: isVerified ?? this.isVerified,
      trustLevel: trustLevel ?? this.trustLevel,
      unreadCount: unreadCount ?? this.unreadCount,
      isSavedMessages: isSavedMessages ?? this.isSavedMessages,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      peerMailboxId: peerMailboxId ?? this.peerMailboxId,
      hasActiveSession: hasActiveSession ?? this.hasActiveSession,
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
  final String cardIdVisibility; // 'Público', 'Apenas Contatos Verificados', 'Oculto'

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
    this.cardIdVisibility = 'Público',
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
