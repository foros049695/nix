import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import '../database/local_database.dart';
import 'key_vault.dart';

/// Relatório de execução do procedimento anti-forense.
class ShredReport {
  final int filesOverwritten;
  final int totalBytesWiped;
  final int passesPerFile;
  final bool memoryWiped;
  final List<String> shreddedPaths;
  final Map<String, String> errors;

  const ShredReport({
    required this.filesOverwritten,
    required this.totalBytesWiped,
    required this.passesPerFile,
    required this.memoryWiped,
    required this.shreddedPaths,
    this.errors = const {},
  });

  @override
  String toString() =>
      'ShredReport(files: $filesOverwritten, bytes: $totalBytesWiped, passes: $passesPerFile, memoryWiped: $memoryWiped)';
}

/// Destruidor Soberano Anti-Forense para o Projeto Nix.
///
/// Implementa sobrescrita destrutiva em múltiplas passagens (estilo BleachBit / GNU shred / DoD 5220.22-M):
/// 1. Passagem 1: Bytes pseudoaleatórios criptográficos (CSPRNG via Cryptography).
/// 2. Passagem 2: Padrão binário complementar (0xAA / 0x55 alternados).
/// 3. Passagem 3: Zeros criptográficos (0x00).
/// 4. Sincronização forçada com o hardware de armazenamento (fsync) a cada passagem.
/// 5. Truncamento do arquivo para 0 bytes.
/// 6. Renomeação para hash aleatório no sistema de arquivos para ofuscar metadados de inode.
/// 7. Exclusão definitiva do arquivo.
class AntiForensicShredder {
  static const int defaultPasses = 3;
  static const int chunkSize = 65536; // 64 KiB chunks

  /// Sobrescreve destrutivamente um arquivo específico no disco e o remove sem deixar vestígios.
  static Future<int> shredFile(File file, {int passes = defaultPasses}) async {
    if (!await file.exists()) return 0;

    final length = await file.length();
    if (length == 0) {
      await _obfuscateAndRemove(file);
      return 0;
    }

    // Abre sem truncar; setPosition(0) reposiciona cada passagem.
    final raf = await file.open(mode: FileMode.writeOnlyAppend);
    try {
      final random = Random.secure();
      final randomBuffer = Uint8List(chunkSize);
      final patternBuffer = Uint8List(chunkSize)..fillRange(0, chunkSize, 0x55);
      final zeroBuffer = Uint8List(chunkSize)..fillRange(0, chunkSize, 0x00);

      for (var pass = 1; pass <= passes; pass++) {
        await raf.setPosition(0);
        var remaining = length;

        while (remaining > 0) {
          final writeSize = remaining < chunkSize ? remaining : chunkSize;
          final Uint8List chunk;

          if (pass == 1) {
            // Passagem 1: Entropia aleatória criptográfica
            for (var i = 0; i < writeSize; i++) {
              randomBuffer[i] = random.nextInt(256);
            }
            chunk = Uint8List.sublistView(randomBuffer, 0, writeSize);
          } else if (pass == 2) {
            // Passagem 2: Padrão complementar (0x55)
            chunk = Uint8List.sublistView(patternBuffer, 0, writeSize);
          } else {
            // Passagem 3: Zeros (0x00)
            chunk = Uint8List.sublistView(zeroBuffer, 0, writeSize);
          }

          await raf.writeFrom(chunk);
          remaining -= writeSize;
        }

        // Força sincronização com o hardware (fsync)
        await raf.flush();
      }

      // Trunca o arquivo para tamanho zero
      await raf.truncate(0);
    } finally {
      await raf.close();
    }

    // Ofusca o nome e metadados no sistema de arquivos antes de apagar
    await _obfuscateAndRemove(file);
    return length * passes;
  }

  /// Renomeia o arquivo para um nome aleatório antes de deletar, destruindo vestígios em diretórios.
  static Future<void> _obfuscateAndRemove(File file) async {
    try {
      final parentDir = file.parent.path;
      final randomSuffix = List.generate(
          16, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
      final obfuscatedFile =
          await file.rename('$parentDir/.nix_wipe_$randomSuffix');
      await obfuscatedFile.delete();
    } catch (_) {
      // Fallback para delete direto se o rename falhar por permissões
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  /// Calcula os alvos sem acessar o ambiente ou o sistema de arquivos.
  /// Um diretório explícito nunca inclui os caminhos padrão do usuário.
  static List<String> wipeTargets(
      {required String home, String? customBaseDir}) {
    final baseDir =
        customBaseDir ?? (home.isNotEmpty ? '$home/.local/share/nix' : '.');
    return [
      // O bootstrap da chave vem antes dos arquivos do banco.
      if (customBaseDir == null && home.isEmpty) '.nix_vault_bootstrap.json',
      '$baseDir/vault_bootstrap.json',
      if (customBaseDir == null && home.isEmpty) '.nix_local_v4.db',
      '$baseDir/nix_local_v4.db',
      '$baseDir/nix_local_v4.db-wal',
      '$baseDir/nix_local_v4.db-shm',
      '$baseDir/client_prefs_v4.json',
    ];
  }

  /// Procedimento de PÂNICO / APAGAMENTO TOTAL DA CONTA:
  /// - Fecha todas as conexões de banco de dados.
  /// - Sobrescreve com zeros a chave mestre na memória RAM (`KeyVault.lock()`).
  /// - Destrói destrutivamente o banco SQLCipher, WAL, SHM, cofre de chaves, preferências e cache.
  static Future<ShredReport> panicWipeAccount({
    LocalDatabase? activeDatabase,
    KeyVault? activeVault,
    String? customBaseDir,
    int passes = defaultPasses,
  }) async {
    var filesOverwritten = 0;
    var totalBytesWiped = 0;
    var memoryWiped = false;
    final shreddedPaths = <String>[];
    final errors = <String, String>{};

    if (activeDatabase != null) {
      try {
        await activeDatabase.close();
      } catch (error) {
        errors['database.close'] = error.toString();
      }
    }

    if (activeVault != null) {
      final wasUnlocked = activeVault.isUnlocked;
      try {
        activeVault.lock();
        memoryWiped = wasUnlocked && !activeVault.isUnlocked;
      } catch (error) {
        errors['vault.lock'] = error.toString();
      }
    }

    final home = Platform.environment['HOME'] ?? '';
    final baseDir =
        customBaseDir ?? (home.isNotEmpty ? '$home/.local/share/nix' : '.');

    Future<void> wipeTarget(String path) async {
      try {
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.notFound) return;
        if (type != FileSystemEntityType.file) {
          throw FileSystemException('Alvo não é arquivo regular', path);
        }
        final bytes = await shredFile(File(path), passes: passes);
        totalBytesWiped += bytes;
        filesOverwritten += 1;
        shreddedPaths.add(path);
      } catch (error) {
        // Uma falha não impede a destruição dos demais alvos.
        errors[path] = error.toString();
      }
    }

    for (final target
        in wipeTargets(home: home, customBaseDir: customBaseDir)) {
      await wipeTarget(target);
    }

    // Não segue links do cache para arquivos fora do diretório da conta.
    final storageDir = Directory('$baseDir/storage');
    try {
      final type =
          await FileSystemEntity.type(storageDir.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw FileSystemException(
            'Cache não pode ser link simbólico', storageDir.path);
      }
      if (type == FileSystemEntityType.directory) {
        final errorsBefore = errors.length;
        await for (final entity
            in storageDir.list(recursive: true, followLinks: false)) {
          if (entity is Link) {
            // Remove somente o link, sem abrir ou apagar o alvo externo.
            try {
              await entity.delete();
            } catch (error) {
              errors[entity.path] = error.toString();
            }
          } else if (entity is File) {
            await wipeTarget(entity.path);
          }
        }
        if (errors.length == errorsBefore) {
          await storageDir.delete(recursive: true);
        }
      }
    } catch (error) {
      errors[storageDir.path] = error.toString();
    }

    return ShredReport(
      filesOverwritten: filesOverwritten,
      totalBytesWiped: totalBytesWiped,
      passesPerFile: passes,
      memoryWiped: memoryWiped,
      shreddedPaths: shreddedPaths,
      errors: errors,
    );
  }
}
