import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../local_database.dart';

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
