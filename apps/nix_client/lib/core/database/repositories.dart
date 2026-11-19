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

  /// Lista dispositivos associados a uma identidade.
  Future<List<Map<String, dynamic>>> listDevices(String identityId) async {
    return _db.query(
      'devices',
      where: 'identity_id = ? AND revoked_at IS NULL',
      whereArgs: [identityId],
      orderBy: 'added_at ASC',
    );
  }

  /// Persiste card público assinado (tabela `cards`) para troca out-of-band / QR.
  Future<void> saveCard({
    required String id,
    required String identityId,
    required int revision,
    required Uint8List publicBundle,
    required Uint8List signature,
    required int expiresAt,
  }) async {
    await _db.insert(
      'cards',
      {
        'id': id,
        'identity_id': identityId,
        'revision': revision,
        'public_bundle': publicBundle,
        'signature': signature,
        'expires_at': expiresAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retorna a revisão mais recente de card emitida para a identidade.
  Future<Map<String, dynamic>?> getLatestCard(String identityId) async {
    final rows = await _db.query(
      'cards',
      where: 'identity_id = ?',
      whereArgs: [identityId],
      orderBy: 'revision DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
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

  Future<Map<String, dynamic>?> getContact(String id) async {
    final rows = await _db.query(
      'contacts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> appendKeyHistory({
    required String contactId,
    required int version,
    required Uint8List bundle,
    int? acceptedAt,
  }) async {
    await _db.insert(
      'contact_key_history',
      {
        'contact_id': contactId,
        'version': version,
        'bundle': bundle,
        'accepted_at': acceptedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getKeyHistory(String contactId) async {
    return _db.query(
      'contact_key_history',
      where: 'contact_id = ?',
      whereArgs: [contactId],
      orderBy: 'version DESC',
    );
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

  Future<Map<String, dynamic>?> getConversation(String id) async {
    final rows = await _db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateConversationEpoch(String id, int newEpoch) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.update(
      'conversations',
      {'epoch': newEpoch, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> addMember({
    required String conversationId,
    required String memberKey,
    required String deviceId,
    String role = 'member',
    int joinedEpoch = 0,
  }) async {
    await _db.insert(
      'members',
      {
        'conversation_id': conversationId,
        'member_key': memberKey,
        'device_id': deviceId,
        'role': role,
        'joined_epoch': joinedEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeMember({
    required String conversationId,
    required String memberKey,
    required String deviceId,
    required int leftEpoch,
  }) async {
    await _db.update(
      'members',
      {'left_epoch': leftEpoch},
      where: 'conversation_id = ? AND member_key = ? AND device_id = ?',
      whereArgs: [conversationId, memberKey, deviceId],
    );
  }

  Future<List<Map<String, dynamic>>> listMembers(
    String conversationId, {
    bool activeOnly = true,
  }) async {
    return _db.query(
      'members',
      where: activeOnly
          ? 'conversation_id = ? AND left_epoch IS NULL'
          : 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<void> createFolder({
    required String id,
    required String name,
    required int sortOrder,
  }) async {
    await _db.insert('folders', {
      'id': id,
      'name': name,
      'sort_order': sortOrder,
    });
  }

  Future<List<Map<String, dynamic>>> listFolders() async {
    return _db.query('folders', orderBy: 'sort_order ASC');
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
    if (queryTerm.trim().isEmpty) return [];
    final sanitized = queryTerm.replaceAll("'", "''").replaceAll('"', '""');
    return _db.rawQuery('''
      SELECT m.* FROM media_items m
      JOIN media_search ms ON m.id = ms.media_id
      WHERE media_search MATCH ?
      ORDER BY m.updated_at DESC LIMIT 30;
    ''', [sanitized]);
  }

  Future<void> deleteMediaItem(String id) async {
    await _db.delete('media_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> upsertLibraryEntry({
    required String identityId,
    required String mediaId,
    String status = 'saved',
    Map<String, dynamic> progress = const {},
    int? rating,
    bool publicInCard = false,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert(
      'library_entries',
      {
        'identity_id': identityId,
        'media_id': mediaId,
        'status': status,
        'progress_json': jsonEncode(progress),
        'rating': rating,
        'public_in_card': publicInCard ? 1 : 0,
        'saved_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> listLibraryEntries(String identityId) async {
    return _db.rawQuery('''
      SELECT l.*, m.kind, m.title, m.metadata_json, m.source, m.source_id
      FROM library_entries l
      JOIN media_items m ON m.id = l.media_id
      WHERE l.identity_id = ?
      ORDER BY l.saved_at DESC;
    ''', [identityId]);
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

/// Repositório para armazenamento envelopado de material criptográfico (`key_material`).
class KeyMaterialRepository {
  final LocalDatabase _database;
  KeyMaterialRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> storeKeyMaterial({
    required String id,
    required String purpose,
    required Uint8List wrappedBytes,
    required String wrappingKeyRef,
    int formatVersion = 1,
    int? createdAt,
  }) async {
    final now = createdAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert(
      'key_material',
      {
        'id': id,
        'purpose': purpose,
        'wrapped_bytes': wrappedBytes,
        'wrapping_key_ref': wrappingKeyRef,
        'format_version': formatVersion,
        'created_at': now,
        'retired_at': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getKeyMaterial(String id) async {
    final rows = await _db.query(
      'key_material',
      where: 'id = ? AND retired_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> retireKeyMaterial(String id, {int? retiredAt}) async {
    final now = retiredAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.update(
      'key_material',
      {'retired_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

/// Repositório de pré-chaves X3DH locais (`prekeys`).
class PreKeyRepository {
  final LocalDatabase _database;
  PreKeyRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> storePreKey({
    required String id,
    required String identityId,
    required String deviceId,
    required String kind,
    required Uint8List publicBytes,
    required String keyRef,
    Uint8List? signature,
    required int expiresAt,
  }) async {
    await _db.insert(
      'prekeys',
      {
        'id': id,
        'identity_id': identityId,
        'device_id': deviceId,
        'kind': kind,
        'public_bytes': publicBytes,
        'key_ref': keyRef,
        'signature': signature,
        'expires_at': expiresAt,
        'consumed_at': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getPreKey(String id) async {
    final rows = await _db.query(
      'prekeys',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> consumePreKey(String id, {int? consumedAt}) async {
    final now = consumedAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.update(
      'prekeys',
      {'consumed_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

/// Repositório de sessões Double Ratchet, chaves puladas (`skipped_keys`) e nonces anti-replay.
class SessionRepository {
  final LocalDatabase _database;
  SessionRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> saveSession({
    required String id,
    required String conversationId,
    required String localDeviceId,
    required String peerDeviceId,
    required Uint8List stateBlob,
    int formatVersion = 1,
    int revision = 0,
    int? updatedAt,
  }) async {
    final now = updatedAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert(
      'sessions',
      {
        'id': id,
        'conversation_id': conversationId,
        'local_device_id': localDeviceId,
        'peer_device_id': peerDeviceId,
        'state_blob': stateBlob,
        'format_version': formatVersion,
        'revision': revision,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getSessionByConversation(
    String conversationId, {
    String? peerDeviceId,
  }) async {
    final rows = await _db.query(
      'sessions',
      where: peerDeviceId == null
          ? 'conversation_id = ?'
          : 'conversation_id = ? AND peer_device_id = ?',
      whereArgs: peerDeviceId == null
          ? [conversationId]
          : [conversationId, peerDeviceId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> listSessions() async {
    return _db.query('sessions', orderBy: 'updated_at DESC');
  }

  Future<void> storeSkippedKey({
    required String sessionId,
    required Uint8List ratchetPublic,
    required int messageNo,
    required Uint8List wrappedKey,
    required int expiresAt,
  }) async {
    await _db.insert(
      'skipped_keys',
      {
        'session_id': sessionId,
        'ratchet_public': ratchetPublic,
        'message_no': messageNo,
        'wrapped_key': wrappedKey,
        'expires_at': expiresAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Uint8List?> takeSkippedKey({
    required String sessionId,
    required Uint8List ratchetPublic,
    required int messageNo,
  }) async {
    final rows = await _db.query(
      'skipped_keys',
      where: 'session_id = ? AND ratchet_public = ? AND message_no = ?',
      whereArgs: [sessionId, ratchetPublic, messageNo],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    await _db.delete(
      'skipped_keys',
      where: 'session_id = ? AND ratchet_public = ? AND message_no = ?',
      whereArgs: [sessionId, ratchetPublic, messageNo],
    );
    return Uint8List.fromList(rows.first['wrapped_key'] as List<int>);
  }

  Future<int> purgeExpiredSkippedKeys({int? nowMs}) async {
    final now = nowMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    return _db.delete(
      'skipped_keys',
      where: 'expires_at <= ?',
      whereArgs: [now],
    );
  }

  Future<bool> hasReplayNonce({
    required String issuerKey,
    required String recordType,
    required Uint8List nonce,
  }) async {
    final rows = await _db.query(
      'replay_nonces',
      where: 'issuer_key = ? AND record_type = ? AND nonce = ?',
      whereArgs: [issuerKey, recordType, nonce],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> recordReplayNonce({
    required String issuerKey,
    required String recordType,
    required Uint8List nonce,
    required int expiresAt,
  }) async {
    await _db.insert(
      'replay_nonces',
      {
        'issuer_key': issuerKey,
        'record_type': recordType,
        'nonce': nonce,
        'expires_at': expiresAt,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}

/// Repositório de objetos binários fragmentados (chunks) e anexos cifrados E2EE.
class ObjectChunkRepository {
  final LocalDatabase _database;
  ObjectChunkRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> upsertObject({
    required String id,
    required Uint8List sha256Digest,
    required String mimeType,
    required int byteSize,
    required String keyRef,
    required String encryptedPath,
    int? createdAt,
    int? expiresAt,
  }) async {
    final now = createdAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert(
      'objects',
      {
        'id': id,
        'sha256': sha256Digest,
        'mime_type': mimeType,
        'byte_size': byteSize,
        'key_ref': keyRef,
        'encrypted_path': encryptedPath,
        'created_at': now,
        'expires_at': expiresAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getObject(String id) async {
    final rows = await _db.query(
      'objects',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsertChunk({
    required String objectId,
    required int chunkNo,
    required Uint8List ciphertextHash,
    required int cipherSize,
    required String encryptedPath,
  }) async {
    await _db.insert(
      'object_chunks',
      {
        'object_id': objectId,
        'chunk_no': chunkNo,
        'ciphertext_hash': ciphertextHash,
        'cipher_size': cipherSize,
        'encrypted_path': encryptedPath,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getChunks(String objectId) async {
    return _db.query(
      'object_chunks',
      where: 'object_id = ?',
      whereArgs: [objectId],
      orderBy: 'chunk_no ASC',
    );
  }

  Future<void> linkAttachment({
    required String messageId,
    required String objectId,
    required String fileName,
    int ordinal = 0,
  }) async {
    await _db.insert(
      'attachments',
      {
        'message_id': messageId,
        'object_id': objectId,
        'file_name': fileName,
        'ordinal': ordinal,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAttachmentsForMessage(
    String messageId,
  ) async {
    return _db.rawQuery('''
      SELECT a.*, o.sha256, o.mime_type, o.byte_size, o.key_ref, o.encrypted_path
      FROM attachments a
      JOIN objects o ON o.id = a.object_id
      WHERE a.message_id = ?
      ORDER BY a.ordinal ASC;
    ''', [messageId]);
  }
}

/// Repositório para Nix Archive: personas assinantes, objetos imutáveis canônicos,
/// alegações (claims), refutações e registros de réplicas distribuídas.
class ArchiveRepository {
  final LocalDatabase _database;
  ArchiveRepository(this._database);

  Database get _db => _database.rawDatabase;

  Future<void> upsertPersona({
    required String id,
    required Uint8List publicKey,
    required String keyRef,
  }) async {
    await _db.insert(
      'archive_personas',
      {
        'id': id,
        'public_key': publicKey,
        'key_ref': keyRef,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getPersona(String id) async {
    final rows = await _db.query(
      'archive_personas',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsertObject({
    required String hash,
    required String kind,
    required Uint8List canonicalBytes,
    required Uint8List authorPublic,
    required Uint8List signature,
    String? supersedesHash,
    String visibility = 'public',
    int? createdAt,
  }) async {
    final now = createdAt ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _db.insert(
      'archive_objects',
      {
        'hash': hash,
        'kind': kind,
        'canonical_bytes': canonicalBytes,
        'author_public': authorPublic,
        'signature': signature,
        'supersedes_hash': supersedesHash,
        'visibility': visibility,
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getObject(String hash) async {
    final rows = await _db.query(
      'archive_objects',
      where: 'hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> listObjects({
    String? kind,
    int limit = 50,
  }) async {
    return _db.query(
      'archive_objects',
      where: kind == null ? null : 'kind = ?',
      whereArgs: kind == null ? null : [kind],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<void> upsertClaim({
    required String objectHash,
    required String claimId,
    required String text,
  }) async {
    await _db.insert(
      'archive_claims',
      {
        'object_hash': objectHash,
        'claim_id': claimId,
        'text': text,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getClaimsForObject(
    String objectHash,
  ) async {
    return _db.query(
      'archive_claims',
      where: 'object_hash = ?',
      whereArgs: [objectHash],
      orderBy: 'claim_id ASC',
    );
  }

  Future<void> insertRefutation({
    required String refutationHash,
    required String targetHash,
    required String targetClaimId,
  }) async {
    await _db.insert(
      'archive_refutations',
      {
        'refutation_hash': refutationHash,
        'target_hash': targetHash,
        'target_claim_id': targetClaimId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> listRefutationsForTarget(
    String targetHash,
  ) async {
    return _db.query(
      'archive_refutations',
      where: 'target_hash = ?',
      whereArgs: [targetHash],
    );
  }

  Future<void> upsertReplica({
    required String objectHash,
    required String replicaId,
    required String endpoint,
    int? lastVerifiedAt,
    int? promisedUntil,
  }) async {
    await _db.insert(
      'archive_replicas',
      {
        'object_hash': objectHash,
        'replica_id': replicaId,
        'endpoint': endpoint,
        'last_verified_at': lastVerifiedAt,
        'promised_until': promisedUntil,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> listReplicas(String objectHash) async {
    return _db.query(
      'archive_replicas',
      where: 'object_hash = ?',
      whereArgs: [objectHash],
    );
  }
}
