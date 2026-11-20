part of 'os_key_storage.dart';

// CREDENTIALW em wincred.h. As duas partes de FILETIME preservam
// o alinhamento de 32 bits antes de CredentialBlobSize.
final class _WindowsCredential extends Struct {
  @Uint32()
  external int flags;
  @Uint32()
  external int type;
  external Pointer<Utf16> targetName;
  external Pointer<Utf16> comment;
  @Uint32()
  external int lastWrittenLow;
  @Uint32()
  external int lastWrittenHigh;
  @Uint32()
  external int blobSize;
  external Pointer<Uint8> blob;
  @Uint32()
  external int persist;
  @Uint32()
  external int attributeCount;
  external Pointer<Void> attributes;
  external Pointer<Utf16> targetAlias;
  external Pointer<Utf16> userName;
}

class WindowsCredentialStorage implements OsKeyStorage {
  static const _generic = 1;
  static const _localMachine = 2;
  static const _maxBlobSize = 2560;

  final DynamicLibrary _advapi;
  final DynamicLibrary _kernel;

  WindowsCredentialStorage._(this._advapi, this._kernel);

  static WindowsCredentialStorage? tryOpen() {
    if (!Platform.isWindows) return null;
    try {
      return WindowsCredentialStorage._(
        DynamicLibrary.open('advapi32.dll'),
        DynamicLibrary.open('kernel32.dll'),
      );
    } on ArgumentError {
      return null;
    }
  }

  late final _write = _advapi.lookupFunction<
      Int32 Function(Pointer<_WindowsCredential>, Uint32),
      int Function(Pointer<_WindowsCredential>, int)>('CredWriteW');
  late final _read = _advapi.lookupFunction<
      Int32 Function(
          Pointer<Utf16>, Uint32, Uint32, Pointer<Pointer<_WindowsCredential>>),
      int Function(Pointer<Utf16>, int, int,
          Pointer<Pointer<_WindowsCredential>>)>('CredReadW');
  late final _delete = _advapi.lookupFunction<
      Int32 Function(Pointer<Utf16>, Uint32, Uint32),
      int Function(Pointer<Utf16>, int, int)>('CredDeleteW');
  late final _free = _advapi.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('CredFree');
  late final _lastError =
      _kernel.lookupFunction<Uint32 Function(), int Function()>('GetLastError');

  Pointer<Utf16> _target(String key) {
    if (key.isEmpty || key.length > 128 || key.contains('\u0000')) {
      throw ArgumentError('Identificador do cofre inválido.');
    }
    return 'Projeto Nix/$key'.toNativeUtf16(allocator: calloc);
  }

  @override
  String get backendName => 'Windows Credential Manager';

  @override
  bool get isHardwareOrOsBacked => true;

  @override
  Future<bool> storeSecret(String key, String value) async {
    final bytes = utf8.encode(value);
    if (bytes.isEmpty || bytes.length > _maxBlobSize) return false;
    final target = _target(key);
    final credential = calloc<_WindowsCredential>();
    final blob = calloc<Uint8>(bytes.length);
    try {
      blob.asTypedList(bytes.length).setAll(0, bytes);
      credential.ref
        ..type = _generic
        ..targetName = target
        ..blobSize = bytes.length
        ..blob = blob
        ..persist = _localMachine;
      return _write(credential, 0) != 0;
    } finally {
      blob.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      bytes.fillRange(0, bytes.length, 0);
      calloc.free(blob);
      calloc.free(credential);
      calloc.free(target);
    }
  }

  @override
  Future<String?> readSecret(String key) async {
    final target = _target(key);
    final output = calloc<Pointer<_WindowsCredential>>();
    try {
      if (_read(target, _generic, 0, output) == 0) return null;
      final credential = output.value.ref;
      final length = credential.blobSize;
      if (length == 0 || length > _maxBlobSize || credential.blob == nullptr) {
        return null;
      }
      final bytes = credential.blob.asTypedList(length);
      try {
        return utf8.decode(bytes);
      } on FormatException {
        return null;
      } finally {
        bytes.fillRange(0, length, 0);
      }
    } finally {
      if (output.value != nullptr) _free(output.value.cast<Void>());
      calloc.free(output);
      calloc.free(target);
    }
  }

  @override
  Future<bool> deleteSecret(String key) async {
    final target = _target(key);
    try {
      return _delete(target, _generic, 0) != 0 || _lastError() == 1168;
    } finally {
      calloc.free(target);
    }
  }
}
