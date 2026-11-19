import 'dart:typed_data';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../local_database.dart';

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
