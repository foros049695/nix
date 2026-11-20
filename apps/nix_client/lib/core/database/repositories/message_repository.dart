import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../local_database.dart';

/// Repositório de mensagens com suporte a eventos de causualidade, reações e busca FTS5.
class MessageRepository {
  final LocalDatabase _database;
  MessageRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> insertMessage({
    required String id,
    required String conversationId,
    required String authorKey,
    required String deviceId,
    required String body,
    String deliveryState = 'draft',
    String? replyToId,
    int? createdAt,
    int? expiresAt,
  }) async {
    final now = createdAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert('messages', {
      'id': id,
      'conversation_id': conversationId,
      'author_key': authorKey,
      'device_id': deviceId,
      'body': body,
      'created_at': now,
      'received_at': now,
      'expires_at': expiresAt,
      'revision': 1,
      'delivery_state': deliveryState,
      'reply_to_id': replyToId,
    });

    // Atualiza o timestamp da conversa
    await _db.update(
      'conversations',
      {'updated_at': now},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<List<Map<String, dynamic>>> getMessagesForConversation(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) async {
    return _db.query(
      'messages',
      where: 'conversation_id = ? AND delivery_state != ?',
      whereArgs: [conversationId, 'deleted'],
      orderBy: 'created_at ASC',
      limit: limit,
      offset: offset,
    );
  }

  Future<List<Map<String, dynamic>>> getLatestMessagesForConversation(
      String conversationId,
      {int limit = 200}) async {
    final recent = await _db.query(
      'messages',
      where: 'conversation_id = ? AND delivery_state != ?',
      whereArgs: [conversationId, 'deleted'],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return recent.reversed.toList();
  }

  Future<List<Map<String, Object?>>> getProtocolMessages(
    String conversationId,
    String prefix,
  ) =>
      _db.query(
        'messages',
        columns: ['id', 'author_key', 'created_at', 'body', 'delivery_state'],
        where:
            'conversation_id = ? AND delivery_state != ? AND expires_at IS NULL '
            'AND substr(body, 1, ?) = ?',
        whereArgs: [conversationId, 'deleted', prefix.length, prefix],
        orderBy: 'created_at DESC, id DESC',
        limit: 2048,
      );

  Future<void> updateDeliveryState(String messageId, String newState) async {
    await _db.update(
      'messages',
      {'delivery_state': newState},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Remove ou marca como expiradas todas as mensagens cujo prazo TTL venceu.
  Future<int> sweepExpiredMessages({int? nowMs}) async {
    final now = nowMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    return _db.delete(
      'messages',
      where: 'expires_at IS NOT NULL AND expires_at <= ?',
      whereArgs: [now],
    );
  }

  /// Apaga uma mensagem localmente (ex: recebimento de evento remoto de exclusão/burn).
  Future<void> markMessageDeleted(String messageId, {int? deletedAt}) async {
    final now = deletedAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.update(
      'messages',
      {
        'body': null,
        'delivery_state': 'deleted',
        'deleted_at': now,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Busca de texto integral via tabela virtual FTS5 indexada pelo SQLite.
  Future<List<Map<String, dynamic>>> searchMessages(String queryTerm) async {
    final clean = queryTerm.trim();
    if (clean.isEmpty) return [];
    // Envolve termo entre aspas para compatibilidade segura com hífens e operadores do FTS5
    final safeTerm = '"${clean.replaceAll('"', '""')}"';
    return _db.rawQuery('''
      SELECT m.* FROM messages m
      JOIN message_search ms ON m.id = ms.message_id
      WHERE message_search MATCH ?
      ORDER BY m.created_at DESC LIMIT 30;
    ''', [safeTerm]);
  }
}
