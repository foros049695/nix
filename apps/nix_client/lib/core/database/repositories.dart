import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'local_database.dart';

/// Repositório para identidades locais, dispositivos e cards públicos emitidos.
class IdentityRepository {
  final LocalDatabase _database;
  IdentityRepository(this._database);

  Database get _db => _database.rawDatabase;

  /// Registra uma nova identidade soberana no banco.
  Future<void> createIdentity({
    required String id,
    required String publicId,
    required Uint8List edPublic,
    required Uint8List xPublic,
    required String keyRef,
    int? createdAt,
  }) async {
    final now = createdAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert('identities', {
      'id': id,
      'public_id': publicId,
      'ed_public': edPublic,
      'x_public': xPublic,
      'key_ref': keyRef,
      'created_at': now,
    });
  }

  /// Retorna a identidade primária cadastrada no cliente (ou null se ainda não criada).
  Future<Map<String, dynamic>?> getPrimaryIdentity() async {
    final results = await _db.query('identities', limit: 1);
    if (results.isEmpty) return null;
    return results.first;
  }

  /// Registra um dispositivo associado a uma identidade.
  Future<void> registerDevice({
    required String deviceId,
    required String identityId,
    required Uint8List signingPublic,
    required Uint8List grant,
    int? addedAt,
  }) async {
    final now = addedAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert('devices', {
      'id': deviceId,
      'identity_id': identityId,
      'signing_public': signingPublic,
      'grant': grant,
      'added_at': now,
    });
  }

  /// Salva ou atualiza o perfil associado à identidade.
  Future<void> saveProfile({
    required String identityId,
    required String displayName,
    required String bio,
    String? avatarObjectId,
    String visibility = 'contacts',
    int revision = 1,
  }) async {
    await _db.insert(
      'profiles',
      {
        'identity_id': identityId,
        'display_name': displayName,
        'bio': bio,
        'avatar_object_id': avatarObjectId,
        'visibility': visibility,
        'revision': revision,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Recupera o perfil cadastrado.
  Future<Map<String, dynamic>?> getProfile(String identityId) async {
    final results = await _db.query(
      'profiles',
      where: 'identity_id = ?',
      whereArgs: [identityId],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return results.first;
  }
}

/// Repositório soberano de contatos e histórico de chaves verificadas.
class ContactRepository {
  final LocalDatabase _database;
  ContactRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> upsertContact({
    required String id,
    required Uint8List edPublic,
    required Uint8List xPublic,
    required String fingerprint,
    required String displayName,
    String verification = 'unverified',
    int? verifiedAt,
  }) async {
    await _db.insert(
      'contacts',
      {
        'id': id,
        'ed_public': edPublic,
        'x_public': xPublic,
        'fingerprint': fingerprint,
        'display_name': displayName,
        'verification': verification,
        'verified_at': verifiedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> listContacts() async {
    return _db.query('contacts', orderBy: 'display_name ASC');
  }

  Future<void> updateVerification(String id, String verificationStatus) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.update(
      'contacts',
      {
        'verification': verificationStatus,
        'verified_at': verificationStatus == 'verified' ? now : null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

/// Repositório de conversas, pastas e participantes.
class ConversationRepository {
  final LocalDatabase _database;
  ConversationRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> createConversation({
    required String id,
    required String kind,
    required String ownerIdentityId,
    required String title,
    int epoch = 0,
    int? createdAt,
  }) async {
    final now = createdAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert('conversations', {
      'id': id,
      'kind': kind,
      'owner_identity_id': ownerIdentityId,
      'title': title,
      'epoch': epoch,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<List<Map<String, dynamic>>> listConversations() async {
    return _db.query('conversations', orderBy: 'updated_at DESC');
  }

  Future<void> addMember({
    required String conversationId,
    required String memberKey,
    required String deviceId,
    String role = 'member',
    int joinedEpoch = 0,
  }) async {
    await _db.insert('members', {
      'conversation_id': conversationId,
      'member_key': memberKey,
      'device_id': deviceId,
      'role': role,
      'joined_epoch': joinedEpoch,
    });
  }

  Future<void> createFolder({
    required String id,
    required String name,
    required int position,
  }) async {
    await _db.insert('folders', {
      'id': id,
      'name': name,
      'position': position,
    });
  }

  Future<List<Map<String, dynamic>>> listFolders() async {
    return _db.query('folders', orderBy: 'position ASC');
  }
}

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

  Future<void> updateDeliveryState(String messageId, String newState) async {
    await _db.update(
      'messages',
      {'delivery_state': newState},
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
    Uint8List? payloadHash,
    int nextAttemptAt = 0,
  }) async {
    final hash = payloadHash ??
        Uint8List.fromList(crypto.sha256.convert(ciphertext).bytes);
    await _db.insert('outbox', {
      'id': id,
      'destination_mailbox': destinationMailbox,
      'ciphertext': ciphertext,
      'payload_hash': hash,
      'transport_state': 'queued',
      'attempts': 0,
      'next_attempt_at': nextAttemptAt,
      'expires_at': expiresAt,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingEnvelopes({int limit = 10}) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return _db.query(
      'outbox',
      where: 'transport_state IN (?, ?) AND next_attempt_at <= ? AND expires_at > ?',
      whereArgs: ['queued', 'leased', now, now],
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

  Future<void> markEnvelopeFailed(String id, int retryDelayMs) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.rawUpdate('''
      UPDATE outbox
      SET attempts = attempts + 1,
          transport_state = 'failed',
          next_attempt_at = ?
      WHERE id = ?;
    ''', [now + retryDelayMs, id]);
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

/// Repositório de acervo cultural privado e indexação FTS5.
class MediaRepository {
  final LocalDatabase _database;
  MediaRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> upsertMediaItem({
    required String id,
    required String kind,
    required String title,
    String? parentId,
    Map<String, dynamic> metadata = const {},
    String? source,
    String? sourceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert(
      'media_items',
      {
        'id': id,
        'kind': kind,
        'title': title,
        'parent_id': parentId,
        'metadata_json': jsonEncode(metadata),
        'source': source,
        'source_id': sourceId,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> listMediaItems({int limit = 50}) async {
    return _db.query('media_items', orderBy: 'updated_at DESC', limit: limit);
  }

  Future<List<Map<String, dynamic>>> searchMedia(String queryTerm) async {
    final clean = queryTerm.trim();
    if (clean.isEmpty) return [];
    // Trata a busca como frase literal, inclusive hífens e aspas internas.
    final safeTerm = '"${clean.replaceAll('"', '""')}"';
    return _db.rawQuery('''
      SELECT m.* FROM media_items m
      JOIN media_search ms ON m.id = ms.media_id
      WHERE media_search MATCH ?
      ORDER BY m.updated_at DESC LIMIT 30;
    ''', [safeTerm]);
  }
}

/// Repositório de preferências do cliente armazenadas de forma cifrada na tabela `preferences`.
class PreferencesRepository {
  final LocalDatabase _database;
  PreferencesRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> setOption(String key, dynamic value, {int revision = 1}) async {
    await _db.insert(
      'preferences',
      {
        'key': key,
        'value_json': jsonEncode(value),
        'revision': revision,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<dynamic> getOption(String key) async {
    final rows = await _db.query(
      'preferences',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final jsonStr = rows.first['value_json'] as String;
    return jsonDecode(jsonStr);
  }
}
