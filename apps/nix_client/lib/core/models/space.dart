import 'channel.dart';

class SpaceFolder {
  final String id;
  final String name;
  final String
      iconName; // 'folder', 'shield', 'code', 'chat', 'star', 'lock', 'bookmark'
  final int colorValue;
  final List<String> spaceIds;
  final List<String>
      conversationIds; // Suporta DMs, grupos e canais arrastados para a pasta
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

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'iconName': iconName,
        'colorValue': colorValue,
        'spaceIds': spaceIds,
        'conversationIds': conversationIds,
        'isExpanded': isExpanded,
      };

  factory SpaceFolder.fromJson(Map<String, dynamic> data) => SpaceFolder(
        id: data['id'] as String,
        name: data['name'] as String,
        iconName: data['iconName'] as String? ?? 'folder',
        colorValue: data['colorValue'] as int? ?? 0xFFFFC928,
        spaceIds:
            (data['spaceIds'] as List?)?.whereType<String>().toList() ?? [],
        conversationIds:
            (data['conversationIds'] as List?)?.whereType<String>().toList() ??
                [],
        isExpanded: data['isExpanded'] == true,
      );

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
  final String? customImagePath;
  final String? ownerFingerprint;
  final List<Channel> channels;
  final int unreadCount;
  final int? memberCount;
  final int? onlineCount;
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
    this.customImagePath,
    this.ownerFingerprint,
    required this.channels,
    this.unreadCount = 0,
    this.memberCount,
    this.onlineCount,
    this.isPublic = true,
    this.isPinned = false,
    this.isMuted = false,
    this.categoryTag = 'Comunidade',
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'initials': initials,
        'description': description,
        'iconEmoji': iconEmoji,
        'customImagePath': customImagePath,
        'ownerFingerprint': ownerFingerprint,
        'isPublic': isPublic,
        'isPinned': isPinned,
        'isMuted': isMuted,
        'categoryTag': categoryTag,
        'channels': channels.map((channel) => channel.toJson()).toList(),
      };

  factory Space.fromJson(Map<String, dynamic> data) {
    final id = data['id'] as String;
    return Space(
      id: id,
      name: data['name'] as String,
      initials: data['initials'] as String? ?? 'NX',
      description: data['description'] as String? ?? '',
      iconEmoji: data['iconEmoji'] as String?,
      customImagePath: data['customImagePath'] as String?,
      ownerFingerprint: data['ownerFingerprint'] as String?,
      isPublic: data['isPublic'] == true,
      isPinned: data['isPinned'] == true,
      isMuted: data['isMuted'] == true,
      categoryTag: data['categoryTag'] as String? ?? 'Comunidade',
      channels: (data['channels'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((channel) => Channel.fromJson(channel, spaceId: id))
          .toList(),
    );
  }

  Space copyWith({
    String? id,
    String? name,
    String? initials,
    String? description,
    bool? isDirectMessages,
    String? iconEmoji,
    String? customImagePath,
    bool clearCustomImage = false,
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
      customImagePath:
          clearCustomImage ? null : customImagePath ?? this.customImagePath,
      ownerFingerprint: ownerFingerprint,
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
