import 'dart:typed_data';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../local_database.dart';

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
