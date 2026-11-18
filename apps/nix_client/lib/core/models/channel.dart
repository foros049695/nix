import 'package:flutter/material.dart';
import '../theme/nix_colors.dart';

enum ChannelType {
  text,         // Sala de texto padrão
  forum,        // Área de tópicos interativos (cards com imagens + chat em split-view)
  voice,        // Sala de voz / call E2EE
  publication,  // Sala do Nix Archive (artigos canônicos e evidências)
  announcement, // Canal de comunicados
}

class ChannelPermissions {
  final bool allowMessages;
  final bool allowImages;
  final bool allowFiles;
  final bool allowVideos;
  final bool allowAudio;
  final bool allowLinks;
  final bool allowForwarding;
  final bool allowReactions;
  final bool allowEditing;
  final bool allowDeletion;

  // Proteção de Conteúdo
  final bool restrictExport;
  final bool restrictMediaSaving;
  final bool requestScreenshotProtection; // FLAG_SECURE no Android
  final int ephemeralRetentionMinutes; // 0 = permanente, 5, 60, 1440, 10080

  // Identidade e Acesso
  final bool isPublic;
  final bool requireApproval;
  final int memberLimit; // 0 = ilimitado
  final int inviteExpiryDays; // 1, 7, 30, 0 = nunca

  // Segurança e Anti-spam
  final int slowModeSeconds; // 0 = desativado
  final int maxFileSizeMb; // 10, 50, 100

  const ChannelPermissions({
    this.allowMessages = true,
    this.allowImages = true,
    this.allowFiles = true,
    this.allowVideos = true,
    this.allowAudio = true,
    this.allowLinks = true,
    this.allowForwarding = true,
    this.allowReactions = true,
    this.allowEditing = true,
    this.allowDeletion = true,
    this.restrictExport = false,
    this.restrictMediaSaving = false,
    this.requestScreenshotProtection = false,
    this.ephemeralRetentionMinutes = 0,
    this.isPublic = false,
    this.requireApproval = false,
    this.memberLimit = 0,
    this.inviteExpiryDays = 7,
    this.slowModeSeconds = 0,
    this.maxFileSizeMb = 50,
  });

  ChannelPermissions copyWith({
    bool? allowMessages,
    bool? allowImages,
    bool? allowFiles,
    bool? allowVideos,
    bool? allowAudio,
    bool? allowLinks,
    bool? allowForwarding,
    bool? allowReactions,
    bool? allowEditing,
    bool? allowDeletion,
    bool? restrictExport,
    bool? restrictMediaSaving,
    bool? requestScreenshotProtection,
    int? ephemeralRetentionMinutes,
    bool? isPublic,
    bool? requireApproval,
    int? memberLimit,
    int? inviteExpiryDays,
    int? slowModeSeconds,
    int? maxFileSizeMb,
  }) {
    return ChannelPermissions(
      allowMessages: allowMessages ?? this.allowMessages,
      allowImages: allowImages ?? this.allowImages,
      allowFiles: allowFiles ?? this.allowFiles,
      allowVideos: allowVideos ?? this.allowVideos,
      allowAudio: allowAudio ?? this.allowAudio,
      allowLinks: allowLinks ?? this.allowLinks,
      allowForwarding: allowForwarding ?? this.allowForwarding,
      allowReactions: allowReactions ?? this.allowReactions,
      allowEditing: allowEditing ?? this.allowEditing,
      allowDeletion: allowDeletion ?? this.allowDeletion,
      restrictExport: restrictExport ?? this.restrictExport,
      restrictMediaSaving: restrictMediaSaving ?? this.restrictMediaSaving,
      requestScreenshotProtection: requestScreenshotProtection ?? this.requestScreenshotProtection,
      ephemeralRetentionMinutes: ephemeralRetentionMinutes ?? this.ephemeralRetentionMinutes,
      isPublic: isPublic ?? this.isPublic,
      requireApproval: requireApproval ?? this.requireApproval,
      memberLimit: memberLimit ?? this.memberLimit,
      inviteExpiryDays: inviteExpiryDays ?? this.inviteExpiryDays,
      slowModeSeconds: slowModeSeconds ?? this.slowModeSeconds,
      maxFileSizeMb: maxFileSizeMb ?? this.maxFileSizeMb,
    );
  }
}

class Channel {
  final String id;
  final String spaceId;
  final String name;
  final String topic;
  final String description;
  final ChannelType type;
  final int unreadCount;
  final bool isEncrypted;
  final String category;
  final ChannelPermissions permissions;
  final String ownerFingerprint;
  final List<String> admins;
  final List<String> moderators;
  final List<String> bannedMembers;
  final List<String> auditLogs;

  const Channel({
    required this.id,
    required this.spaceId,
    required this.name,
    required this.topic,
    this.description = '',
    required this.type,
    this.unreadCount = 0,
    this.isEncrypted = true,
    required this.category,
    this.permissions = const ChannelPermissions(),
    this.ownerFingerprint = '7E3A-9F01-C45B-289D',
    this.admins = const [],
    this.moderators = const [],
    this.bannedMembers = const [],
    this.auditLogs = const [
      'Canal inicializado com criptografia de envelope Ed25519/XChaCha20.',
      'Políticas de retenção e privacidade estabelecidas.',
    ],
  });

  IconData get icon {
    switch (type) {
      case ChannelType.text:
        return Icons.tag_rounded;
      case ChannelType.forum:
        return Icons.forum_outlined;
      case ChannelType.voice:
        return Icons.volume_up_outlined;
      case ChannelType.publication:
        return Icons.menu_book_outlined;
      case ChannelType.announcement:
        return Icons.campaign_outlined;
    }
  }

  // Ícones monocromáticos consistentes
  Color get iconColor => NixColors.iconSecondary;

  Channel copyWith({
    String? name,
    String? topic,
    String? description,
    ChannelType? type,
    int? unreadCount,
    bool? isEncrypted,
    String? category,
    ChannelPermissions? permissions,
    List<String>? admins,
    List<String>? moderators,
    List<String>? bannedMembers,
    List<String>? auditLogs,
  }) {
    return Channel(
      id: id,
      spaceId: spaceId,
      name: name ?? this.name,
      topic: topic ?? this.topic,
      description: description ?? this.description,
      type: type ?? this.type,
      unreadCount: unreadCount ?? this.unreadCount,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      category: category ?? this.category,
      permissions: permissions ?? this.permissions,
      ownerFingerprint: ownerFingerprint,
      admins: admins ?? this.admins,
      moderators: moderators ?? this.moderators,
      bannedMembers: bannedMembers ?? this.bannedMembers,
      auditLogs: auditLogs ?? this.auditLogs,
    );
  }
}
