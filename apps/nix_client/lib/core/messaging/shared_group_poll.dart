import 'dart:convert';

import 'direct_poll.dart';
import 'local_group_poll.dart';

/// Eventos transmitidos somente por sessões diretas de contatos verificados.
class SharedGroupPollPacket {
  static const prefix = 'nix.group-poll.v1:';
  static const maxLength = 5000;
  static final _id = RegExp(r'^[a-zA-Z0-9_-]{8,96}$');

  final String id;
  final int revision;
  final DirectPollSpec? spec;
  final DateTime? created;
  final bool closed;
  final List<int> values;

  const SharedGroupPollPacket._(
    this.id,
    this.revision,
    this.spec,
    this.created,
    this.closed,
    this.values,
  );

  bool get isBallot => spec == null;

  factory SharedGroupPollPacket.snapshot(LocalGroupPoll poll, int revision) {
    final spec = poll.spec;
    final openSpec = poll.closed
        ? spec
        : DirectPollSpec.create(
            question: spec.question,
            options: spec.options,
            description: spec.description,
            multiple: spec.multiple,
            allowRevote: spec.allowRevote,
            hideResults: spec.hideResults,
            shuffle: spec.shuffle,
            durationMinutes: spec.durationMinutes,
          );
    return SharedGroupPollPacket._(
      poll.id,
      revision,
      openSpec,
      poll.created,
      poll.closed,
      List.unmodifiable(spec.hideResults && !poll.closed
          ? List.filled(spec.options.length, 0)
          : poll.totals),
    );
  }

  factory SharedGroupPollPacket.ballot(
          String id, int revision, List<int> choices) =>
      SharedGroupPollPacket._(
          id, revision, null, null, false, List.unmodifiable(choices));

  String encode() => '$prefix${jsonEncode({
            'id': id,
            'revision': revision,
            'values': values,
            if (spec != null) ...{
              'spec': spec!.encode(),
              'created': created!.millisecondsSinceEpoch,
              'closed': closed,
            },
          })}';

  static SharedGroupPollPacket? parse(String input) {
    if (!input.startsWith(prefix) || input.length > maxLength) return null;
    try {
      final data =
          jsonDecode(input.substring(prefix.length)) as Map<String, dynamic>;
      final id = data['id'] as String;
      final revision = data['revision'] as int;
      final values = (data['values'] as List).cast<int>();
      if (!_id.hasMatch(id) ||
          revision < 1 ||
          revision > 1000000 ||
          values.isEmpty ||
          values.length > 8) return null;
      if (data.length == 3 && !data.containsKey('spec')) {
        if (values.any((value) => value < 0 || value > 7) ||
            values.toSet().length != values.length) return null;
        return SharedGroupPollPacket.ballot(id, revision, values);
      }
      if (data.length != 6) return null;
      final spec = DirectPollEvent.parse(data['spec'] as String);
      final time = data['created'] as int;
      if (spec is! DirectPollSpec ||
          !DirectPollEvent.acceptsTimestamp(time) ||
          values.length != spec.options.length ||
          values.any((value) => value < 0 || value > 51)) return null;
      return SharedGroupPollPacket._(
          id,
          revision,
          spec,
          DateTime.fromMillisecondsSinceEpoch(time, isUtc: true),
          data['closed'] as bool,
          List.unmodifiable(values));
    } catch (_) {
      return null;
    }
  }
}

class SharedGroupPollThread {
  final sent = <String, SharedGroupPollPacket>{};
  final received = <String, SharedGroupPollPacket>{};
  final sentBallots = <String, SharedGroupPollPacket>{};
  final receivedBallots = <String, SharedGroupPollPacket>{};
  final firstBallots = <String, SharedGroupPollPacket>{};

  SharedGroupPollThread.project(
    Iterable<Map<String, Object?>> rows, {
    required String self,
    required String peer,
  }) {
    for (final row in rows) {
      final actor = row['author_key'];
      final body = row['body'];
      if ((actor != self && actor != peer) ||
          body is! String ||
          row['delivery_state'] == 'failed' ||
          row['delivery_state'] == 'deleted') continue;
      final packet = SharedGroupPollPacket.parse(body);
      if (packet == null) continue;
      if (packet.isBallot && actor == peer && packet.revision == 1) {
        firstBallots.putIfAbsent(packet.id, () => packet);
      }
      final destination = packet.isBallot
          ? (actor == self ? sentBallots : receivedBallots)
          : (actor == self ? sent : received);
      final prior = destination[packet.id];
      if (prior == null || prior.revision < packet.revision) {
        destination[packet.id] = packet;
      }
    }
  }
}
