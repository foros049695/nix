import 'package:flutter/material.dart';
import '../theme/nix_colors.dart';

enum ChannelType {
  text, // Sala de texto padrão
  forum, // Área de tópicos interativos (cards com imagens + chat em split-view)
  voice, // Sala de voz / call E2EE
  publication, // Sala do Nix Archive (artigos canônicos e evidências)
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
  final bool protectPreviews;
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
    this.protectPreviews = false,
    this.requestScreenshotProtection = false,
    this.ephemeralRetentionMinutes = 0,
    this.isPublic = false,
    this.requireApproval = false,
    this.memberLimit = 0,
    this.inviteExpiryDays = 7,
    this.slowModeSeconds = 0,
    this.maxFileSizeMb = 50,
  });

  Map<String, Object?> toJson() => {
        'allowMessages': allowMessages,
        'allowImages': allowImages,
        'allowFiles': allowFiles,
        'allowVideos': allowVideos,
        'allowAudio': allowAudio,
        'allowLinks': allowLinks,
        'allowForwarding': allowForwarding,
        'allowReactions': allowReactions,
        'allowEditing': allowEditing,
        'allowDeletion': allowDeletion,
        'restrictExport': restrictExport,
        'restrictMediaSaving': restrictMediaSaving,
        'protectPreviews': protectPreviews,
        'requestScreenshotProtection': requestScreenshotProtection,
        'ephemeralRetentionMinutes': ephemeralRetentionMinutes,
        'isPublic': isPublic,
        'requireApproval': requireApproval,
        'memberLimit': memberLimit,
        'inviteExpiryDays': inviteExpiryDays,
        'slowModeSeconds': slowModeSeconds,
        'maxFileSizeMb': maxFileSizeMb,
      };

  factory ChannelPermissions.fromJson(Map<String, dynamic> data) {
    const defaults = ChannelPermissions();
    return ChannelPermissions(
      allowMessages: data['allowMessages'] is bool
          ? data['allowMessages'] as bool
          : defaults.allowMessages,
      allowImages: data['allowImages'] is bool
          ? data['allowImages'] as bool
          : defaults.allowImages,
      allowFiles: data['allowFiles'] is bool
          ? data['allowFiles'] as bool
          : defaults.allowFiles,
      allowVideos: data['allowVideos'] is bool
          ? data['allowVideos'] as bool
          : defaults.allowVideos,
      allowAudio: data['allowAudio'] is bool
          ? data['allowAudio'] as bool
          : defaults.allowAudio,
      allowLinks: data['allowLinks'] is bool
          ? data['allowLinks'] as bool
          : defaults.allowLinks,
      allowForwarding: data['allowForwarding'] is bool
          ? data['allowForwarding'] as bool
          : defaults.allowForwarding,
      allowReactions: data['allowReactions'] is bool
          ? data['allowReactions'] as bool
          : defaults.allowReactions,
      allowEditing: data['allowEditing'] is bool
          ? data['allowEditing'] as bool
          : defaults.allowEditing,
      allowDeletion: data['allowDeletion'] is bool
          ? data['allowDeletion'] as bool
          : defaults.allowDeletion,
      restrictExport: data['restrictExport'] is bool
          ? data['restrictExport'] as bool
          : defaults.restrictExport,
      restrictMediaSaving: data['restrictMediaSaving'] is bool
          ? data['restrictMediaSaving'] as bool
          : defaults.restrictMediaSaving,
      protectPreviews: data['protectPreviews'] is bool
          ? data['protectPreviews'] as bool
          : defaults.protectPreviews,
      requestScreenshotProtection: data['requestScreenshotProtection'] is bool
          ? data['requestScreenshotProtection'] as bool
          : defaults.requestScreenshotProtection,
      ephemeralRetentionMinutes: data['ephemeralRetentionMinutes'] is int
          ? data['ephemeralRetentionMinutes'] as int
          : defaults.ephemeralRetentionMinutes,
      isPublic: data['isPublic'] is bool
          ? data['isPublic'] as bool
          : defaults.isPublic,
      requireApproval: data['requireApproval'] is bool
          ? data['requireApproval'] as bool
          : defaults.requireApproval,
      memberLimit: data['memberLimit'] is int
          ? data['memberLimit'] as int
          : defaults.memberLimit,
      inviteExpiryDays: data['inviteExpiryDays'] is int
          ? data['inviteExpiryDays'] as int
          : defaults.inviteExpiryDays,
      slowModeSeconds: data['slowModeSeconds'] is int
          ? data['slowModeSeconds'] as int
          : defaults.slowModeSeconds,
      maxFileSizeMb: data['maxFileSizeMb'] is int
          ? data['maxFileSizeMb'] as int
          : defaults.maxFileSizeMb,
    );
  }

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
    bool? protectPreviews,
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
      protectPreviews: protectPreviews ?? this.protectPreviews,
      requestScreenshotProtection:
          requestScreenshotProtection ?? this.requestScreenshotProtection,
      ephemeralRetentionMinutes:
          ephemeralRetentionMinutes ?? this.ephemeralRetentionMinutes,
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
  final bool isPinned;
  final bool isMuted;
  final String category;
  final String? customImagePath;
  final String? inviteCode;
  final ChannelPermissions permissions;
  final String ownerFingerprint;
  final List<String> admins;
  final List<String> moderators;
  final List<String> mutedMembers;
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
    this.isPinned = false,
    this.isMuted = false,
    required this.category,
    this.customImagePath,
    this.inviteCode,
    this.permissions = const ChannelPermissions(),
    this.ownerFingerprint = '7E3A-9F01-C45B-289D',
    this.admins = const [],
    this.moderators = const [],
    this.mutedMembers = const [],
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

  Map<String, Object?> toJson() => {
        'id': id,
        'spaceId': spaceId,
        'name': name,
        'topic': topic,
        'description': description,
        'category': category,
        'ownerFingerprint': ownerFingerprint,
        'customImagePath': customImagePath,
        'inviteCode': inviteCode,
        'isEncrypted': isEncrypted,
        'isPinned': isPinned,
        'isMuted': isMuted,
        'admins': admins,
        'moderators': moderators,
        'mutedMembers': mutedMembers,
        'bannedMembers': bannedMembers,
        'auditLogs': auditLogs,
        'type': type.name,
        'permissions': permissions.toJson(),
      };

  factory Channel.fromJson(Map<String, dynamic> data,
      {required String spaceId}) {
    List<String> ids(String key) =>
        (data[key] as List?)?.whereType<String>().toList() ?? [];
    return Channel(
      id: data['id'] as String,
      spaceId: spaceId,
      name: data['name'] as String,
      topic: data['topic'] as String? ?? '',
      description: data['description'] as String? ?? '',
      category: data['category'] as String? ?? 'COMUNIDADE',
      ownerFingerprint: data['ownerFingerprint'] as String? ?? '',
      customImagePath: data['customImagePath'] as String?,
      inviteCode: data['inviteCode'] as String?,
      type: ChannelType.values.firstWhere((type) => type.name == data['type'],
          orElse: () => ChannelType.text),
      isEncrypted: data['isEncrypted'] != false,
      isPinned: data['isPinned'] == true,
      isMuted: data['isMuted'] == true,
      admins: ids('admins'),
      moderators: ids('moderators'),
      mutedMembers: ids('mutedMembers'),
      bannedMembers: ids('bannedMembers'),
      auditLogs: ids('auditLogs'),
      permissions: ChannelPermissions.fromJson(
          data['permissions'] as Map<String, dynamic>? ?? {}),
    );
  }

  Channel copyWith({
    String? name,
    String? topic,
    String? description,
    ChannelType? type,
    int? unreadCount,
    bool? isEncrypted,
    bool? isPinned,
    bool? isMuted,
    String? category,
    String? customImagePath,
    bool clearCustomImage = false,
    String? inviteCode,
    ChannelPermissions? permissions,
    List<String>? admins,
    List<String>? moderators,
    List<String>? mutedMembers,
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
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      category: category ?? this.category,
      customImagePath:
          clearCustomImage ? null : customImagePath ?? this.customImagePath,
      inviteCode: inviteCode ?? this.inviteCode,
      permissions: permissions ?? this.permissions,
      ownerFingerprint: ownerFingerprint,
      admins: admins ?? this.admins,
      moderators: moderators ?? this.moderators,
      mutedMembers: mutedMembers ?? this.mutedMembers,
      bannedMembers: bannedMembers ?? this.bannedMembers,
      auditLogs: auditLogs ?? this.auditLogs,
    );
  }
}
