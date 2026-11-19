import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:nix_core_crypto/nix_core_crypto.dart';
import 'os_key_storage.dart';

/// Exceção disparada quando o cofre ainda não foi provisionado.
class VaultNotInitializedException implements Exception {
  final String message;
  const VaultNotInitializedException(
      [this.message = 'Cofre de chaves não foi inicializado neste dispositivo.']);
  @override
  String toString() => 'VaultNotInitializedException: $message';
}

/// Exceção disparada quando a senha está incorreta ou o material foi adulterado.
class VaultAuthenticationException implements Exception {
  final String message;
  const VaultAuthenticationException(
      [this.message =
          'Falha de autenticação do cofre: senha incorreta ou arquivo adulterado.']);
  @override
  String toString() => 'VaultAuthenticationException: $message';
}

/// Exceção disparada ao tentar reinicializar um cofre já existente sem procedimento de reset explícito.
class VaultAlreadyInitializedException implements Exception {
  final String message;
  const VaultAlreadyInitializedException(
      [this.message = 'Cofre já inicializado. Utilize unlock ou rotação de senha.']);
  @override
  String toString() => 'VaultAlreadyInitializedException: $message';
}

/// Estado retornado ao avaliar a senha de desbloqueio (sucesso real ou PIN de coação).
enum VaultUnlockStatus {
  unlocked,
  duressTriggered,
}

class VaultUnlockResult {
  final VaultUnlockStatus status;
  final Uint8List? masterKey;
  const VaultUnlockResult._({required this.status, this.masterKey});

  const VaultUnlockResult.unlocked(Uint8List key)
      : this._(status: VaultUnlockStatus.unlocked, masterKey: key);

  const VaultUnlockResult.duressTriggered()
      : this._(status: VaultUnlockStatus.duressTriggered);
}

/// KeyVault: Gerenciador soberano do material de chave do banco local e identidades.
///
/// Implementa proteção por envelope criptográfico conforme Marco P0-2 e documento 05:
/// - Chave mestre aleatória de 32 bytes gerada independentemente das chaves de rede.
/// - Derivação de chave de envelope (wrapping key) via Argon2id (64 MiB, 3 iterações).
/// - Envelopamento autenticado com XChaCha20-Poly1305.
/// - Suporte opcional a PIN de coação (`duressVerifier` Argon2id, sem armazenar senha em claro).
/// - Integração opcional com keyring nativo do SO (`libsecret` / `AndroidKeyStore`).
/// - O arquivo de bootstrap contém apenas parâmetros KDF, salt e ciphertext; NUNCA a chave em claro.
class KeyVault {
  static const int masterKeyLength = 32;
  static const int saltLength = 16;
  static const int currentVersion = 1;
  static const String osKeyringPassphraseSlot = 'nix_vault_wrapping_secret_v1';

  final OsKeyStorage _osKeyStorage;
  Uint8List? _cachedMasterKey;
  bool _isUnlocked = false;
  bool _lastKeyringBindSucceeded = false;

  KeyVault({OsKeyStorage? osKeyStorage})
      : _osKeyStorage = osKeyStorage ?? OsKeyStorage.createDefault();

  OsKeyStorage get osKeyStorage => _osKeyStorage;
  bool get isUnlocked => _isUnlocked && _cachedMasterKey != null;
  bool get lastKeyringBindSucceeded => _lastKeyringBindSucceeded;

  /// Retorna a chave mestre de 32 bytes se desbloqueado; lança [StateError] se bloqueado.
  Uint8List get masterKey {
    if (!isUnlocked || _cachedMasterKey == null) {
      throw StateError(
          'O KeyVault está bloqueado. Desbloqueie com senha antes de acessar a chave mestre.');
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
      return map.containsKey('version') &&
          map.containsKey('kdf') &&
          map.containsKey('wrappedKey');
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
    String? duressPassphrase,
    bool bindToOsKeyring = false,
  }) async {
    final path = customPath ?? getDefaultBootstrapPath();
    final file = File(path);

    if (!overwrite && await file.exists()) {
      throw const VaultAlreadyInitializedException();
    }

    if (passphrase.trim().isEmpty) {
      throw ArgumentError('A senha do cofre não pode ser vazia.');
    }
    if (duressPassphrase != null &&
        duressPassphrase.trim().isNotEmpty &&
        duressPassphrase == passphrase) {
      throw ArgumentError('O PIN de coação deve ser distinto da senha principal.');
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

    Map<String, dynamic>? duressSection;
    if (duressPassphrase != null && duressPassphrase.trim().isNotEmpty) {
      duressSection = await _buildDuressVerifier(duressPassphrase);
    }

    // 5. Salva arquivo de bootstrap atômico (nunca grava chave em claro)
    final bootstrapData = <String, dynamic>{
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
      if (duressSection != null) 'duressVerifier': duressSection,
    };

    await _writeBootstrapAtomic(path, bootstrapData);

    _lastKeyringBindSucceeded = false;
    if (bindToOsKeyring && _osKeyStorage.isHardwareOrOsBacked) {
      _lastKeyringBindSucceeded =
          await _osKeyStorage.storeSecret(_keyringKey(path), passphrase);
    }

    _cachedMasterKey = masterBytes;
    _isUnlocked = true;
    return Uint8List.fromList(masterBytes);
  }

  /// Exporta o envelope criptografado do KeyVault (sem expor a chave mestre em claro) para backup seguro.
  Future<Map<String, dynamic>> exportEncryptedBackupBundle({
    String? customPath,
  }) async {
    final path = customPath ?? getDefaultBootstrapPath();
    final file = File(path);
    if (!await file.exists()) {
      throw const VaultNotInitializedException();
    }
    final raw = await file.readAsString();
    final map = jsonDecode(raw) as Map<String, dynamic>;
    if (!map.containsKey('version') ||
        !map.containsKey('kdf') ||
        !map.containsKey('wrappedKey')) {
      throw const VaultAuthenticationException('Estrutura de cofre inválida para backup.');
    }
    return Map<String, dynamic>.from(map);
  }

  /// Restaura e autentica um envelope de backup criptografado do KeyVault validando a frase-passe antes de gravar.
  Future<Uint8List> importEncryptedBackupBundle(
    Map<String, dynamic> bundle, {
    required String passphrase,
    String? customPath,
    bool bindToOsKeyring = false,
  }) async {
    final path = customPath ?? getDefaultBootstrapPath();
    final tempCheckPath = '$path.restore_verify_${DateTime.now().microsecondsSinceEpoch}';
    try {
      await _writeBootstrapAtomic(tempCheckPath, bundle);
      final unlocked = await unlock(
        passphrase: passphrase,
        customPath: tempCheckPath,
      );
      await _writeBootstrapAtomic(path, bundle);
      _lastKeyringBindSucceeded = false;
      if (bindToOsKeyring && _osKeyStorage.isHardwareOrOsBacked) {
        _lastKeyringBindSucceeded =
            await _osKeyStorage.storeSecret(_keyringKey(path), passphrase);
      }
      return unlocked;
    } finally {
      final tmp = File(tempCheckPath);
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
  }

  /// Tenta desbloqueio automático seguro utilizando credencial isolada no Keyring do SO.
  Future<Uint8List?> tryUnlockWithOsKeyring({String? customPath}) async {
    if (!_osKeyStorage.isHardwareOrOsBacked) return null;
    final path = customPath ?? getDefaultBootstrapPath();
    final secret = await _osKeyStorage.readSecret(_keyringKey(path));
    if (secret == null || secret.isEmpty) return null;
    try {
      return await unlock(passphrase: secret, customPath: customPath);
    } catch (_) {
      return null;
    }
  }

  /// Remove eventual segredo armazenado no Keyring do SO para o cofre informado.
  Future<void> clearOsKeyringSecret({String? customPath}) async {
    final path = customPath ?? getDefaultBootstrapPath();
    await _osKeyStorage.deleteSecret(_keyringKey(path));
  }

  /// Verifica se existe verificador de PIN de coação configurado no cofre.
  Future<bool> hasDuressPassphrase({String? customPath}) async {
    final path = customPath ?? getDefaultBootstrapPath();
    final file = File(path);
    if (!await file.exists()) return false;
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return data['duressVerifier'] is Map<String, dynamic>;
    } catch (_) {
      return false;
    }
  }

  /// Configura ou substitui o PIN de coação após autenticar com a senha real do cofre.
  Future<void> configureDuressPassphrase({
    required String vaultPassphrase,
    required String duressPassphrase,
    String? customPath,
  }) async {
    if (duressPassphrase.trim().isEmpty) {
      throw ArgumentError('O PIN de coação não pode ser vazio.');
    }
    if (duressPassphrase == vaultPassphrase) {
      throw ArgumentError('O PIN de coação deve ser distinto da senha principal.');
    }
    await unlock(passphrase: vaultPassphrase, customPath: customPath);

    final path = customPath ?? getDefaultBootstrapPath();
    final data =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    data['duressVerifier'] = await _buildDuressVerifier(duressPassphrase);
    await _writeBootstrapAtomic(path, data);
  }

  /// Desbloqueia o cofre avaliando também eventual PIN de coação.
  /// Caso o PIN de coação corresponda, bloqueia o cofre em RAM e retorna
  /// [VaultUnlockStatus.duressTriggered] sem decifrar a chave mestre.
  Future<VaultUnlockResult> unlockOrDuress({
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
      throw const VaultAuthenticationException(
          'Arquivo de bootstrap corrompido ou inválido.');
    }

    final duressMap = data['duressVerifier'] as Map<String, dynamic>?;
    if (duressMap != null && await _matchesDuress(passphrase, duressMap)) {
      lock();
      return const VaultUnlockResult.duressTriggered();
    }

    final key = await _unlockFromMap(data, passphrase);
    return VaultUnlockResult.unlocked(key);
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
      throw const VaultAuthenticationException(
          'Arquivo de bootstrap corrompido ou inválido.');
    }
    return _unlockFromMap(data, passphrase);
  }

  Future<Uint8List> _unlockFromMap(
    Map<String, dynamic> data,
    String passphrase,
  ) async {
    final kdfMap = data['kdf'] as Map<String, dynamic>?;
    final wrappedMap = data['wrappedKey'] as Map<String, dynamic>?;

    if (kdfMap == null || wrappedMap == null) {
      throw const VaultAuthenticationException(
          'Estrutura de bootstrap incompleta.');
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
        throw const VaultAuthenticationException(
            'Comprimento de chave decifrada inconsistente.');
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
    final currentKey =
        await unlock(passphrase: oldPassphrase, customPath: customPath);
    if (newPassphrase.trim().isEmpty) {
      throw ArgumentError('A nova senha não pode ser vazia.');
    }

    final path = customPath ?? getDefaultBootstrapPath();
    final existingData =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;

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

    final bootstrapData = <String, dynamic>{
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
      if (existingData['duressVerifier'] != null)
        'duressVerifier': existingData['duressVerifier'],
    };

    await _writeBootstrapAtomic(path, bootstrapData);
    if (_osKeyStorage.isHardwareOrOsBacked &&
        await _osKeyStorage.readSecret(_keyringKey(path)) != null) {
      await _osKeyStorage.storeSecret(_keyringKey(path), newPassphrase);
    }

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

  /// Remove um arquivo bootstrap recém-criado quando a inicialização subsequente do SQLCipher falha.
  Future<void> rollbackFreshBootstrap({String? customPath}) async {
    lock();
    final path = customPath ?? getDefaultBootstrapPath();
    try {
      await _osKeyStorage.deleteSecret(_keyringKey(path));
    } catch (_) {}
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static String _keyringKey(String path) =>
      '${osKeyringPassphraseSlot}_${path.hashCode.toUnsigned(32)}';

  static Future<Map<String, dynamic>> _buildDuressVerifier(
      String duressPassphrase) async {
    final salt = PassphraseKdf.generateSalt(saltLength);
    const kdf = PassphraseKdf.strong();
    final derived =
        await kdf.deriveKey(passphrase: duressPassphrase, salt: salt);
    final bytes = Uint8List.fromList(derived.bytes);
    try {
      return {
        'algorithm': 'Argon2id',
        'memoryKib': kdf.memoryKib,
        'iterations': kdf.iterations,
        'parallelism': kdf.parallelism,
        'hashLength': kdf.hashLength,
        'salt': base64Encode(salt),
        'verifier': base64Encode(bytes),
      };
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  static Future<bool> _matchesDuress(
    String candidate,
    Map<String, dynamic> duressMap,
  ) async {
    try {
      final salt = base64Decode(duressMap['salt'] as String);
      final expected = base64Decode(duressMap['verifier'] as String);
      final kdf = PassphraseKdf(
        memoryKib: duressMap['memoryKib'] as int? ?? 65536,
        iterations: duressMap['iterations'] as int? ?? 3,
        parallelism: duressMap['parallelism'] as int? ?? 1,
        hashLength: duressMap['hashLength'] as int? ?? 32,
      );
      final actualData =
          await kdf.deriveKey(passphrase: candidate, salt: salt);
      final actual = Uint8List.fromList(actualData.bytes);
      try {
        if (actual.length != expected.length) return false;
        var diff = 0;
        for (int i = 0; i < actual.length; i++) {
          diff |= actual[i] ^ expected[i];
        }
        return diff == 0;
      } finally {
        actual.fillRange(0, actual.length, 0);
      }
    } catch (_) {
      return false;
    }
  }

  static Future<void> _writeBootstrapAtomic(
      String path, Map<String, dynamic> data) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final tempFile = File('$path.tmp_${DateTime.now().microsecondsSinceEpoch}');
    await tempFile.writeAsString(jsonEncode(data), flush: true);
    await tempFile.rename(path);
  }
}
