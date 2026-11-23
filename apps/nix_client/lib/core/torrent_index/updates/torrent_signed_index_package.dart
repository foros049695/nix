import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:cryptography/cryptography.dart';
import '../database/torrent_index_database.dart';
import '../models/torrent_record.dart';

class TorrentPackageVerificationException implements Exception {
  final String message;
  const TorrentPackageVerificationException(this.message);
  @override
  String toString() => 'TorrentPackageVerificationException: $message';
}

class TorrentPackageRollbackException implements Exception {
  final String message;
  const TorrentPackageRollbackException(this.message);
  @override
  String toString() => 'TorrentPackageRollbackException: $message';
}

/// Manifesto descritivo de um pacote assinado de atualização do índice offline.
class TorrentPackageManifest {
  final int version;
  final String payloadSha256;
  final int recordsCount;
  final DateTime publishedAt;
  final String signatureHex;
  final String signerPublicKeyHex;

  const TorrentPackageManifest({
    required this.version,
    required this.payloadSha256,
    required this.recordsCount,
    required this.publishedAt,
    required this.signatureHex,
    required this.signerPublicKeyHex,
  });

  Map<String, dynamic> toMap() => {
    'version': version,
    'payloadSha256': payloadSha256,
    'recordsCount': recordsCount,
    'publishedAt': publishedAt.toIso8601String(),
    'signatureHex': signatureHex,
    'signerPublicKeyHex': signerPublicKeyHex,
  };

  factory TorrentPackageManifest.fromMap(Map<String, dynamic> map) {
    return TorrentPackageManifest(
      version: map['version'] as int? ?? 1,
      payloadSha256: map['payloadSha256'] as String? ?? '',
      recordsCount: map['recordsCount'] as int? ?? 0,
      publishedAt: DateTime.tryParse(map['publishedAt'] as String? ?? '') ?? DateTime.now(),
      signatureHex: map['signatureHex'] as String? ?? '',
      signerPublicKeyHex: map['signerPublicKeyHex'] as String? ?? '',
    );
  }
}

/// Gerenciador de pacotes assinados offline do Nix Torrent Index.
/// Validação estrita por SHA-256 e Ed25519 com proteção contra rollback de versão.
class TorrentSignedIndexPackage {
  static const String officialSignerPublicKeyHex =
      'a805baa55178d7c0220a9d586a56db6359521455e3b66d9abf914b829a47f045';

  final TorrentPackageManifest manifest;
  final List<TorrentIndexRecord> records;

  const TorrentSignedIndexPackage({
    required this.manifest,
    required this.records,
  });

  /// Verifica se os bytes brutos do payload correspondem exatamente ao hash SHA-256 do manifesto.
  static bool verifyPayloadHash(Uint8List payloadBytes, String expectedSha256Hex) {
    final digest = std_crypto.sha256.convert(payloadBytes);
    return digest.toString().toLowerCase() == expectedSha256Hex.toLowerCase();
  }

  /// Verifica a assinatura criptográfica Ed25519 do manifesto sobre os bytes do payload.
  static Future<bool> verifyEd25519Signature({
    required Uint8List payloadBytes,
    required String signatureHex,
    required String publicKeyHex,
  }) async {
    try {
      final sigBytes = _hexToBytes(signatureHex);
      final pubBytes = _hexToBytes(publicKeyHex);
      if (sigBytes.length != 64 || pubBytes.length != 32) return false;

      final algorithm = Ed25519();
      final pubKey = SimplePublicKey(pubBytes, type: KeyPairType.ed25519);
      final signature = Signature(sigBytes, publicKey: pubKey);

      return await algorithm.verify(payloadBytes, signature: signature);
    } catch (_) {
      return false;
    }
  }

  /// Aplica a atualização assinada no banco de dados com proteção contra rollback e transação atômica.
  static Future<void> applyPackage({
    required TorrentIndexDatabase db,
    required TorrentPackageManifest manifest,
    required Uint8List payloadBytes,
    Set<String> trustedPublicKeys = const {officialSignerPublicKeyHex},
  }) async {
    // 1. Verificação da chave pública confiável
    if (!trustedPublicKeys.contains(manifest.signerPublicKeyHex.toLowerCase())) {
      throw const TorrentPackageVerificationException('Chave pública de assinatura não autorizada.');
    }

    // 2. Verificação de integridade por SHA-256
    if (!verifyPayloadHash(payloadBytes, manifest.payloadSha256)) {
      throw const TorrentPackageVerificationException('Hash SHA-256 do payload não confere com o manifesto.');
    }

    // 3. Verificação da assinatura Ed25519
    final isSigValid = await verifyEd25519Signature(
      payloadBytes: payloadBytes,
      signatureHex: manifest.signatureHex,
      publicKeyHex: manifest.signerPublicKeyHex,
    );
    if (!isSigValid) {
      throw const TorrentPackageVerificationException('Assinatura Ed25519 inválida para o pacote de índice.');
    }

    // 4. Proteção contra rollback de versão
    final currentVerStr = await db.getMeta('current_package_version');
    final currentVer = int.tryParse(currentVerStr ?? '0') ?? 0;
    if (manifest.version <= currentVer) {
      throw TorrentPackageRollbackException(
        'Versão do pacote (${manifest.version}) é menor ou igual à versão instalada ($currentVer). Atualização rejeitada.',
      );
    }

    // 5. Decodifica os registros do payload
    final jsonString = utf8.decode(payloadBytes);
    final rawList = jsonDecode(jsonString) as List<dynamic>;
    final records = rawList
        .whereType<Map<String, dynamic>>()
        .map((m) => TorrentIndexRecord.fromMap(m))
        .toList();

    // 6. Aplica atomicamente no banco
    await db.upsertRecords(records);
    await db.setMeta('current_package_version', manifest.version.toString());
    await db.setMeta('last_sync_date', DateTime.now().toIso8601String());
    await db.setMeta('last_manifest_sha256', manifest.payloadSha256);
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.replaceAll(' ', '').trim();
    final result = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < clean.length; i += 2) {
      result[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}
