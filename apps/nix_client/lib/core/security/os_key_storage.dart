import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'android_keystore_channel_stub.dart'
    if (dart.library.ui) 'android_keystore_channel_flutter.dart';

part 'windows_credential_storage.dart';

/// Abstração para armazenamento de material de desbloqueio no cofre nativo do SO:
/// - Linux Desktop: D-Bus Secret Service via `libsecret-1.so.0` (gnome-keyring / KWallet)
/// - Windows: Windows Credential Manager (credencial genérica por usuário)
/// - Android: Hardware/TEE `AndroidKeyStore` (AES-256-GCM) via MethodChannel
/// - Ambiente headless/testes: fallback explícito que não simula segurança onde não existe
abstract class OsKeyStorage {
  String get backendName;
  bool get isHardwareOrOsBacked;

  Future<bool> storeSecret(String key, String value);
  Future<String?> readSecret(String key);
  Future<bool> deleteSecret(String key);

  static OsKeyStorage createDefault() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return PassphraseOnlyKeyStorage();
    }
    if (Platform.isAndroid) {
      return AndroidKeystoreKeyStorage();
    }
    if (Platform.isWindows) {
      return WindowsCredentialStorage.tryOpen() ?? PassphraseOnlyKeyStorage();
    }
    if (Platform.isLinux) {
      final linuxStorage = LinuxLibsecretKeyStorage.tryOpen();
      if (linuxStorage != null) {
        return linuxStorage;
      }
    }
    return PassphraseOnlyKeyStorage();
  }
}

/// Implementação nula honesta para ambientes sem daemon keyring (ex: headless/CI).
/// Nunca grava segredos em claro em arquivo para fingir ser cofre do SO.
class PassphraseOnlyKeyStorage implements OsKeyStorage {
  @override
  String get backendName => 'Passphrase-Only (Sem Keyring OS Ativo)';

  @override
  bool get isHardwareOrOsBacked => false;

  @override
  Future<bool> storeSecret(String key, String value) async => false;

  @override
  Future<String?> readSecret(String key) async => null;

  @override
  Future<bool> deleteSecret(String key) async => false;
}

/// Armazenamento em memória para testes unitários isolados.
class InMemoryOsKeyStorage implements OsKeyStorage {
  final Map<String, String> _secrets = {};

  @override
  String get backendName => 'InMemory-Test-KeyStorage';

  @override
  bool get isHardwareOrOsBacked => true;

  @override
  Future<bool> storeSecret(String key, String value) async {
    _secrets[key] = value;
    return true;
  }

  @override
  Future<String?> readSecret(String key) async => _secrets[key];

  @override
  Future<bool> deleteSecret(String key) async {
    _secrets.remove(key);
    return true;
  }
}

/// Ponte AndroidKeyStore real (`MainActivity.kt` AES/GCM/NoPadding).
class AndroidKeystoreKeyStorage implements OsKeyStorage {
  @override
  String get backendName => 'AndroidKeyStore (AES-256-GCM)';

  @override
  bool get isHardwareOrOsBacked => true;

  @override
  Future<bool> storeSecret(String key, String value) async {
    try {
      final res = await invokeKeystoreChannel<bool>(
        'storeSecret',
        {'key': key, 'value': value},
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> readSecret(String key) async {
    try {
      return await invokeKeystoreChannel<String>('readSecret', {'key': key});
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> deleteSecret(String key) async {
    try {
      final res = await invokeKeystoreChannel<bool>(
        'deleteSecret',
        {'key': key},
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}

typedef _GHashTableNewFunc = Pointer<Void> Function(
    Pointer<Void> hashFunc, Pointer<Void> equalFunc);
typedef _GHashTableInsertNative = Int32 Function(
    Pointer<Void> ht, Pointer<Void> key, Pointer<Void> value);
typedef _GHashTableInsertDart = int Function(
    Pointer<Void> ht, Pointer<Void> key, Pointer<Void> value);
typedef _GHashTableUnrefNative = Void Function(Pointer<Void> ht);
typedef _GHashTableUnrefDart = void Function(Pointer<Void> ht);
typedef _SecretSchemaNewvNative = Pointer<Void> Function(
    Pointer<Utf8> name, Int32 flags, Pointer<Void> attrs);
typedef _SecretSchemaNewvDart = Pointer<Void> Function(
    Pointer<Utf8> name, int flags, Pointer<Void> attrs);
typedef _SecretStorevNative = Int32 Function(
    Pointer<Void> schema,
    Pointer<Void> attrs,
    Pointer<Utf8> collection,
    Pointer<Utf8> label,
    Pointer<Utf8> password,
    Pointer<Void> cancel,
    Pointer<Pointer<Void>> err);
typedef _SecretStorevDart = int Function(
    Pointer<Void> schema,
    Pointer<Void> attrs,
    Pointer<Utf8> collection,
    Pointer<Utf8> label,
    Pointer<Utf8> password,
    Pointer<Void> cancel,
    Pointer<Pointer<Void>> err);
typedef _SecretLookupvNative = Pointer<Utf8> Function(Pointer<Void> schema,
    Pointer<Void> attrs, Pointer<Void> cancel, Pointer<Pointer<Void>> err);
typedef _SecretLookupvDart = Pointer<Utf8> Function(Pointer<Void> schema,
    Pointer<Void> attrs, Pointer<Void> cancel, Pointer<Pointer<Void>> err);
typedef _SecretClearvNative = Int32 Function(Pointer<Void> schema,
    Pointer<Void> attrs, Pointer<Void> cancel, Pointer<Pointer<Void>> err);
typedef _SecretClearvDart = int Function(Pointer<Void> schema,
    Pointer<Void> attrs, Pointer<Void> cancel, Pointer<Pointer<Void>> err);
typedef _SecretFreeNative = Void Function(Pointer<Utf8> password);
typedef _SecretFreeDart = void Function(Pointer<Utf8> password);

/// Driver FFI direto para `libsecret-1.so.0` (gnome-keyring / Secret Service D-Bus),
/// sem exigir pacotes `-dev` em tempo de compilação.
class LinuxLibsecretKeyStorage implements OsKeyStorage {
  final _GHashTableNewFunc _gHashNew;
  final _GHashTableInsertDart _gHashInsert;
  final _GHashTableUnrefDart _gHashUnref;
  final _SecretSchemaNewvDart _schemaNewv;
  final _SecretStorevDart _storev;
  final _SecretLookupvDart _lookupv;
  final _SecretClearvDart _clearv;
  final _SecretFreeDart _secretFree;
  final Pointer<Void> _gStrHash;
  final Pointer<Void> _gStrEqual;

  LinuxLibsecretKeyStorage._(
    this._gHashNew,
    this._gHashInsert,
    this._gHashUnref,
    this._schemaNewv,
    this._storev,
    this._lookupv,
    this._clearv,
    this._secretFree,
    this._gStrHash,
    this._gStrEqual,
  );

  static LinuxLibsecretKeyStorage? tryOpen() {
    if (!Platform.isLinux) return null;
    if ((Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? '').isEmpty) {
      return null;
    }
    try {
      final glib = DynamicLibrary.open('libglib-2.0.so.0');
      final libsecret = DynamicLibrary.open('libsecret-1.so.0');
      return LinuxLibsecretKeyStorage._(
        glib.lookupFunction<_GHashTableNewFunc, _GHashTableNewFunc>(
            'g_hash_table_new'),
        glib.lookupFunction<_GHashTableInsertNative, _GHashTableInsertDart>(
            'g_hash_table_insert'),
        glib.lookupFunction<_GHashTableUnrefNative, _GHashTableUnrefDart>(
            'g_hash_table_unref'),
        libsecret.lookupFunction<_SecretSchemaNewvNative, _SecretSchemaNewvDart>(
            'secret_schema_newv'),
        libsecret.lookupFunction<_SecretStorevNative, _SecretStorevDart>(
            'secret_password_storev_sync'),
        libsecret.lookupFunction<_SecretLookupvNative, _SecretLookupvDart>(
            'secret_password_lookupv_sync'),
        libsecret.lookupFunction<_SecretClearvNative, _SecretClearvDart>(
            'secret_password_clearv_sync'),
        libsecret.lookupFunction<_SecretFreeNative, _SecretFreeDart>(
            'secret_password_free'),
        glib.lookup<Void>('g_str_hash'),
        glib.lookup<Void>('g_str_equal'),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String get backendName => 'Linux Secret Service (libsecret / gnome-keyring)';

  @override
  bool get isHardwareOrOsBacked => true;

  T _withKey<T>(
      String key, T Function(Pointer<Void> schema, Pointer<Void> attrs) fn) {
    final schemaAttrs = _gHashNew(_gStrHash, _gStrEqual);
    final kService = 'nix_service'.toNativeUtf8();
    final kKey = 'nix_key'.toNativeUtf8();
    final schemaName = 'com.projetonix.nix.vault'.toNativeUtf8();
    final vService = 'nix_local_vault'.toNativeUtf8();
    final vKey = key.toNativeUtf8();
    _gHashInsert(schemaAttrs, kService.cast(), Pointer.fromAddress(0));
    _gHashInsert(schemaAttrs, kKey.cast(), Pointer.fromAddress(0));
    final schema = _schemaNewv(schemaName, 0, schemaAttrs);
    final attrs = _gHashNew(_gStrHash, _gStrEqual);
    _gHashInsert(attrs, kService.cast(), vService.cast());
    _gHashInsert(attrs, kKey.cast(), vKey.cast());
    try {
      return fn(schema, attrs);
    } finally {
      _gHashUnref(attrs);
      _gHashUnref(schemaAttrs);
      calloc.free(vKey);
      calloc.free(vService);
      calloc.free(schemaName);
      calloc.free(kKey);
      calloc.free(kService);
    }
  }

  @override
  Future<bool> storeSecret(String key, String value) async {
    return _withKey(key, (schema, attrs) {
      final label = 'Projeto Nix KeyVault ($key)'.toNativeUtf8();
      final secret = value.toNativeUtf8();
      final errPtr = calloc<Pointer<Void>>();
      errPtr.value = nullptr;
      try {
        final ok =
            _storev(schema, attrs, nullptr, label, secret, nullptr, errPtr);
        return ok != 0 && errPtr.value == nullptr;
      } finally {
        calloc.free(errPtr);
        calloc.free(secret);
        calloc.free(label);
      }
    });
  }

  @override
  Future<String?> readSecret(String key) async {
    return _withKey(key, (schema, attrs) {
      final errPtr = calloc<Pointer<Void>>();
      errPtr.value = nullptr;
      try {
        final foundPtr = _lookupv(schema, attrs, nullptr, errPtr);
        if (foundPtr == nullptr || errPtr.value != nullptr) {
          return null;
        }
        try {
          return foundPtr.toDartString();
        } finally {
          _secretFree(foundPtr);
        }
      } finally {
        calloc.free(errPtr);
      }
    });
  }

  @override
  Future<bool> deleteSecret(String key) async {
    return _withKey(key, (schema, attrs) {
      final errPtr = calloc<Pointer<Void>>();
      errPtr.value = nullptr;
      try {
        final ok = _clearv(schema, attrs, nullptr, errPtr);
        return ok != 0 && errPtr.value == nullptr;
      } finally {
        calloc.free(errPtr);
      }
    });
  }
}
