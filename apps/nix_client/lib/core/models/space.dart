import 'channel.dart';

class SpaceFolder {
  final String id;
  final String name;
  final List<String> spaceIds;
  final bool isExpanded;

  const SpaceFolder({
    required this.id,
    required this.name,
    required this.spaceIds,
    this.isExpanded = false,
  });

  SpaceFolder copyWith({
    String? id,
    String? name,
    List<String>? spaceIds,
    bool? isExpanded,
  }) {
    return SpaceFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      spaceIds: spaceIds ?? this.spaceIds,
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
      categoryTag: categoryTag ?? this.categoryTag,
    );
  }
}
