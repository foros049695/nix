import 'dart:io';
import 'platform_channel_stub.dart'
    if (dart.library.ui) 'platform_channel_flutter.dart';

/// Diagnóstico real do runtime nativo (Linux Desktop / Android NDK / TEE / Tor Móvel).
class NixPlatformRuntimeInfo {
  final String dataDir;
  final String? nativeLibraryDir;
  final String? androidTorBinaryPath;
  final bool androidTorBinaryExists;
  final int? androidSdkInt;
  final String deviceAbi;
  final bool allowBackupDisabled;
  final String keystoreSecurityLevel;
  final bool keystoreInsideSecureHardware;

  const NixPlatformRuntimeInfo({
    required this.dataDir,
    this.nativeLibraryDir,
    this.androidTorBinaryPath,
    this.androidTorBinaryExists = false,
    this.androidSdkInt,
    this.deviceAbi = 'unknown',
    this.allowBackupDisabled = true,
    this.keystoreSecurityLevel = 'UNKNOWN',
    this.keystoreInsideSecureHardware = false,
  });
}

/// Resolvedor portátil de caminhos de persistência e binários nativos (Linux & Android).
///
/// Em Android, `Platform.environment['HOME']` é vazio ou aponta para `/` somente-leitura;
/// esta classe consulta `MainActivity.kt` (`com.projetonix.nix/platform` e `keystore`)
/// na inicialização para obter `context.filesDir`, `nativeLibraryDir/libtor.so` e nível TEE.
class NixPlatformPaths {
  static NixPlatformRuntimeInfo? _runtimeInfo;
  static bool _initialized = false;

  static NixPlatformRuntimeInfo? get runtimeInfo => _runtimeInfo;
  static bool get isInitialized => _initialized;

  /// Inicializa os diretórios nativos e consulta telemetria de segurança do hardware local.
  static Future<void> initialize() async {
    if (_initialized) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _initialized = true;
      return;
    }

    if (Platform.isAndroid) {
      String filesDir = '';
      String? nativeLibDir;
      String? torBin;
      bool torExists = false;
      int? sdkInt;
      String abi = 'arm64-v8a';
      bool backupDisabled = true;

      try {
        final res = await invokePlatformRuntimeInfo();
        if (res != null) {
          filesDir = (res['filesDir'] as String?) ?? '';
          nativeLibDir = res['nativeLibraryDir'] as String?;
          torBin = res['torBinaryPath'] as String?;
          torExists = (res['torBinaryExists'] as bool?) ?? false;
          sdkInt = res['sdkInt'] as int?;
          abi = (res['primaryAbi'] as String?) ?? abi;
          backupDisabled = (res['allowBackupDisabled'] as bool?) ?? true;
        }
      } catch (_) {}

      String ksLevel = 'ANDROID_KEYSTORE';
      bool ksHardware = false;
      try {
        final ksInfo = await invokeKeystoreSecurityInfo();
        if (ksInfo != null) {
          ksLevel = (ksInfo['securityLevel'] as String?) ?? ksLevel;
          ksHardware = (ksInfo['isInsideSecureHardware'] as bool?) ?? false;
        }
      } catch (_) {}

      final effectiveDataDir = filesDir.isNotEmpty
          ? '$filesDir/nix_data'
          : '/data/user/0/com.projetonix.nix_client/files/nix_data';

      _runtimeInfo = NixPlatformRuntimeInfo(
        dataDir: effectiveDataDir,
        nativeLibraryDir: nativeLibDir,
        androidTorBinaryPath: torBin,
        androidTorBinaryExists: torExists,
        androidSdkInt: sdkInt,
        deviceAbi: abi,
        allowBackupDisabled: backupDisabled,
        keystoreSecurityLevel: ksLevel,
        keystoreInsideSecureHardware: ksHardware,
      );
      _initialized = true;
      return;
    }

    // Linux / Desktop POSIX
    final home = Platform.environment['HOME'] ?? '';
    final dataDir = home.isNotEmpty ? '$home/.local/share/nix' : '.nix_data';
    _runtimeInfo = NixPlatformRuntimeInfo(
      dataDir: dataDir,
      deviceAbi: Platform.version.contains('arm64') ? 'linux-arm64' : 'linux-x64',
      allowBackupDisabled: true,
      keystoreSecurityLevel: 'LINUX_LIBSECRET',
      keystoreInsideSecureHardware: false,
    );
    _initialized = true;
  }

  /// Resolve um caminho dentro do diretório soberano de dados do aplicativo.
  static String resolveDataFile(String filename) {
    final rt = _runtimeInfo;
    if (rt != null && rt.dataDir.isNotEmpty) {
      return '${rt.dataDir}/$filename';
    }
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) {
      return '.$filename';
    }
    return '$home/.local/share/nix/$filename';
  }

  /// Retorna candidatos extras para o binário Tor nativo (ex: `nativeLibraryDir/libtor.so` no Android).
  static List<String> extraTorBinaryCandidates() {
    final rt = _runtimeInfo;
    if (rt == null) return const [];
    return [
      if (rt.androidTorBinaryPath != null &&
          rt.androidTorBinaryPath!.isNotEmpty)
        rt.androidTorBinaryPath!,
      if (rt.nativeLibraryDir != null && rt.nativeLibraryDir!.isNotEmpty)
        '${rt.nativeLibraryDir}/libtor.so',
    ];
  }
}
