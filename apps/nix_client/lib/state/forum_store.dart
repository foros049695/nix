import '../core/archive/archive_image.dart';
import '../core/database/repositories.dart';
import '../core/models/forum_post.dart';
import '../core/models/message.dart';

class ForumStore {
  const ForumStore(this.repository);

  static const _key = 'forum_local_v1';
  final PreferencesRepository repository;

  Future<void> save(
          List<ForumPost> posts, Map<String, Map<String, String>> tags) =>
      repository.setOption(_key, {
        'tags': tags,
        'posts': [
          for (final post in posts)
            {
              'id': post.id,
              'channel': post.channelId,
              'title': post.title,
              'author': post.authorName,
              'fingerprint': post.authorFingerprint,
              'created': post.createdAt.millisecondsSinceEpoch,
              'edited': post.editedAt?.millisecondsSinceEpoch,
              'revision': post.revision,
              'tags': post.tags,
              'description': post.description,
              'images': [for (final item in post.images) if (item.image != null) item.image!.toJson()],
              'comments': [
                for (final comment in post.comments)
                  {
                    'id': comment.id,
                    'author': comment.senderName,
                    'fingerprint': comment.senderFingerprint,
                    'mine': comment.isMe,
                    'text': comment.text,
                    'created': comment.timestamp.millisecondsSinceEpoch,
                    'edited': comment.editedAt?.millisecondsSinceEpoch,
                    'reactions': comment.reactions,
                    'myReactions': comment.myReactions.toList(),
                  },
              ],
            },
        ],
      });

  Future<({List<ForumPost> posts, Map<String, Map<String, String>> tags})>
      load() async {
    final stored = await repository.getOption(_key);
    if (stored is! Map)
      return (posts: <ForumPost>[], tags: <String, Map<String, String>>{});
    final tags = <String, Map<String, String>>{};
    final rawTags = stored['tags'];
    if (rawTags is Map) {
      for (final entry in rawTags.entries) {
        if (entry.key is String && entry.value is Map) {
          tags[entry.key as String] = {
            for (final tag in (entry.value as Map).entries)
              if (tag.key is String && tag.value is String)
                tag.key as String: tag.value as String,
          };
        }
      }
    }
    final posts = <ForumPost>[];
    final rawPosts = stored['posts'];
    if (rawPosts is List) {
      for (final row in rawPosts.whereType<Map>()) {
        try {
          final id = row['id'] as String;
          posts.add(ForumPost(
            id: id,
            channelId: row['channel'] as String,
            title: row['title'] as String,
            authorName: row['author'] as String,
            authorFingerprint: row['fingerprint'] as String,
            createdAt: _date(row['created']),
            editedAt: row['edited'] != null ? _date(row['edited']) : null,
            revision: row['revision'] as int? ?? 1,
            tags: (row['tags'] as List).cast<String>(),
            description: row['description'] as String,
            images: ArchiveImage.readList(row['images']).indexed.map((entry) =>
              ForumImageSpec(label: 'Imagem ${entry.$1 + 1}', subtitle: '', code: '',
                image: entry.$2)).toList(growable: false),
            comments: [
              for (final comment in (row['comments'] as List).whereType<Map>())
                Message(
                  id: comment['id'] as String,
                  channelId: id,
                  senderName: comment['author'] as String,
                  senderFingerprint: comment['fingerprint'] as String,
                  isMe: comment['mine'] as bool,
                  text: comment['text'] as String,
                  timestamp: _date(comment['created']),
                  editedAt: comment['edited'] == null
                      ? null
                      : _date(comment['edited']),
                  reactions: (comment['reactions'] as Map).cast<String, int>(),
                  myReactions:
                      (comment['myReactions'] as List).cast<String>().toSet(),
                  deliveryState: 'saved',
                ),
            ],
          ));
        } catch (_) {
          // Uma linha incompatível não descarta os demais tópicos do cofre.
        }
      }
    }
    return (posts: posts, tags: tags);
  }

  static DateTime _date(Object? value) =>
      DateTime.fromMillisecondsSinceEpoch(value as int, isUtc: true);
}
