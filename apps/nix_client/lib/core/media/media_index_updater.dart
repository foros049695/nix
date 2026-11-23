import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:nix_transport/nix_transport.dart';
import '../security/platform_runtime.dart';
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
  static const String officialPublisherKeyHex =
      'e2b5c179834d8fa209f87234bb4817a5690d9841804f5619ca2e8310c85b190f';
  static const String defaultOfficialManifestUrl =
      'http://nixcatalog234567abcdefghijklmnopqrstuvwxyz234567abcdefaa.onion/manifest.json';
  static const String officialHttpsManifestUrl =
      'https://raw.githubusercontent.com/foros049695/nix/main/apps/nix_client/assets/catalog/seed_catalog_manifest.json';

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
          else ...[
            officialPublisherKeyHex.toLowerCase(),
            if (!isProductionMode || allowTestFixtureKey)
              fixtureTestPublisherKeyHex.toLowerCase(),
          ],
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
    if (!await verifyManifest(keyring) || artifactBytes.length != byteSize) {
      return false;
    }
    return std_crypto.sha256.convert(artifactBytes).toString() ==
        sha256Hex.toLowerCase();
  }

  Future<bool> verifyManifest(CatalogPublisherKeyring keyring) async {
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
        (keyring.isProductionMode || !keyring.allowTestFixtureKey)) {
      throw const CatalogTestKeyRejectedException(
        '[Segurança P0] Chave de teste exclusiva para fixtures rejeitada em ambiente de produção.',
      );
    }

    // 3. Verificação de assinatura Ed25519
    final msg = canonicalDigestBytes(
      version: version,
      artifactName: artifactName,
      sha256Hex: sha256Hex,
      byteSize: byteSize,
      issuedAtUnix: issuedAtUnix,
      entryCount: entryCount,
    );

    final ed = Ed25519();
    final sigBytes = hexToBytes(signatureHex);
    final signerPubBytes = hexToBytes(signerLower);
    final valid = await ed.verify(
      msg,
      signature: Signature(
        sigBytes,
        publicKey: SimplePublicKey(signerPubBytes, type: KeyPairType.ed25519),
      ),
    );
    if (!valid) return false;

    // 4. Validação de confiança e rotação
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
    return true;
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
  static const String officialHttpsManifestUrl =
      CatalogPublisherKeyring.officialHttpsManifestUrl;
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
    bool allowReinstall = false,
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
        final existingDb = await CatalogDatabase.open(path: activePath, readOnly: true);
        final int currentVersion;
        try {
          currentVersion = await existingDb.getVersion();
        } finally {
          await existingDb.close();
        }

        if (allowReinstall) {
          if (manifest.version < currentVersion) {
            throw CatalogRollbackRejectedException(
              '[Anti-Rollback] Versão do catálogo recebido (${manifest.version}) é inferior à versão atual ($currentVersion).',
            );
          }
        } else {
          if (manifest.version <= currentVersion) {
            throw CatalogRollbackRejectedException(
              '[Anti-Rollback] Versão do catálogo recebido (${manifest.version}) não é superior à versão atual ($currentVersion).',
            );
          }
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
      incomingDb = await CatalogDatabase.open(path: incomingPath, readOnly: true);
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

class CatalogUpdateCancelledException implements Exception {
  final String message;
  const CatalogUpdateCancelledException([this.message = 'Atualização cancelada pelo usuário.']);
  @override
  String toString() => 'CatalogUpdateCancelledException: $message';
}

enum CatalogUpdateStage {
  idle,
  checking,
  updateAvailable,
  upToDate,
  downloading,
  verifying,
  applying,
  completed,
  cancelled,
  error,
}

class CatalogUpdateProgress {
  final CatalogUpdateStage stage;
  final int bytesDownloaded;
  final int totalBytes;
  final double progressPercent;
  final String statusMessage;
  final String? errorMessage;
  final SignedCatalogManifest? availableManifest;

  const CatalogUpdateProgress({
    required this.stage,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.progressPercent = 0.0,
    this.statusMessage = '',
    this.errorMessage,
    this.availableManifest,
  });

  bool get isTerminal =>
      stage == CatalogUpdateStage.completed ||
      stage == CatalogUpdateStage.error ||
      stage == CatalogUpdateStage.cancelled;
}

class CatalogVersionEntry {
  final int version;
  final String artifactName;
  final String sha256Hex;
  final int entryCount;
  final String signerPublicKeyHex;
  final int appliedAtUnix;
  final String status;

  const CatalogVersionEntry({
    required this.version,
    required this.artifactName,
    required this.sha256Hex,
    required this.entryCount,
    required this.signerPublicKeyHex,
    required this.appliedAtUnix,
    required this.status,
  });

  factory CatalogVersionEntry.fromJson(Map<String, dynamic> json) =>
      CatalogVersionEntry(
        version: json['version'] as int,
        artifactName: json['artifactName'] as String,
        sha256Hex: json['sha256Hex'] as String,
        entryCount: json['entryCount'] as int? ?? 0,
        signerPublicKeyHex: json['signerPublicKeyHex'] as String? ?? '',
        appliedAtUnix: json['appliedAtUnix'] as int,
        status: json['status'] as String? ?? 'success',
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'artifactName': artifactName,
        'sha256Hex': sha256Hex,
        'entryCount': entryCount,
        'signerPublicKeyHex': signerPublicKeyHex,
        'appliedAtUnix': appliedAtUnix,
        'status': status,
      };
}

/// Gerenciador de atualizações privadas e seguras do Nix Media Index.
class CatalogUpdateManager {
  final CatalogPublisherKeyring keyring;
  TransportPolicy transportPolicy;
  final String targetDbPath;
  final String historyFilePath;

  bool _isCancelled = false;
  HttpClient? _activeHttpClient;
  RawSocket? _activeRawSocket;
  final StreamController<CatalogUpdateProgress> _progressController =
      StreamController<CatalogUpdateProgress>.broadcast();

  CatalogUpdateProgress _currentProgress =
      const CatalogUpdateProgress(stage: CatalogUpdateStage.idle);

  CatalogUpdateManager({
    CatalogPublisherKeyring? keyring,
    TransportPolicy? transportPolicy,
    String? targetDbPath,
    String? historyFilePath,
  })  : keyring = keyring ??
            CatalogPublisherKeyring(
              trustedKeysHex: {
                CatalogPublisherKeyring.officialPublisherKeyHex,
                if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(
                  const String.fromEnvironment('NIX_CATALOG_PUBLISHER_KEY_HEX'),
                ))
                  const String.fromEnvironment('NIX_CATALOG_PUBLISHER_KEY_HEX'),
              },
              isProductionMode: true,
            ),
        transportPolicy = transportPolicy ?? const TransportPolicy(),
        targetDbPath = targetDbPath ?? CatalogDatabase.getDefaultCatalogPath(),
        historyFilePath = historyFilePath ??
            NixPlatformPaths.resolveDataFile('catalog_update_history.json');

  Stream<CatalogUpdateProgress> get progressStream => _progressController.stream;
  CatalogUpdateProgress get currentProgress => _currentProgress;
  bool get isBusy =>
      _currentProgress.stage == CatalogUpdateStage.checking ||
      _currentProgress.stage == CatalogUpdateStage.downloading ||
      _currentProgress.stage == CatalogUpdateStage.verifying ||
      _currentProgress.stage == CatalogUpdateStage.applying;

  void _emitProgress(CatalogUpdateProgress progress) {
    _currentProgress = progress;
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  Future<int> getInstalledVersion() async {
    final file = File(targetDbPath);
    if (!await file.exists()) {
      return 0;
    }
    try {
      final db = await CatalogDatabase.open(path: targetDbPath, readOnly: true);
      try {
        return await db.getVersion();
      } finally {
        await db.close();
      }
    } catch (_) {
      return 0;
    }
  }

  static const String officialHttpsManifestUrl =
      'https://raw.githubusercontent.com/foros049695/nix/main/apps/nix_client/assets/catalog/seed_catalog_manifest.json';

  Future<SignedCatalogManifest?> checkForUpdate({
    required Uri manifestUri,
    bool allowClearnet = false,
  }) async {
    if (isBusy) throw StateError('Já existe uma operação de catálogo em andamento.');
    _isCancelled = false;
    _emitProgress(const CatalogUpdateProgress(
      stage: CatalogUpdateStage.checking,
      statusMessage: 'Consultando versão disponível via transporte seguro...',
    ));

    try {
      if (!allowClearnet) {
        transportPolicy.assertAllowedUri(manifestUri);
      }

      final manifestBytes = await _downloadBytes(manifestUri, allowClearnet: allowClearnet);
      if (_isCancelled) {
        throw const CatalogUpdateCancelledException();
      }

      final manifestJson =
          jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
      final manifest = SignedCatalogManifest.fromJson(manifestJson);

      if (!await manifest.verifyManifest(keyring)) {
        throw const FormatException('Assinatura do manifesto de catálogo inválida.');
      }

      final currentVersion = await getInstalledVersion();
      if (_isCancelled) throw const CatalogUpdateCancelledException();
      if (manifest.version < currentVersion) {
        throw CatalogRollbackRejectedException(
          'O publicador oferece v${manifest.version}, abaixo da versão instalada v$currentVersion.',
        );
      }
      if (manifest.version > currentVersion) {
        _emitProgress(CatalogUpdateProgress(
          stage: CatalogUpdateStage.updateAvailable,
          availableManifest: manifest,
          statusMessage:
              'Nova versão ${manifest.version} disponível (${manifest.entryCount} obras, ${(manifest.byteSize / 1024 / 1024).toStringAsFixed(1)} MB).',
        ));
        return manifest;
      } else {
        _emitProgress(CatalogUpdateProgress(
          stage: CatalogUpdateStage.upToDate,
          availableManifest: manifest,
          statusMessage:
              'O catálogo já está atualizado na versão mais recente ($currentVersion).',
        ));
        return null;
      }
    } catch (e) {
      if (_isCancelled) {
        _emitProgress(const CatalogUpdateProgress(
          stage: CatalogUpdateStage.cancelled,
          statusMessage: 'Verificação cancelada.',
        ));
        return null;
      }
      _emitProgress(CatalogUpdateProgress(
        stage: CatalogUpdateStage.error,
        errorMessage: e.toString(),
        statusMessage: _failureMessage(e, 'Não foi possível obter o manifesto via Tor.'),
      ));
      rethrow;
    }
  }

  Future<CatalogDatabase> downloadAndApplyUpdate({
    required SignedCatalogManifest manifest,
    required Uri packageUri,
    bool allowClearnet = false,
    void Function(CatalogUpdateProgress)? onProgress,
  }) async {
    if (isBusy) throw StateError('Já existe uma operação de catálogo em andamento.');
    _isCancelled = false;
    _emitProgress(CatalogUpdateProgress(
      stage: CatalogUpdateStage.downloading,
      availableManifest: manifest,
      statusMessage: allowClearnet
          ? 'Iniciando download seguro via espelho HTTPS oficial...'
          : 'Iniciando download seguro via Tor...',
      totalBytes: manifest.byteSize,
    ));

    try {
      if (!allowClearnet) {
        transportPolicy.assertAllowedUri(packageUri);
      }

      final packageBytes = await _downloadBytes(
        packageUri,
        expectedLength: manifest.byteSize,
        allowClearnet: allowClearnet,
        onProgress: (received, total) {
          final percent = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
          final p = CatalogUpdateProgress(
            stage: CatalogUpdateStage.downloading,
            availableManifest: manifest,
            bytesDownloaded: received,
            totalBytes: total,
            progressPercent: percent,
            statusMessage:
                'Baixando pacote: ${(received / 1024 / 1024).toStringAsFixed(1)} MB de ${(total / 1024 / 1024).toStringAsFixed(1)} MB (${(percent * 100).toStringAsFixed(0)}%)',
          );
          _emitProgress(p);
          onProgress?.call(p);
        },
      );

      if (_isCancelled) {
        throw const CatalogUpdateCancelledException();
      }

      _emitProgress(CatalogUpdateProgress(
        stage: CatalogUpdateStage.verifying,
        availableManifest: manifest,
        statusMessage: 'Verificando integridade SHA-256 e assinatura Ed25519...',
      ));

      _emitProgress(CatalogUpdateProgress(
        stage: CatalogUpdateStage.applying,
        availableManifest: manifest,
        statusMessage: 'Aplicando pacote e validando banco SQLite FTS5...',
      ));

      final updatedDb = await MediaIndexUpdater.applySignedCatalogPackage(
        packageBytes: packageBytes,
        manifest: manifest,
        keyring: keyring,
        targetDbPath: targetDbPath,
      );

      // Grava no histórico de versões
      await _recordHistory(CatalogVersionEntry(
        version: manifest.version,
        artifactName: manifest.artifactName,
        sha256Hex: manifest.sha256Hex,
        entryCount: manifest.entryCount,
        signerPublicKeyHex: manifest.signerEd25519Hex,
        appliedAtUnix: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        status: 'success',
      ));

      _emitProgress(CatalogUpdateProgress(
        stage: CatalogUpdateStage.completed,
        availableManifest: manifest,
        statusMessage:
            'Catálogo atualizado com sucesso para versão ${manifest.version} (${manifest.entryCount} obras)!',
      ));

      return updatedDb;
    } catch (e) {
      // Limpeza defensiva do incoming
      final inc = File('$targetDbPath.incoming');
      if (await inc.exists()) {
        try {
          await inc.delete();
        } catch (_) {}
      }

      if (_isCancelled) {
        _emitProgress(const CatalogUpdateProgress(
          stage: CatalogUpdateStage.cancelled,
          statusMessage: 'Atualização cancelada pelo usuário.',
        ));
        rethrow;
      }

      await _recordHistory(CatalogVersionEntry(
        version: manifest.version,
        artifactName: manifest.artifactName,
        sha256Hex: manifest.sha256Hex,
        entryCount: manifest.entryCount,
        signerPublicKeyHex: manifest.signerEd25519Hex,
        appliedAtUnix: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        status: 'failed: $e',
      ));

      _emitProgress(CatalogUpdateProgress(
        stage: CatalogUpdateStage.error,
        errorMessage: e.toString(),
        statusMessage: _failureMessage(e, 'Não foi possível baixar ou instalar o catálogo via Tor.'),
      ));
      rethrow;
    }
  }

  String _failureMessage(Object error, String fallback) => switch (error) {
    CatalogRollbackRejectedException() => error.message,
    CatalogKeyRevokedException() ||
    CatalogUntrustedSignerException() ||
    CatalogTestKeyRejectedException() => 'A chave que assinou o catálogo não é confiável.',
    CatalogIntegrityVerificationException() ||
    FormatException() => 'O manifesto ou pacote não passou na verificação de integridade.',
    TransportBlockedException() => 'Destino bloqueado. As atualizações exigem Tor.',
    _ => fallback,
  };

  bool get canCancel => _currentProgress.stage == CatalogUpdateStage.checking ||
      _currentProgress.stage == CatalogUpdateStage.downloading;

  Future<void> cancelAndWait() async {
    final completion = isBusy
        ? progressStream.firstWhere((progress) => !isBusy)
        : null;
    cancel();
    await completion;
  }

  void cancel() {
    if (isBusy && !canCancel) return;
    _isCancelled = true;
    _activeHttpClient?.close(force: true);
    _activeHttpClient = null;
    try {
      _activeRawSocket?.close();
    } catch (_) {}
    _activeRawSocket = null;
    if (!isBusy) {
      _emitProgress(const CatalogUpdateProgress(
        stage: CatalogUpdateStage.cancelled,
        statusMessage: 'Operação cancelada.',
      ));
    }
  }

  Future<Uint8List> _downloadBytes(
    Uri uri, {
    int? expectedLength,
    void Function(int received, int total)? onProgress,
    bool allowClearnet = false,
  }) async {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw UnsupportedTransportSchemeException(uri.scheme);
    }

    if (TransportPolicy.isLoopbackHost(uri.host) &&
        transportPolicy.mode == TransportMode.loopbackTest) {
      return _downloadLoopback(uri, expectedLength: expectedLength, onProgress: onProgress);
    }

    if (allowClearnet || !uri.host.endsWith('.onion')) {
      if (allowClearnet || uri.scheme == 'https') {
        return _downloadHttpsDirect(uri, expectedLength: expectedLength, onProgress: onProgress);
      }
    }

    return _downloadSocksTor(uri, expectedLength: expectedLength, onProgress: onProgress);
  }

  Future<Uint8List> _downloadHttpsDirect(
    Uri uri, {
    int? expectedLength,
    void Function(int received, int total)? onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    _activeHttpClient = client;

    try {
      final req = await client.getUrl(uri);
      req.headers.clear();
      req.headers.set(HttpHeaders.hostHeader, uri.host);
      req.headers.set(HttpHeaders.connectionHeader, 'close');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json, application/octet-stream, */*');
      req.headers.set(HttpHeaders.userAgentHeader, 'NixClient/1.0 (Signed-Catalog-Sync)');

      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('Falha HTTP ${res.statusCode} ao consultar espelho (${uri.path})');
      }

      final total = res.contentLength > 0 ? res.contentLength : (expectedLength ?? 0);
      final builder = BytesBuilder(copy: false);
      int received = 0;

      await for (final chunk in res) {
        if (_isCancelled) {
          throw const CatalogUpdateCancelledException();
        }
        builder.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }

      return builder.takeBytes();
    } finally {
      client.close(force: true);
      _activeHttpClient = null;
    }
  }

  Future<CatalogDatabase> syncBundledCatalog() async {
    _isCancelled = false;
    _emitProgress(const CatalogUpdateProgress(
      stage: CatalogUpdateStage.downloading,
      statusMessage: 'Carregando catálogo integrado assinado...',
    ));

    try {
      final manifestStr = await rootBundle.loadString('assets/catalog/seed_catalog_manifest.json');
      final manifestJson = jsonDecode(manifestStr) as Map<String, dynamic>;
      final manifest = SignedCatalogManifest.fromJson(manifestJson);

      final dbByteData = await rootBundle.load('assets/catalog/seed_catalog.db');
      final dbBytes = dbByteData.buffer.asUint8List();

      final newDb = await MediaIndexUpdater.applySignedCatalogPackage(
        packageBytes: dbBytes,
        manifest: manifest,
        keyring: keyring,
        targetDbPath: targetDbPath,
        allowReinstall: true,
      );

      await _recordHistory(CatalogVersionEntry(
        version: manifest.version,
        artifactName: manifest.artifactName,
        sha256Hex: manifest.sha256Hex,
        entryCount: manifest.entryCount,
        signerPublicKeyHex: manifest.signerEd25519Hex,
        appliedAtUnix: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        status: 'success',
      ));

      _emitProgress(CatalogUpdateProgress(
        stage: CatalogUpdateStage.completed,
        availableManifest: manifest,
        statusMessage: 'Catálogo integrado sincronizado e validado com sucesso (v${manifest.version})!',
      ));

      return newDb;
    } catch (e) {
      _emitProgress(CatalogUpdateProgress(
        stage: CatalogUpdateStage.error,
        errorMessage: e.toString(),
        statusMessage: 'Falha ao sincronizar catálogo integrado: $e',
      ));
      rethrow;
    }
  }

  Future<Uint8List> _downloadLoopback(
    Uri uri, {
    int? expectedLength,
    void Function(int received, int total)? onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    _activeHttpClient = client;

    try {
      final req = await client.getUrl(uri);
      // Privacy guarantee: zero extra headers, zero telemetry, zero identifiers
      req.headers.clear();
      req.headers.set(HttpHeaders.hostHeader, uri.host);
      req.headers.set(HttpHeaders.connectionHeader, 'close');

      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('Falha HTTP ${res.statusCode} ao obter ${uri.path}');
      }

      final total = res.contentLength > 0 ? res.contentLength : (expectedLength ?? 0);
      final builder = BytesBuilder(copy: false);
      int received = 0;

      await for (final chunk in res) {
        if (_isCancelled) {
          throw const CatalogUpdateCancelledException();
        }
        builder.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }

      return builder.takeBytes();
    } finally {
      client.close(force: true);
      _activeHttpClient = null;
    }
  }

  Future<Uint8List> _downloadSocksTor(
    Uri uri, {
    int? expectedLength,
    void Function(int received, int total)? onProgress,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final connector = Socks5Connector(
      proxyHost: transportPolicy.socksHost,
      proxyPort: transportPolicy.socksPort,
    );
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final conn = await connector.connectRaw(uri.host, port, requireOnionV3: true, timeout: timeout);

    RawSocket activeSocket = conn.socket;
    _activeRawSocket = activeSocket;

    try {
      if (uri.scheme == 'https') {
        final secure = await RawSecureSocket.secure(
          conn.socket,
          subscription: conn.subscription,
          host: uri.host,
        ).timeout(timeout);
        activeSocket = secure;
        _activeRawSocket = secure;
      }

      // Privacy: pure static request without cookies, user identifiers or query search params
      final path = uri.path.isEmpty ? '/' : uri.path;
      final reqString = 'GET $path HTTP/1.1\r\nHost: ${uri.host}\r\nConnection: close\r\n\r\n';
      activeSocket.write(utf8.encode(reqString));

      final completer = Completer<Uint8List>();
      final builder = BytesBuilder(copy: false);
      int received = 0;
      int total = expectedLength ?? 0;
      bool headersParsed = false;
      List<int> headerBuffer = [];

      conn.subscription.onData((event) {
        if (_isCancelled) {
          activeSocket.close();
          if (!completer.isCompleted) {
            completer.completeError(const CatalogUpdateCancelledException());
          }
          return;
        }

        if (event == RawSocketEvent.read) {
          while (true) {
            final chunk = activeSocket.read();
            if (chunk == null || chunk.isEmpty) break;

            if (!headersParsed) {
              headerBuffer.addAll(chunk);
              final idx = _findHeaderEnd(headerBuffer);
              if (idx != -1) {
                headersParsed = true;
                final headerStr = utf8.decode(headerBuffer.sublist(0, idx), allowMalformed: true);
                final clMatch = RegExp(r'content-length:\s*(\d+)', caseSensitive: false).firstMatch(headerStr);
                if (clMatch != null) {
                  total = int.parse(clMatch.group(1)!);
                }
                final remainingBody = headerBuffer.sublist(idx + 4);
                if (remainingBody.isNotEmpty) {
                  builder.add(remainingBody);
                  received += remainingBody.length;
                  onProgress?.call(received, total);
                }
                headerBuffer.clear();
              }
            } else {
              builder.add(chunk);
              received += chunk.length;
              onProgress?.call(received, total);
            }
          }
        } else if (event == RawSocketEvent.readClosed || event == RawSocketEvent.closed) {
          if (!completer.isCompleted) {
            completer.complete(builder.takeBytes());
          }
        }
      });

      conn.subscription.onError((err) {
        if (!completer.isCompleted) {
          completer.completeError(err);
        }
      });

      return await completer.future.timeout(timeout, onTimeout: () {
        throw const SocketException('Timeout ao baixar pacote via Tor SOCKS5.');
      });
    } finally {
      try {
        activeSocket.close();
      } catch (_) {}
      _activeRawSocket = null;
    }
  }

  static int _findHeaderEnd(List<int> bytes) {
    for (int i = 0; i < bytes.length - 3; i++) {
      if (bytes[i] == 13 && bytes[i + 1] == 10 && bytes[i + 2] == 13 && bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  Future<void> _recordHistory(CatalogVersionEntry entry) async {
    try {
      final list = await getVersionHistory();
      list.removeWhere((e) => e.version == entry.version);
      list.insert(0, entry);
      final file = File(historyFilePath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      await file.writeAsString(
        jsonEncode(list.map((e) => e.toJson()).toList()),
        flush: true,
      );
    } catch (_) {}
  }

  Future<List<CatalogVersionEntry>> getVersionHistory() async {
    try {
      final file = File(historyFilePath);
      if (!await file.exists()) {
        return [];
      }
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => CatalogVersionEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<int> cleanupStorage() async {
    if (isBusy) return 0;
    int freed = 0;
    final incoming = File('$targetDbPath.incoming');
    if (await incoming.exists()) {
      freed += await incoming.length();
      await incoming.delete();
    }
    final bak = File('$targetDbPath.bak');
    if (await bak.exists()) {
      freed += await bak.length();
      await bak.delete();
    }
    return freed;
  }

  void dispose() {
    _progressController.close();
  }
}
