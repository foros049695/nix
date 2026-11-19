import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:cryptography/cryptography.dart';
import 'catalog_database.dart';

class CatalogRollbackRejectedException implements Exception {
  final String message;
  const CatalogRollbackRejectedException(this.message);
  @override
  String toString() => 'CatalogRollbackRejectedException: $message';
}

class CatalogIntegrityVerificationException implements Exception {
  final String message;
  const CatalogIntegrityVerificationException(this.message);
  @override
  String toString() => 'CatalogIntegrityVerificationException: $message';
}

/// Manifesto criptograficamente assinado com Ed25519 para pacotes de catálogo do Nix Media Index.
class SignedCatalogManifest {
  final int version;
  final String artifactName;
  final String sha256Hex;
  final int byteSize;
  final int issuedAtUnix;
  final int entryCount;
  final String signerEd25519Hex;
  final String signatureHex;

  const SignedCatalogManifest({
    required this.version,
    required this.artifactName,
    required this.sha256Hex,
    required this.byteSize,
    required this.issuedAtUnix,
    required this.entryCount,
    required this.signerEd25519Hex,
    required this.signatureHex,
  });

  static List<int> canonicalDigestBytes({
    required int version,
    required String artifactName,
    required String sha256Hex,
    required int byteSize,
    required int issuedAtUnix,
    required int entryCount,
  }) {
    return utf8.encode(jsonEncode({
      'domain': 'NIX-CATALOG-MANIFEST-V1',
      'version': version,
      'artifact': artifactName,
      'sha256': sha256Hex.toLowerCase(),
      'bytes': byteSize,
      'iat': issuedAtUnix,
      'entries': entryCount,
    }));
  }

  static Future<SignedCatalogManifest> signArtifact({
    required KeyPair signerKeyPair,
    required int version,
    required String artifactName,
    required List<int> artifactBytes,
    required int entryCount,
    int? issuedAtUnix,
  }) async {
    final iat = issuedAtUnix ??
        (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000);
    final digest = std_crypto.sha256.convert(artifactBytes).toString();
    final msg = canonicalDigestBytes(
      version: version,
      artifactName: artifactName,
      sha256Hex: digest,
      byteSize: artifactBytes.length,
      issuedAtUnix: iat,
      entryCount: entryCount,
    );

    final ed = Ed25519();
    final sig = await ed.sign(msg, keyPair: signerKeyPair);
    final pubKey = await signerKeyPair.extractPublicKey() as SimplePublicKey;

    return SignedCatalogManifest(
      version: version,
      artifactName: artifactName,
      sha256Hex: digest,
      byteSize: artifactBytes.length,
      issuedAtUnix: iat,
      entryCount: entryCount,
      signerEd25519Hex: _bytesToHex(pubKey.bytes),
      signatureHex: _bytesToHex(sig.bytes),
    );
  }

  Future<bool> verifyArtifactBytes(
    List<int> artifactBytes, {
    required SimplePublicKey trustedPublisherKey,
  }) async {
    final expectedSigner = _bytesToHex(trustedPublisherKey.bytes).toLowerCase();
    if (expectedSigner != signerEd25519Hex.toLowerCase()) {
      return false;
    }
    if (artifactBytes.length != byteSize) {
      return false;
    }
    final actualSha =
        std_crypto.sha256.convert(artifactBytes).toString().toLowerCase();
    if (actualSha != sha256Hex.toLowerCase()) {
      return false;
    }

    final msg = canonicalDigestBytes(
      version: version,
      artifactName: artifactName,
      sha256Hex: actualSha,
      byteSize: byteSize,
      issuedAtUnix: issuedAtUnix,
      entryCount: entryCount,
    );

    final ed = Ed25519();
    final sigBytes = _hexToBytes(signatureHex);
    return ed.verify(
      msg,
      signature: Signature(sigBytes, publicKey: trustedPublisherKey),
    );
  }

  Map<String, dynamic> toJson() => {
        'domain': 'NIX-CATALOG-MANIFEST-V1',
        'version': version,
        'artifact': artifactName,
        'sha256': sha256Hex,
        'byteSize': byteSize,
        'issuedAtUnix': issuedAtUnix,
        'entryCount': entryCount,
        'signerEd25519Hex': signerEd25519Hex,
        'signatureHex': signatureHex,
      };

  factory SignedCatalogManifest.fromJson(Map<String, dynamic> json) =>
      SignedCatalogManifest(
        version: json['version'] as int,
        artifactName: json['artifact'] as String,
        sha256Hex: json['sha256'] as String,
        byteSize: json['byteSize'] as int,
        issuedAtUnix: json['issuedAtUnix'] as int,
        entryCount: json['entryCount'] as int,
        signerEd25519Hex: json['signerEd25519Hex'] as String,
        signatureHex: json['signatureHex'] as String,
      );

  static String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}

/// Orquestrador de atualizações assinadas e substituição atômica do Nix Media Index.
class MediaIndexUpdater {
  /// Aplica um novo pacote de catálogo assinado com verificação estrita:
  /// 1. Rejeição anti-rollback (versão recebida <= versão instalada).
  /// 2. Verificação de integridade SHA-256 e assinatura Ed25519 contra [trustedPublisherKey].
  /// 3. Escrita em arquivo temporário `.incoming` e checagem PRAGMA integrity_check.
  /// 4. Troca atômica (swap) com backup `.bak` e rollback automático em falha.
  static Future<CatalogDatabase> applySignedCatalogPackage({
    required List<int> packageBytes,
    required SignedCatalogManifest manifest,
    required SimplePublicKey trustedPublisherKey,
    String? targetDbPath,
  }) async {
    final activePath = targetDbPath ?? CatalogDatabase.getDefaultCatalogPath();
    final targetFile = File(activePath);

    // 1. Verificação anti-rollback
    if (await targetFile.exists()) {
      try {
        final existingDb = await CatalogDatabase.open(path: activePath);
        final currentVersion = await existingDb.getVersion();
        await existingDb.close();

        if (manifest.version <= currentVersion) {
          throw CatalogRollbackRejectedException(
            '[Anti-Rollback] Versão do catálogo recebido (${manifest.version}) não é superior à versão atual ($currentVersion).',
          );
        }
      } catch (e) {
        if (e is CatalogRollbackRejectedException) rethrow;
        // Se arquivo existente estiver corrompido, permite sobrescrita pelo pacote válido
      }
    }

    // 2. Verificação da assinatura Ed25519 e digest SHA-256
    final verified = await manifest.verifyArtifactBytes(
      packageBytes,
      trustedPublisherKey: trustedPublisherKey,
    );
    if (!verified) {
      throw const CatalogIntegrityVerificationException(
        '[Fail-Closed] Falha na verificação criptográfica Ed25519 do manifesto do catálogo.',
      );
    }

    // 3. Escrita no arquivo temporário
    final incomingPath = '$activePath.incoming';
    final backupPath = '$activePath.bak';
    final incomingFile = File(incomingPath);

    if (await incomingFile.exists()) {
      await incomingFile.delete();
    }
    await incomingFile.parent.create(recursive: true);
    await incomingFile.writeAsBytes(packageBytes, flush: true);

    // Validação de integridade do SQLite incoming
    CatalogDatabase? incomingDb;
    try {
      incomingDb = await CatalogDatabase.open(path: incomingPath);
      final isOk = await incomingDb.integrityCheck();
      if (!isOk) {
        throw const CatalogIntegrityVerificationException(
          '[Fail-Closed] Arquivo do catálogo falhou na verificação PRAGMA integrity_check.',
        );
      }
      // Registra metadados do manifesto no novo banco
      await incomingDb.setMeta('version', manifest.version.toString());
      await incomingDb.setMeta('entry_count', manifest.entryCount.toString());
      await incomingDb.setMeta('sha256', manifest.sha256Hex);
      await incomingDb.setMeta('signer', manifest.signerEd25519Hex);
      await incomingDb.setMeta('iat', manifest.issuedAtUnix.toString());
    } finally {
      await incomingDb?.close();
    }

    // 4. Troca atômica (swap) com proteção de rollback
    final backupFile = File(backupPath);
    if (await backupFile.exists()) {
      await backupFile.delete();
    }

    try {
      if (await targetFile.exists()) {
        await targetFile.rename(backupPath);
      }
      await incomingFile.rename(activePath);

      // Abre e testa a base recém-instalada
      final finalDb = await CatalogDatabase.open(path: activePath);
      final finalOk = await finalDb.integrityCheck();
      if (!finalOk) {
        await finalDb.close();
        throw const CatalogIntegrityVerificationException(
          '[Fail-Closed] Falha ao validar banco ativo após troca atômica.',
        );
      }

      // Sucesso definitivo: limpa backup
      if (await backupFile.exists()) {
        await backupFile.delete();
      }

      return finalDb;
    } catch (e) {
      // Rollback automático
      if (await backupFile.exists()) {
        if (await targetFile.exists()) {
          try {
            await targetFile.delete();
          } catch (_) {}
        }
        await backupFile.rename(activePath);
      }
      if (await incomingFile.exists()) {
        try {
          await incomingFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }
}
