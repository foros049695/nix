import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

enum MessageRecurrence {
  once('Uma vez', Duration.zero),
  daily('A cada 24 horas', Duration(days: 1)),
  weekly('A cada 7 dias', Duration(days: 7));

  const MessageRecurrence(this.label, this.interval);

  final String label;
  final Duration interval;
}

class ScheduledMessage {
  const ScheduledMessage._({
    required this.id,
    required this.revision,
    required this.conversationId,
    required this.text,
    required this.dueAt,
    required this.recurrence,
  });

  final String id;
  final int revision;
  final String conversationId;
  final String text;
  final DateTime dueAt;
  final MessageRecurrence recurrence;

  DateTime nextAfter(DateTime now) {
    final intervalMs = recurrence.interval.inMilliseconds;
    final alreadyElapsed = now.difference(dueAt).inMilliseconds;
    return dueAt.add(Duration(
      milliseconds: (alreadyElapsed ~/ intervalMs + 1) * intervalMs,
    ));
  }

  String _encode(DateTime when) => jsonEncode({
        'conversation': conversationId,
        'text': text,
        'dueAt': when.millisecondsSinceEpoch,
        'recurrence': recurrence.name,
      });

  factory ScheduledMessage._fromRow(Map<String, Object?> row) {
    final data =
        jsonDecode(row['value_json'] as String) as Map<String, dynamic>;
    return ScheduledMessage._(
      id: row['key'] as String,
      revision: row['revision'] as int,
      conversationId: data['conversation'] as String,
      text: data['text'] as String,
      dueAt: DateTime.fromMillisecondsSinceEpoch(data['dueAt'] as int,
          isUtc: true),
      recurrence: MessageRecurrence.values.byName(data['recurrence'] as String),
    );
  }
}

/// Guarda os rascunhos no cofre local, em chaves próprias da tabela preferences.
class ScheduledMessages {
  ScheduledMessages(this._db);

  final Database _db;
  static const _prefix = 'scheduled_dm/';
  static const _whereNamespace = 'key >= ? AND key < ?';
  static const _namespace = [_prefix, 'scheduled_dm0'];

  Future<List<ScheduledMessage>> list() async {
    final rows = await _db.query('preferences',
        where: _whereNamespace, whereArgs: _namespace);
    return rows.map(ScheduledMessage._fromRow).toList()
      ..sort((left, right) => left.dueAt.compareTo(right.dueAt));
  }

  Future<ScheduledMessage> add({
    required String conversationId,
    required String text,
    required DateTime dueAt,
    required MessageRecurrence recurrence,
    required DateTime now,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || utf8.encode(trimmed).length > 16000) {
      throw const FormatException('Informe um texto de até 16 KB.');
    }
    if (!dueAt.isAfter(now)) {
      throw const FormatException('Escolha uma data e hora futuras.');
    }
    final randomId = SecretKeyData.random(length: 16)
        .bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final entry = ScheduledMessage._(
      id: '$_prefix$randomId',
      revision: 1,
      conversationId: conversationId,
      text: trimmed,
      dueAt: dueAt.toUtc(),
      recurrence: recurrence,
    );
    await _db.transaction((txn) async {
      final count = await txn.rawQuery(
        'SELECT count(*) FROM preferences WHERE $_whereNamespace',
        _namespace,
      );
      if ((count.single.values.single as int) >= 100) {
        throw StateError('Limite de 100 agendamentos por cofre.');
      }
      await txn.insert('preferences', {
        'key': entry.id,
        'revision': entry.revision,
        'value_json': entry._encode(entry.dueAt),
      });
    });
    return entry;
  }

  Future<bool> cancel(ScheduledMessage entry) async {
    final deleted = await _db
        .delete('preferences', where: 'key = ?', whereArgs: [entry.id]);
    return deleted == 1;
  }

  /// Mesma transação da mensagem, do Ratchet e da Outbox. Se alguém cancelou
  /// ou já processou esta revisão, nenhuma mensagem adicional é gravada.
  static Future<void> markEnqueued(
      Transaction txn, ScheduledMessage entry, DateTime now) async {
    const condition = 'key = ? AND revision = ?';
    final args = [entry.id, entry.revision];
    final changed = entry.recurrence == MessageRecurrence.once
        ? await txn.delete('preferences', where: condition, whereArgs: args)
        : await txn.update(
            'preferences',
            {
              'value_json': entry._encode(entry.nextAfter(now)),
              'revision': entry.revision + 1,
            },
            where: condition,
            whereArgs: args,
          );
    if (changed != 1) throw const ScheduledMessageChanged();
  }
}

class ScheduledMessageChanged implements Exception {
  const ScheduledMessageChanged();
}
