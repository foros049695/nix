import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';

/// Exceção disparada quando o cofre ainda não foi provisionado.
class VaultNotInitializedException implements Exception {
  final String message;
  const VaultNotInitializedException([this.message = 'Cofre de chaves não foi inicializado neste dispositivo.']);
  @override
  String toString() => 'VaultNotInitializedException: $message';
}

/// Exceção disparada quando a senha está incorreta ou o material foi adulterado.
class VaultAuthenticationException implements Exception {
  final String message;
  const VaultAuthenticationException([this.message = 'Falha de autenticação do cofre: senha incorreta ou arquivo adulterado.']);
  @override
  String toString() => 'VaultAuthenticationException: $message';
}

/// Exceção disparada ao tentar reinicializar um cofre já existente sem procedimento de reset explícito.
class VaultAlreadyInitializedException implements Exception {
  final String message;
  const VaultAlreadyInitializedException([this.message = 'Cofre já inicializado. Utilize unlock ou rotação de senha.']);
  @override
  String toString() => 'VaultAlreadyInitializedException: $message';
}

/// KeyVault: Gerenciador soberano do material de chave do banco local e identidades.
///
/// Implementa proteção por envelope criptográfico conforme Marco P0-2 e documento 05:
/// - Chave mestre aleatória de 32 bytes gerada independentemente das chaves de rede.
/// - Derivação de chave de envelope (wrapping key) via Argon2id (64 MiB, 3 iterações).
/// - Envelopamento autenticado com XChaCha20-Poly1305.
/// - O arquivo de bootstrap contém apenas parâmetros KDF, salt e ciphertext; NUNCA a chave em claro.
class KeyVault {
  static const int masterKeyLength = 32;
  static const int saltLength = 16;
  static const int currentVersion = 1;

  Uint8List? _cachedMasterKey;
  bool _isUnlocked = false;

  bool get isUnlocked => _isUnlocked && _cachedMasterKey != null;

  /// Retorna a chave mestre de 32 bytes se desbloqueado; lança [StateError] se bloqueado.
  Uint8List get masterKey {
    if (!isUnlocked || _cachedMasterKey == null) {
      throw StateError('O KeyVault está bloqueado. Desbloqueie com senha antes de acessar a chave mestre.');
    }
    return Uint8List.fromList(_cachedMasterKey!);
  }

  /// Caminho padrão para o arquivo de bootstrap do cofre em plataformas desktop/linux.
  static String getDefaultBootstrapPath() {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) {
      return '.nix_vault_bootstrap.json';
    }
    return '$home/.local/share/nix/vault_bootstrap.json';
  }

  /// Verifica se o arquivo de bootstrap do cofre existe e possui estrutura válida.
  Future<bool> isInitialized({String? customPath}) async {
    final path = customPath ?? getDefaultBootstrapPath();
    final file = File(path);
    if (!await file.exists()) return false;
    try {
      final raw = await file.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.containsKey('version') && map.containsKey('kdf') && map.containsKey('wrappedKey');
    } catch (_) {
      return false;
    }
  }

  /// Inicializa o cofre gerando uma nova chave mestre aleatória de 32 bytes e
  /// gravando o envelope cifrado via Argon2id + XChaCha20-Poly1305.
  Future<Uint8List> initialize({
    required String passphrase,
    String? customPath,
    bool overwrite = false,
  }) async {
    final path = customPath ?? getDefaultBootstrapPath();
    final file = File(path);

    if (!overwrite && await file.exists()) {
      throw const VaultAlreadyInitializedException();
    }

    if (passphrase.trim().isEmpty) {
      throw ArgumentError('A senha do cofre não pode ser vazia.');
    }

    // 1. Gera chave mestre aleatória de 32 bytes (independente de chaves de rede)
    final masterSecret = SecretKeyData.random(length: masterKeyLength);
    final masterBytes = Uint8List.fromList(masterSecret.bytes);

    // 2. Gera salt criptográfico de 16 bytes
    final salt = PassphraseKdf.generateSalt(saltLength);

    // 3. Deriva chave de envelope via Argon2id (64 MiB, 3 iterações)
    const kdf = PassphraseKdf.strong();
    final derivedWrappingKey = await kdf.deriveKey(
      passphrase: passphrase,
      salt: salt,
    );

    // 4. Envelopa chave mestre com XChaCha20-Poly1305
    final sealed = await SealedEnvelope.seal(
      key: SecretKey(derivedWrappingKey.bytes),
      plaintext: masterBytes,
      aad: utf8.encode('NIX_KEYVAULT_V1'),
    );

    // 5. Salva arquivo de bootstrap atômico (nunca grava chave em claro)
    final bootstrapData = {
      'version': currentVersion,
      'createdAt': DateTime.now().toUtc().millisecondsSinceEpoch,
      'kdf': {
        'algorithm': 'Argon2id',
        'memoryKib': kdf.memoryKib,
        'iterations': kdf.iterations,
        'parallelism': kdf.parallelism,
        'hashLength': kdf.hashLength,
        'salt': base64Encode(salt),
      },
      'wrappedKey': {
        'nonce': base64Encode(sealed.nonce),
        'mac': base64Encode(sealed.macBytes),
        'cipherText': base64Encode(sealed.cipherText),
      },
    };

    await file.parent.create(recursive: true);
    final tempFile = File('${path}.tmp_${DateTime.now().microsecondsSinceEpoch}');
    await tempFile.writeAsString(jsonEncode(bootstrapData), flush: true);
    await tempFile.rename(path);

    _cachedMasterKey = masterBytes;
    _isUnlocked = true;
    return Uint8List.fromList(masterBytes);
  }

  /// Desbloqueia o cofre utilizando [passphrase], decifrando a chave mestre de 32 bytes.
  Future<Uint8List> unlock({
    required String passphrase,
    String? customPath,
  }) async {
    final path = customPath ?? getDefaultBootstrapPath();
    final file = File(path);

    if (!await file.exists()) {
      throw const VaultNotInitializedException();
    }

    final rawContent = await file.readAsString();
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(rawContent) as Map<String, dynamic>;
    } catch (_) {
      throw const VaultAuthenticationException('Arquivo de bootstrap corrompido ou inválido.');
    }

    final kdfMap = data['kdf'] as Map<String, dynamic>?;
    final wrappedMap = data['wrappedKey'] as Map<String, dynamic>?;

    if (kdfMap == null || wrappedMap == null) {
      throw const VaultAuthenticationException('Estrutura de bootstrap incompleta.');
    }

    final memoryKib = kdfMap['memoryKib'] as int? ?? 65536;
    final iterations = kdfMap['iterations'] as int? ?? 3;
    final parallelism = kdfMap['parallelism'] as int? ?? 1;
    final hashLength = kdfMap['hashLength'] as int? ?? 32;
    final salt = base64Decode(kdfMap['salt'] as String);

    final nonce = base64Decode(wrappedMap['nonce'] as String);
    final mac = base64Decode(wrappedMap['mac'] as String);
    final cipherText = base64Decode(wrappedMap['cipherText'] as String);

    final kdf = PassphraseKdf(
      memoryKib: memoryKib,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: hashLength,
    );

    final derivedWrappingKey = await kdf.deriveKey(
      passphrase: passphrase,
      salt: salt,
    );

    try {
      final payload = SealedPayload(
        nonce: Uint8List.fromList(nonce),
        macBytes: Uint8List.fromList(mac),
        cipherText: Uint8List.fromList(cipherText),
      );

      final clearMasterBytes = await SealedEnvelope.open(
        key: SecretKey(derivedWrappingKey.bytes),
        payload: payload,
        aad: utf8.encode('NIX_KEYVAULT_V1'),
      );

      if (clearMasterBytes.length != masterKeyLength) {
        throw const VaultAuthenticationException('Comprimento de chave decifrada inconsistente.');
      }

      _cachedMasterKey = Uint8List.fromList(clearMasterBytes);
      _isUnlocked = true;
      return Uint8List.fromList(clearMasterBytes);
    } catch (e) {
      _cachedMasterKey = null;
      _isUnlocked = false;
      throw const VaultAuthenticationException();
    }
  }

  /// Altera a senha do cofre decifrando a chave existente e envelopando-a com novo salt e senha.
  Future<void> changePassphrase({
    required String oldPassphrase,
    required String newPassphrase,
    String? customPath,
  }) async {
    final currentKey = await unlock(passphrase: oldPassphrase, customPath: customPath);
    if (newPassphrase.trim().isEmpty) {
      throw ArgumentError('A nova senha não pode ser vazia.');
    }

    final path = customPath ?? getDefaultBootstrapPath();
    final file = File(path);

    final newSalt = PassphraseKdf.generateSalt(saltLength);
    const kdf = PassphraseKdf.strong();
    final newWrappingKey = await kdf.deriveKey(
      passphrase: newPassphrase,
      salt: newSalt,
    );

    final sealed = await SealedEnvelope.seal(
      key: SecretKey(newWrappingKey.bytes),
      plaintext: currentKey,
      aad: utf8.encode('NIX_KEYVAULT_V1'),
    );

    final bootstrapData = {
      'version': currentVersion,
      'createdAt': DateTime.now().toUtc().millisecondsSinceEpoch,
      'kdf': {
        'algorithm': 'Argon2id',
        'memoryKib': kdf.memoryKib,
        'iterations': kdf.iterations,
        'parallelism': kdf.parallelism,
        'hashLength': kdf.hashLength,
        'salt': base64Encode(newSalt),
      },
      'wrappedKey': {
        'nonce': base64Encode(sealed.nonce),
        'mac': base64Encode(sealed.macBytes),
        'cipherText': base64Encode(sealed.cipherText),
      },
    };

    final tempFile = File('${path}.tmp_${DateTime.now().microsecondsSinceEpoch}');
    await tempFile.writeAsString(jsonEncode(bootstrapData), flush: true);
    await tempFile.rename(path);

    _cachedMasterKey = currentKey;
    _isUnlocked = true;
  }

  /// Bloqueia o cofre e zera o material de chave na memória.
  void lock() {
    if (_cachedMasterKey != null) {
      // Sobrescreve com zeros antes de liberar
      _cachedMasterKey!.fillRange(0, _cachedMasterKey!.length, 0);
      _cachedMasterKey = null;
    }
    _isUnlocked = false;
  }
}
