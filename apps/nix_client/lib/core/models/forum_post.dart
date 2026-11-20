import '../archive/archive_image.dart';
import 'message.dart';

class ForumImageSpec {
  final String label;
  final String subtitle;
  final String code;
  final ArchiveImage? image;

  const ForumImageSpec({
    required this.label,
    required this.subtitle,
    required this.code,
    this.image,
  });
}

class ForumPost {
  final String id;
  final String channelId;
  final String title;
  final String authorName;
  final String authorFingerprint;
  final DateTime createdAt;
  final List<String> tags;
  final String description;
  final List<ForumImageSpec> images;
  final List<Message> comments;
  final bool isNew;
  final int endorsements;

  const ForumPost({
    required this.id,
    required this.channelId,
    required this.title,
    required this.authorName,
    required this.authorFingerprint,
    required this.createdAt,
    required this.tags,
    required this.description,
    required this.images,
    required this.comments,
    this.isNew = true,
    this.endorsements = 0,
  });

  ForumPost copyWith({
    List<Message>? comments,
    int? endorsements,
  }) {
    return ForumPost(
      id: id,
      channelId: channelId,
      title: title,
      authorName: authorName,
      authorFingerprint: authorFingerprint,
      createdAt: createdAt,
      tags: tags,
      description: description,
      images: images,
      comments: comments ?? this.comments,
      isNew: isNew,
      endorsements: endorsements ?? this.endorsements,
    );
  }
}
