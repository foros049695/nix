import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

sealed class DirectPollEvent {
  const DirectPollEvent();

  static const prefix = 'nix.poll.v1:';
  static const maxLength = 4096;

  static final _latestTimestamp =
      8640000000000000 - const Duration(days: 7).inMilliseconds;

  static bool acceptsTimestamp(int stamp) =>
      stamp >= 0 && stamp <= _latestTimestamp;

  Map<String, Object?> toJson();

  String encode() => '$prefix${jsonEncode(toJson())}';

  static DirectPollEvent? parse(String text) {
    if (!text.startsWith(prefix) || text.length > maxLength) return null;
    try {
      final data =
          jsonDecode(text.substring(prefix.length)) as Map<String, dynamic>;
      return switch (data['type']) {
        'open' => DirectPollSpec.create(
            question: data['question'] as String,
            description: data['description'] as String,
            options: (data['options'] as List).cast<String>(),
            multiple: data['multiple'] as bool,
            allowRevote: data['revote'] as bool,
            hideResults: data['hidden'] as bool,
            shuffle: data['shuffle'] as bool? ?? false,
            correctOption: data['correct'] as int?,
            durationMinutes: data['minutes'] as int?,
          ),
        'vote' => DirectPollVote(
            pollId: _id(data['poll']),
            revision: _revision(data['revision']),
            options: _choices(data['options']),
          ),
        'close' => DirectPollClose(
            pollId: _id(data['poll']),
            creatorChoices: _choices(data['creator'], emptyAllowed: true),
            peerChoices: _choices(data['peer'], emptyAllowed: true),
          ),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  static String _id(Object? id) {
    if (id is! String || !RegExp(r'^[a-zA-Z0-9_-]{1,96}$').hasMatch(id)) {
      throw const FormatException('Identificador de enquete inválido.');
    }
    return id;
  }

  static int _revision(Object? revision) {
    if (revision is! int || revision < 1 || revision > 1000) {
      throw const FormatException('Revisão de voto inválida.');
    }
    return revision;
  }

  static List<int> _choices(Object? raw, {bool emptyAllowed = false}) {
    final list = (raw as List).cast<int>();
    if ((!emptyAllowed && list.isEmpty) ||
        list.length > 8 ||
        list.toSet().length != list.length ||
        list.any((value) => value < 0 || value >= 8)) {
      throw const FormatException('Opções de voto inválidas.');
    }
    return List.unmodifiable(list);
  }
}

final class DirectPollSpec extends DirectPollEvent {
  const DirectPollSpec._({
    required this.question,
    required this.description,
    required this.options,
    required this.multiple,
    required this.allowRevote,
    required this.hideResults,
    required this.shuffle,
    required this.correctOption,
    required this.durationMinutes,
  });

  final String question;
  final String description;
  final List<String> options;
  final bool multiple;
  final bool allowRevote;
  final bool hideResults;
  final bool shuffle;
  final int? correctOption;
  final int? durationMinutes;

  factory DirectPollSpec.create({
    required String question,
    required List<String> options,
    String description = '',
    bool multiple = false,
    bool allowRevote = false,
    bool hideResults = false,
    bool shuffle = false,
    int? correctOption,
    int? durationMinutes,
  }) {
    final title = question.trim();
    final detail = description.trim();
    final answers = options.map((value) => value.trim()).toList();
    if (title.isEmpty ||
        title.length > 140 ||
        detail.length > 400 ||
        answers.length < 2 ||
        answers.length > 8 ||
        answers.any((answer) => answer.isEmpty || answer.length > 80) ||
        answers.map((answer) => answer.toLowerCase()).toSet().length !=
            answers.length ||
        (correctOption != null &&
            (multiple ||
                correctOption < 0 ||
                correctOption >= answers.length)) ||
        (durationMinutes != null &&
            (durationMinutes < 1 || durationMinutes > 10080))) {
      throw const FormatException(
          'Use uma pergunta e de duas a oito opções distintas.');
    }
    return DirectPollSpec._(
      question: title,
      description: detail,
      options: List.unmodifiable(answers),
      multiple: multiple,
      allowRevote: allowRevote,
      hideResults: hideResults,
      shuffle: shuffle,
      correctOption: correctOption,
      durationMinutes: durationMinutes,
    );
  }

  bool accepts(List<int> choices) =>
      choices.isNotEmpty &&
      (multiple || choices.length == 1) &&
      choices.toSet().length == choices.length &&
      choices.every((index) => index >= 0 && index < options.length);

  @override
  Map<String, Object?> toJson() => {
        'type': 'open',
        'question': question,
        'description': description,
        'options': options,
        'multiple': multiple,
        'revote': allowRevote,
        'hidden': hideResults,
        'shuffle': shuffle,
        'correct': correctOption,
        'minutes': durationMinutes,
      };
}

final class DirectPollVote extends DirectPollEvent {
  const DirectPollVote({
    required this.pollId,
    required this.revision,
    required this.options,
  });

  final String pollId;
  final int revision;
  final List<int> options;

  @override
  Map<String, Object?> toJson() => {
        'type': 'vote',
        'poll': pollId,
        'revision': revision,
        'options': options,
      };
}

final class DirectPollClose extends DirectPollEvent {
  const DirectPollClose({
    required this.pollId,
    required this.creatorChoices,
    required this.peerChoices,
  });

  final String pollId;
  final List<int> creatorChoices;
  final List<int> peerChoices;

  @override
  Map<String, Object?> toJson() => {
        'type': 'close',
        'poll': pollId,
        'creator': creatorChoices,
        'peer': peerChoices,
      };
}

class DirectPollState {
  DirectPollState._(
      this.id, this.creatorId, this.peerId, this.spec, this.createdAt);

  final String id;
  final String creatorId;
  final String peerId;
  final DirectPollSpec spec;
  final DateTime createdAt;
  final _votes = <String, ({DirectPollVote vote, bool pending})>{};
  DirectPollClose? _close;
  bool _closePending = false;

  bool get closed => _close != null;
  DateTime? get deadline => spec.durationMinutes == null
      ? null
      : createdAt.add(Duration(minutes: spec.durationMinutes!));

  bool acceptsVotesAt(DateTime time) =>
      !closed && (deadline?.isAfter(time) ?? true);

  List<int> optionsFor(String actor) {
    final indexes = List.generate(spec.options.length, (index) => index);
    if (!spec.shuffle) return indexes;
    final order = [
      for (final index in indexes)
        crypto.sha256
            .convert(utf8.encode(jsonEncode([id, actor, index])))
            .toString(),
    ];
    return indexes..sort((left, right) => order[left].compareTo(order[right]));
  }

  List<int> choicesOf(String actor) {
    if (_close case final close?) {
      if (actor == creatorId) return close.creatorChoices;
      if (actor == peerId) return close.peerChoices;
      return const [];
    }
    return _votes[actor]?.vote.options ?? const [];
  }

  bool pendingFor(String actor) => closed
      ? actor == creatorId && _closePending
      : _votes[actor]?.pending ?? false;

  List<int> get counts => List.generate(
        spec.options.length,
        (index) => [creatorId, peerId]
            .where((actor) => choicesOf(actor).contains(index))
            .length,
      );

  DirectPollVote makeVote(String actor, List<int> options, DateTime now) {
    final prior = _votes[actor]?.vote.revision ?? 0;
    if ((actor != creatorId && actor != peerId) ||
        !acceptsVotesAt(now) ||
        !spec.accepts(options) ||
        (prior > 0 && !spec.allowRevote) ||
        prior >= 1000) {
      throw StateError('A enquete não aceita este voto.');
    }
    return DirectPollVote(pollId: id, revision: prior + 1, options: options);
  }

  DirectPollClose makeClose(String actor) {
    if (actor != creatorId || closed) {
      throw StateError('Só o autor pode encerrar uma enquete aberta.');
    }
    return DirectPollClose(
      pollId: id,
      creatorChoices: choicesOf(creatorId),
      peerChoices: choicesOf(peerId),
    );
  }

  static Map<String, DirectPollState> project(
    Iterable<Map<String, Object?>> rows, {
    required String localId,
    required String remoteId,
  }) {
    final polls = <String, DirectPollState>{};
    final entries = <({
      String id,
      DirectPollEvent event,
      String actor,
      DateTime time,
      bool pending
    })>[];
    for (final row in rows) {
      final actor = row['author_key'];
      final id = row['id'];
      final body = row['body'];
      final stamp = row['created_at'];
      if ((actor != localId && actor != remoteId) ||
          actor is! String ||
          body is! String ||
          id is! String ||
          stamp is! int ||
          !DirectPollEvent.acceptsTimestamp(stamp)) continue;
      final time = DateTime.fromMillisecondsSinceEpoch(stamp, isUtc: true);
      final event = DirectPollEvent.parse(body);
      if (event == null) continue;
      if (event is DirectPollSpec) {
        polls[id] = DirectPollState._(
            id, actor, actor == localId ? remoteId : localId, event, time);
      } else {
        final status = row['delivery_state'];
        entries.add((
          id: id,
          event: event,
          actor: actor,
          time: time,
          pending:
              actor == localId && status != 'accepted' && status != 'delivered',
        ));
      }
    }
    // Um fechamento é a fotografia dos votos que o autor recebeu até encerrar.
    // A ordem de entrega e o relógio do interlocutor não alteram a fotografia.
    entries.sort((left, right) => left.id.compareTo(right.id));
    for (final entry in entries) {
      switch (entry.event) {
        case DirectPollSpec():
          break;
        case DirectPollVote(:final pollId, :final revision, :final options):
          final poll = polls[pollId];
          if (poll == null ||
              !poll.spec.accepts(options) ||
              (!poll.spec.allowRevote && revision != 1) ||
              (poll.deadline?.compareTo(entry.time) ?? 1) <= 0) continue;
          final previous = poll._votes[entry.actor];
          if (previous != null && previous.vote.revision >= revision) continue;
          poll._votes[entry.actor] = (
            vote: entry.event as DirectPollVote,
            pending: entry.pending,
          );
        case DirectPollClose(
            :final pollId,
            :final creatorChoices,
            :final peerChoices
          ):
          final poll = polls[pollId];
          if (poll == null ||
              poll.closed ||
              entry.actor != poll.creatorId ||
              (creatorChoices.isNotEmpty &&
                  !poll.spec.accepts(creatorChoices)) ||
              (peerChoices.isNotEmpty && !poll.spec.accepts(peerChoices)))
            continue;
          poll._close = entry.event as DirectPollClose;
          poll._closePending = entry.pending;
      }
    }
    return polls;
  }
}
