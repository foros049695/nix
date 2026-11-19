import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../local_database.dart';

/// Repositório de fila de saída (Outbox), anti-replay e deduplicação de mensagens (P0-2 / P0-5).
class OutboxRepository {
  final LocalDatabase _database;
  OutboxRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> enqueue({
    required String id,
    required String destinationMailbox,
    required Uint8List ciphertext,
    required int expiresAt,
    String? messageId,
    String? sessionId,
    Uint8List? payloadHash,
    int nextAttemptAt = 0,
  }) async {
    final hash = payloadHash ??
        Uint8List.fromList(crypto.sha256.convert(ciphertext).bytes);
    await _db.insert('outbox', {
      'id': id,
      'message_id': messageId,
      'session_id': sessionId,
      'destination_mailbox': destinationMailbox,
      'ciphertext': ciphertext,
      'payload_hash': hash,
      'transport_state': 'queued',
      'attempts': 0,
      'next_attempt_at': nextAttemptAt,
      'expires_at': expiresAt,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingEnvelopes({
    int limit = 10,
    int maxAttempts = 20,
    int? nowMs,
  }) async {
    final now = nowMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    return _db.query(
      'outbox',
      where:
          'transport_state IN (?, ?, ?) AND attempts < ? AND next_attempt_at <= ? AND expires_at > ?',
      whereArgs: ['queued', 'leased', 'failed', maxAttempts, now, now],
      orderBy: 'next_attempt_at ASC',
      limit: limit,
    );
  }

  Future<void> markEnvelopeAccepted(String id, String relayEnvelopeId) async {
    await _db.update(
      'outbox',
      {
        'transport_state': 'accepted',
        'relay_envelope_id': relayEnvelopeId,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markEnvelopeFailed(
    String id,
    int retryDelayMs, {
    bool permanent = false,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final nextState = permanent ? 'failed' : 'queued';
    await _db.rawUpdate('''
      UPDATE outbox
      SET attempts = attempts + 1,
          transport_state = ?,
          next_attempt_at = ?
      WHERE id = ?;
    ''', [nextState, now + retryDelayMs, id]);
  }

  /// Verifica se já processamos uma mensagem recebida para evitar replays (inbox_dedup).
  Future<bool> isDuplicateEnvelope(String mailboxId, String deliveryId) async {
    final results = await _db.query(
      'inbox_dedup',
      where: 'mailbox_id = ? AND delivery_id = ?',
      whereArgs: [mailboxId, deliveryId],
      limit: 1,
    );
    return results.isNotEmpty;
  }

  /// Registra o recebimento atômico no inbox_dedup para deduplicação.
  Future<void> recordDeduplication({
    required String mailboxId,
    required String deliveryId,
    required Uint8List payloadHash,
    required int expiresAt,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert(
      'inbox_dedup',
      {
        'mailbox_id': mailboxId,
        'delivery_id': deliveryId,
        'payload_hash': payloadHash,
        'committed_at': now,
        'expires_at': expiresAt,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
