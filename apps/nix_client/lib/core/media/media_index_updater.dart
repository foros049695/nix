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

class CatalogKeyRevokedException implements Exception {
  final String message;
  const CatalogKeyRevokedException(this.message);
  @override
  String toString() => 'CatalogKeyRevokedException: $message';
}

class CatalogUntrustedSignerException implements Exception {
  final String message;
  const CatalogUntrustedSignerException(this.message);
  @override
  String toString() => 'CatalogUntrustedSignerException: $message';
}

class CatalogTestKeyRejectedException implements Exception {
  final String message;
  const CatalogTestKeyRejectedException(this.message);
  @override
  String toString() => 'CatalogTestKeyRejectedException: $message';
}

/// Anel de chaves públicas confiáveis para publicação do catálogo cultural.
class CatalogPublisherKeyring {
  static const String fixtureTestPublisherKeyHex =
      'a805baa55178d7c0220a9d586a56db6359521455e3b66d9abf914b829a47f045';

  final Set<String> _trustedKeysHex;
  final Set<String> _revokedKeysHex;
  final bool isProductionMode;
  final bool allowTestFixtureKey;

  CatalogPublisherKeyring({
    Set<String>? trustedKeysHex,
    Set<String>? revokedKeysHex,
    this.isProductionMode = false,
    this.allowTestFixtureKey = false,
  })  : _trustedKeysHex = {
          if (trustedKeysHex != null)
            ...trustedKeysHex.map((k) => k.toLowerCase())
        },
        _revokedKeysHex = {
          if (revokedKeysHex != null)
            ...revokedKeysHex.map((k) => k.toLowerCase())
        };

  factory CatalogPublisherKeyring.single(
    SimplePublicKey key, {
    bool isProductionMode = false,
    bool allowTestFixtureKey = true,
  }) {
    return CatalogPublisherKeyring(
      trustedKeysHex: {SignedCatalogManifest.bytesToHex(key.bytes)},
      isProductionMode: isProductionMode,
      allowTestFixtureKey: allowTestFixtureKey,
    );
  }

  Set<String> get trustedKeysHex => Set.unmodifiable(_trustedKeysHex);
  Set<String> get revokedKeysHex => Set.unmodifiable(_revokedKeysHex);

  void addTrustedKey(String pubKeyHex) {
    final lower = pubKeyHex.toLowerCase();
    if (_revokedKeysHex.contains(lower)) {
      throw CatalogKeyRevokedException(
        'Chave $lower está revogada e não pode ser configurada como confiável.',
      );
    }
    _trustedKeysHex.add(lower);
  }

  void revokeKey(String pubKeyHex) {
    final lower = pubKeyHex.toLowerCase();
    _trustedKeysHex.remove(lower);
    _revokedKeysHex.add(lower);
  }

  bool isKeyTrusted(String pubKeyHex) =>
      _trustedKeysHex.contains(pubKeyHex.toLowerCase());

  bool isKeyRevoked(String pubKeyHex) =>
      _revokedKeysHex.contains(pubKeyHex.toLowerCase());

  Future<bool> rotateKey({
    required String oldKeyHex,
    required String newKeyHex,
    required String rotationSignatureHex,
    required int version,
  }) async {
    final oldLower = oldKeyHex.toLowerCase();
    final newLower = newKeyHex.toLowerCase();
    if (!isKeyTrusted(oldLower)) return false;
    if (isKeyRevoked(oldLower) || isKeyRevoked(newLower)) return false;

    final ed = Ed25519();
    final claim = utf8.encode('ROTATE:$oldLower->$newLower:$version');
    final oldKeyBytes = SignedCatalogManifest.hexToBytes(oldLower);
    final sigBytes = SignedCatalogManifest.hexToBytes(rotationSignatureHex);

    final ok = await ed.verify(
      claim,
      signature: Signature(
        sigBytes,
        publicKey: SimplePublicKey(oldKeyBytes, type: KeyPairType.ed25519),
      ),
    );

    if (ok) {
      _trustedKeysHex.add(newLower);
      return true;
    }
    return false;
  }
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
  final bool isProduction;
  final String? previousSignerEd25519Hex;
  final String? rotationSignatureHex;

  const SignedCatalogManifest({
    required this.version,
    required this.artifactName,
    required this.sha256Hex,
    required this.byteSize,
    required this.issuedAtUnix,
    required this.entryCount,
    required this.signerEd25519Hex,
    required this.signatureHex,
    this.isProduction = false,
    this.previousSignerEd25519Hex,
    this.rotationSignatureHex,
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
    bool isProduction = false,
    KeyPair? previousKeyPair,
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
    final signerHex = bytesToHex(pubKey.bytes);

    String? prevSignerHex;
    String? rotSigHex;
    if (previousKeyPair != null) {
      final prevPub =
          await previousKeyPair.extractPublicKey() as SimplePublicKey;
      prevSignerHex = bytesToHex(prevPub.bytes);
      final rotClaim =
          utf8.encode('ROTATE:$prevSignerHex->$signerHex:$version');
      final rotSig = await ed.sign(rotClaim, keyPair: previousKeyPair);
      rotSigHex = bytesToHex(rotSig.bytes);
    }

    return SignedCatalogManifest(
      version: version,
      artifactName: artifactName,
      sha256Hex: digest,
      byteSize: artifactBytes.length,
      issuedAtUnix: iat,
      entryCount: entryCount,
      signerEd25519Hex: signerHex,
      signatureHex: bytesToHex(sig.bytes),
      isProduction: isProduction,
      previousSignerEd25519Hex: prevSignerHex,
      rotationSignatureHex: rotSigHex,
    );
  }

  Future<bool> verifyArtifactBytes(
    List<int> artifactBytes, {
    SimplePublicKey? trustedPublisherKey,
    CatalogPublisherKeyring? keyring,
  }) async {
    final kr = keyring ??
        (trustedPublisherKey != null
            ? CatalogPublisherKeyring.single(trustedPublisherKey,
                allowTestFixtureKey: true)
            : null);

    if (kr == null) {
      throw ArgumentError(
        'Forneça um trustedPublisherKey ou um CatalogPublisherKeyring.',
      );
    }

    try {
      return await verifyWithKeyring(artifactBytes, kr);
    } on CatalogUntrustedSignerException {
      return false;
    } on CatalogKeyRevokedException {
      return false;
    } on CatalogTestKeyRejectedException {
      return false;
    }
  }

  Future<bool> verifyWithKeyring(
    List<int> artifactBytes,
    CatalogPublisherKeyring keyring,
  ) async {
    final signerLower = signerEd25519Hex.toLowerCase();

    // 1. Rejeição de chaves revogadas
    if (keyring.isKeyRevoked(signerLower)) {
      throw CatalogKeyRevokedException(
        '[Segurança] A chave do publicador ($signerLower) foi revogada.',
      );
    }

    // 2. Rejeição de chave de teste pública em produção
    if ((keyring.isProductionMode || isProduction) &&
        signerLower == CatalogPublisherKeyring.fixtureTestPublisherKeyHex.toLowerCase() &&
        !keyring.allowTestFixtureKey) {
      throw const CatalogTestKeyRejectedException(
        '[Segurança P0] Chave de teste exclusiva para fixtures rejeitada em ambiente de produção.',
      );
    }

    // 3. Validação de confiança e rotação
    bool trusted = keyring.isKeyTrusted(signerLower);
    if (!trusted &&
        previousSignerEd25519Hex != null &&
        rotationSignatureHex != null) {
      final rotatedOk = await keyring.rotateKey(
        oldKeyHex: previousSignerEd25519Hex!,
        newKeyHex: signerLower,
        rotationSignatureHex: rotationSignatureHex!,
        version: version,
      );
      if (rotatedOk) {
        trusted = true;
      }
    }

    if (!trusted) {
      throw CatalogUntrustedSignerException(
        '[Segurança] O publicador ($signerLower) não consta no anel de chaves confiáveis.',
      );
    }

    // 4. Verificação de tamanho
    if (artifactBytes.length != byteSize) {
      return false;
    }

    // 5. Verificação de integridade SHA-256
    final actualSha =
        std_crypto.sha256.convert(artifactBytes).toString().toLowerCase();
    if (actualSha != sha256Hex.toLowerCase()) {
      return false;
    }

    // 6. Verificação de assinatura Ed25519
    final msg = canonicalDigestBytes(
      version: version,
      artifactName: artifactName,
      sha256Hex: actualSha,
      byteSize: byteSize,
      issuedAtUnix: issuedAtUnix,
      entryCount: entryCount,
    );

    final ed = Ed25519();
    final sigBytes = hexToBytes(signatureHex);
    final signerPubBytes = hexToBytes(signerLower);
    return ed.verify(
      msg,
      signature: Signature(
        sigBytes,
        publicKey: SimplePublicKey(signerPubBytes, type: KeyPairType.ed25519),
      ),
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
        'isProduction': isProduction,
        if (previousSignerEd25519Hex != null)
          'previousSignerEd25519Hex': previousSignerEd25519Hex,
        if (rotationSignatureHex != null)
          'rotationSignatureHex': rotationSignatureHex,
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
        isProduction: json['isProduction'] as bool? ?? false,
        previousSignerEd25519Hex: json['previousSignerEd25519Hex'] as String?,
        rotationSignatureHex: json['rotationSignatureHex'] as String?,
      );

  static String bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List hexToBytes(String hex) {
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
  /// 2. Verificação de integridade SHA-256 e assinatura Ed25519 contra [trustedPublisherKey] ou [keyring].
  /// 3. Escrita em arquivo temporário `.incoming` e checagem PRAGMA integrity_check.
  /// 4. Troca atômica (swap) com backup `.bak` e rollback automático em falha.
  static Future<CatalogDatabase> applySignedCatalogPackage({
    required List<int> packageBytes,
    required SignedCatalogManifest manifest,
    SimplePublicKey? trustedPublisherKey,
    CatalogPublisherKeyring? keyring,
    String? targetDbPath,
  }) async {
    final kr = keyring ??
        (trustedPublisherKey != null
            ? CatalogPublisherKeyring.single(trustedPublisherKey,
                allowTestFixtureKey: true)
            : null);

    if (kr == null) {
      throw ArgumentError(
        'Forneça um trustedPublisherKey ou um CatalogPublisherKeyring.',
      );
    }

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

    // 2. Verificação de assinatura Ed25519 e SHA-256 contra o anel de chaves
    final isValid = await manifest.verifyWithKeyring(packageBytes, kr);
    if (!isValid) {
      throw const CatalogIntegrityVerificationException(
        '[Segurança] Falha na verificação criptográfica do pacote de catálogo (hash ou assinatura inválida).',
      );
    }

    // 3. Escrita atômica em arquivo temporário (.incoming)
    final incomingPath = '$activePath.incoming';
    final backupPath = '$activePath.bak';
    final incomingFile = File(incomingPath);
    if (await incomingFile.exists()) {
      await incomingFile.delete();
    }

    await incomingFile.writeAsBytes(packageBytes, flush: true);

    // Validação de integridade do SQLite e FTS5 no arquivo incoming
    CatalogDatabase? incomingDb;
    try {
      incomingDb = await CatalogDatabase.open(path: incomingPath);
      final check = await incomingDb.rawDatabase.rawQuery('PRAGMA integrity_check;');
      if (check.isEmpty || check.first.values.first != 'ok') {
        throw CatalogIntegrityVerificationException(
          '[SQLite] Arquivo recebido não passou no PRAGMA integrity_check: $check',
        );
      }
      final dbVersion = await incomingDb.getVersion();
      if (dbVersion != manifest.version) {
        throw CatalogIntegrityVerificationException(
          '[Metadados] Versão gravada no SQLite ($dbVersion) difere do manifesto (${manifest.version}).',
        );
      }
    } finally {
      if (incomingDb != null) {
        await incomingDb.close();
      }
    }

    // 4. Troca atômica (swap) com backup defensivo
    if (await targetFile.exists()) {
      final backupFile = File(backupPath);
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
      await targetFile.rename(backupPath);
    }

    try {
      await incomingFile.rename(activePath);
      final finalDb = await CatalogDatabase.open(path: activePath);

      // Limpeza do backup anterior após sucesso
      final backupFile = File(backupPath);
      if (await backupFile.exists()) {
        await backupFile.delete();
      }

      return finalDb;
    } catch (e) {
      // Rollback defensivo
      final backupFile = File(backupPath);
      if (await backupFile.exists()) {
        await backupFile.rename(activePath);
      }
      rethrow;
    }
  }
}
