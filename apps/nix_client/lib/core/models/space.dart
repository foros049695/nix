import 'channel.dart';

class Space {
  final String id;
  final String name;
  final String initials;
  final String description;
  final bool isDirectMessages;
  final String? iconEmoji;
  final List<Channel> channels;
  final int unreadCount;

  const Space({
    required this.id,
    required this.name,
    required this.initials,
    required this.description,
    this.isDirectMessages = false,
    this.iconEmoji,
    required this.channels,
    this.unreadCount = 0,
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
    );
  }
}
