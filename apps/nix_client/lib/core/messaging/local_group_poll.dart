import 'direct_poll.dart';

/// Enquete de um canal local. A chave do canal vincula cada cédula à sua sala.
class LocalGroupPoll {
  final String id;
  final String channelId;
  final String creator;
  final DateTime created;
  final DirectPollSpec spec;
  final Map<String, List<int>> votes;
  final bool closed;

  LocalGroupPoll({
    required this.id,
    required this.channelId,
    required this.creator,
    required this.created,
    required this.spec,
    Map<String, List<int>> votes = const {},
    this.closed = false,
  }) : votes = Map.unmodifiable(votes.map(
          (actor, choices) => MapEntry(actor, List<int>.unmodifiable(choices)),
        ));

  bool isOpen(DateTime now) =>
      !closed &&
      (spec.durationMinutes == null ||
          now.isBefore(created.add(Duration(minutes: spec.durationMinutes!))));

  LocalGroupPoll vote(String actor, List<int> choices, DateTime now) {
    if (actor.isEmpty ||
        !isOpen(now) ||
        !spec.accepts(choices) ||
        (votes.containsKey(actor) && !spec.allowRevote)) {
      throw StateError('A enquete não aceita este voto.');
    }
    return LocalGroupPoll(
      id: id,
      channelId: channelId,
      creator: creator,
      created: created,
      spec: spec,
      votes: {...votes, actor: choices},
    );
  }

  LocalGroupPoll close(String actor) {
    if (actor != creator || closed) {
      throw StateError('Só o autor pode encerrar a enquete.');
    }
    return LocalGroupPoll(
      id: id,
      channelId: channelId,
      creator: creator,
      created: created,
      spec: spec,
      votes: votes,
      closed: true,
    );
  }

  List<int> get totals => List.generate(
        spec.options.length,
        (option) =>
            votes.values.where((entry) => entry.contains(option)).length,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'channel': channelId,
        'creator': creator,
        'created': created.millisecondsSinceEpoch,
        'spec': spec.encode(),
        'closed': closed,
        'votes': votes,
      };

  static LocalGroupPoll? parse(Object? raw) {
    if (raw is! Map) return null;
    try {
      final spec = DirectPollEvent.parse(raw['spec'] as String);
      final stamp = raw['created'] as int;
      if (spec is! DirectPollSpec || !DirectPollEvent.acceptsTimestamp(stamp))
        return null;
      final votes = (raw['votes'] as Map).map(
        (key, value) => MapEntry(key as String, (value as List).cast<int>()),
      );
      if (votes.entries
          .any((entry) => entry.key.isEmpty || !spec.accepts(entry.value)))
        return null;
      return LocalGroupPoll(
        id: raw['id'] as String,
        channelId: raw['channel'] as String,
        creator: raw['creator'] as String,
        spec: spec,
        created: DateTime.fromMillisecondsSinceEpoch(stamp, isUtc: true),
        closed: raw['closed'] as bool,
        votes: votes,
      );
    } catch (_) {
      return null;
    }
  }
}
