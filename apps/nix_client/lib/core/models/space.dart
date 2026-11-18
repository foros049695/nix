import 'channel.dart';

class SpaceFolder {
  final String id;
  final String name;
  final String iconName; // 'folder', 'shield', 'code', 'chat', 'star', 'lock', 'bookmark'
  final int colorValue;
  final List<String> spaceIds;
  final List<String> conversationIds; // Suporta DMs, grupos e canais arrastados para a pasta
  final bool isExpanded;

  const SpaceFolder({
    required this.id,
    required this.name,
    this.iconName = 'folder',
    this.colorValue = 0xFFFFC928,
    required this.spaceIds,
    this.conversationIds = const [],
    this.isExpanded = false,
  });

  SpaceFolder copyWith({
    String? id,
    String? name,
    String? iconName,
    int? colorValue,
    List<String>? spaceIds,
    List<String>? conversationIds,
    bool? isExpanded,
  }) {
    return SpaceFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      colorValue: colorValue ?? this.colorValue,
      spaceIds: spaceIds ?? this.spaceIds,
      conversationIds: conversationIds ?? this.conversationIds,
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }
}

class Space {
  final String id;
  final String name;
  final String initials;
  final String description;
  final bool isDirectMessages;
  final String? iconEmoji;
  final List<Channel> channels;
  final int unreadCount;
  final int memberCount;
  final int onlineCount;
  final bool isPublic;
  final bool isPinned;
  final bool isMuted;
  final String categoryTag;

  const Space({
    required this.id,
    required this.name,
    required this.initials,
    required this.description,
    this.isDirectMessages = false,
    this.iconEmoji,
    required this.channels,
    this.unreadCount = 0,
    this.memberCount = 12,
    this.onlineCount = 5,
    this.isPublic = true,
    this.isPinned = false,
    this.isMuted = false,
    this.categoryTag = 'Comunidade',
  });

  Space copyWith({
    String? id,
    String? name,
    String? initials,
    String? description,
    bool? isDirectMessages,
    String? iconEmoji,
    List<Channel>? channels,
    int? unreadCount,
    int? memberCount,
    int? onlineCount,
    bool? isPublic,
    bool? isPinned,
    bool? isMuted,
    String? categoryTag,
  }) {
    return Space(
      id: id ?? this.id,
      name: name ?? this.name,
      initials: initials ?? this.initials,
      description: description ?? this.description,
      isDirectMessages: isDirectMessages ?? this.isDirectMessages,
      iconEmoji: iconEmoji ?? this.iconEmoji,
      channels: channels ?? this.channels,
      unreadCount: unreadCount ?? this.unreadCount,
      memberCount: memberCount ?? this.memberCount,
      onlineCount: onlineCount ?? this.onlineCount,
      isPublic: isPublic ?? this.isPublic,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      categoryTag: categoryTag ?? this.categoryTag,
    );
  }
}
