import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart' as sqlite_open;

/// Informações de versão e integridade de uma migração do banco de dados local.
class SchemaMigrationRecord {
  final int version;
  final int appliedAt;
  final String checksum;

  const SchemaMigrationRecord({
    required this.version,
    required this.appliedAt,
    required this.checksum,
  });
}

/// Diagnóstico do motor criptográfico do banco de dados.
class DatabaseCipherInfo {
  final bool isEncrypted;
  final String cipherEngine;
  final String? cipherVersion;

  const DatabaseCipherInfo({
    required this.isEncrypted,
    required this.cipherEngine,
    this.cipherVersion,
  });

  @override
  String toString() =>
      'DatabaseCipherInfo(isEncrypted: $isEncrypted, engine: $cipherEngine, version: $cipherVersion)';
}

/// Motor soberano de banco de dados SQLite/SQLCipher para o cliente Nix (Marco P0-2).
///
/// Implementa a especificação técnica definida em `05_NIX_DATABASE_ARCHITECTURE.md`:
/// - Foreign keys estritas habilitadas por conexão (`PRAGMA foreign_keys = ON`).
/// - Runner de migrações transacional com verificação de integridade SHA-256 e tabela `schema_migrations`.
/// - Proteção por chave SQLCipher raw de 32 bytes fornecida pelo [KeyVault].
/// - Target de schema final: `user_version = 2`.
class LocalDatabase {
  static const int targetSchemaVersion = 2;

  // Checksums esperados dos arquivos formais de migração
  static const String checksumMigration001 =
      '57691040b97e9fb7b29322ab70ead31e5c0e97d3c22aad2340e4a3a8751b3113';
  static const String checksumMigration002 =
      '40d339ade7d30f25856a118fa73909668a05919d8b3d895ee8fe6625358deb64';

  final Database _db;
  final DatabaseCipherInfo _cipherInfo;

  LocalDatabase._(this._db, this._cipherInfo);

  Database get rawDatabase => _db;
  DatabaseCipherInfo get cipherInfo => _cipherInfo;

  /// Caminho padrão para o arquivo do banco SQLite local.
  static String getDefaultDatabasePath() {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) {
      return '.nix_local_v4.db';
    }
    return '$home/.local/share/nix/nix_local_v4.db';
  }

  static bool _sqliteInitialized = false;

  /// Garante que o motor SQLite FFI seja inicializado com resolução dinâmica robusta no Linux.
  static void ensureSqliteInitialized() {
    if (_sqliteInitialized) return;
    if (Platform.isLinux) {
      try {
        sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.linux, () {
          final candidates = [
            'libsqlite3.so',
            'libsqlite3.so.0',
            '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
            '/usr/lib/libsqlite3.so.0',
            '${Platform.environment['HOME']}/.local/lib/libsqlite3.so',
            '${Platform.environment['HOME']}/.local/share/nix/bundle/lib/libsqlite3.so',
          ];
          for (final path in candidates) {
            try {
              return DynamicLibrary.open(path);
            } catch (_) {}
          }
          return DynamicLibrary.open('libsqlite3.so');
        });
      } catch (_) {}
    }
    try {
      sqfliteFfiInit();
    } catch (_) {}
    _sqliteInitialized = true;
  }

  /// Inicializa e abre a conexão com o banco de dados local, aplicando migrações pendentes.
  static Future<LocalDatabase> open({
    String? path,
    Uint8List? rawCipherKey,
    DatabaseFactory? customFactory,
    // Overrides explícitos são SQL confiável de testes, fora dos arquivos oficiais.
    String? migration001Sql,
    String? migration002Sql,
  }) async {
    ensureSqliteInitialized();
    final dbPath = path ?? getDefaultDatabasePath();
    final factory = customFactory ?? databaseFactoryFfiNoIsolate;

    // Garante que o diretório pai existe
    if (dbPath != inMemoryDatabasePath) {
      final parentDir = File(dbPath).parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
    }

    final db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        singleInstance: true,
      ),
    );

    // 1. Aplica chave de criptografia ANTES de qualquer leitura/escrita se fornecida
    DatabaseCipherInfo cipherInfo;
    if (rawCipherKey != null) {
      if (rawCipherKey.length != 32) {
        await db.close();
        throw ArgumentError('A chave raw SQLCipher deve possuir exatamente 32 bytes.');
      }
      final hexKey = rawCipherKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      try {
        await db.execute("PRAGMA key = \"x'$hexKey'\";");
      } catch (e) {
        await db.close();
        throw StateError('Falha ao aplicar chave de cifragem no SQLite/SQLCipher: $e');
      }

      // Inspeciona versão do SQLCipher
      String? cipherVersion;
      try {
        final res = await db.rawQuery('PRAGMA cipher_version;');
        if (res.isNotEmpty && res.first.values.isNotEmpty) {
          cipherVersion = res.first.values.first?.toString();
        }
      } catch (_) {
        cipherVersion = null;
      }

      final isEncrypted =
          cipherVersion != null && cipherVersion.trim().isNotEmpty;
      cipherInfo = DatabaseCipherInfo(
        isEncrypted: isEncrypted,
        cipherEngine: isEncrypted ? 'SQLCipher' : 'SQLite-Development-Clearnet',
        cipherVersion: cipherVersion,
      );
    } else {
      cipherInfo = const DatabaseCipherInfo(
        isEncrypted: false,
        cipherEngine: 'SQLite-Development-Clearnet',
        cipherVersion: null,
      );
    }

    // 2. Configurações fundamentais de conexão
    await db.execute('PRAGMA foreign_keys = ON;');
    await db.execute('PRAGMA busy_timeout = 5000;');

    // 3. Executa Runner de Migrações
    final instance = LocalDatabase._(db, cipherInfo);
    try {
      await instance._runMigrations(
        migration001Override: migration001Sql,
        migration002Override: migration002Sql,
      );
    } catch (_) {
      await db.close();
      rethrow;
    }

    return instance;
  }

  /// Executa o pipeline de migrações transacionais validando user_version e checksums.
  Future<void> _runMigrations({
    String? migration001Override,
    String? migration002Override,
  }) async {
    final versionResult = await _db.rawQuery('PRAGMA user_version;');
    final currentVersion = versionResult.first['user_version'] as int? ?? 0;

    if (currentVersion > targetSchemaVersion) {
      throw StateError(
        'Versão do banco de dados ($currentVersion) é mais recente que o suporte da aplicação ($targetSchemaVersion). Abortando para evitar corrupção.',
      );
    }

    if (currentVersion == targetSchemaVersion) {
      // Banco já está atualizado no target esperado (v2)
      return;
    }

    // Valida TODOS os arquivos pendentes antes de aplicar a primeira migração.
    // Overrides são entradas confiáveis e explícitas para testes sintéticos.
    final sql001 = currentVersion == 0
        ? migration001Override ??
            await _loadMigrationFile('local_001_initial.sql')
        : null;
    final sql002 = migration002Override ??
        await _loadMigrationFile('local_002_lookup_indexes.sql');
    if (sql001 != null && migration001Override == null) {
      _verifyChecksum(sql001, checksumMigration001, 1);
    }
    if (migration002Override == null) {
      _verifyChecksum(sql002, checksumMigration002, 2);
    }

    // Migração 0 -> 1: Schema Inicial Completo
    if (currentVersion == 0) {
      final sql = sql001!;
      final computedChecksum = sha256.convert(utf8.encode(sql)).toString();

      // Executa em transação estrita
      await _db.transaction((txn) async {
        // Divide os comandos SQL respeitando blocos e triggers
        final statements = _splitSqlStatements(sql);
        for (final statement in statements) {
          final trimmed = statement.trim();
          if (trimmed.isNotEmpty &&
              !trimmed.startsWith('PRAGMA user_version') &&
              !trimmed.startsWith('BEGIN') &&
              !trimmed.startsWith('COMMIT')) {
            await txn.execute(trimmed);
          }
        }

        final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
        await txn.rawInsert(
          'INSERT INTO schema_migrations(version, applied_at, checksum) VALUES(?, ?, ?);',
          [1, nowMs, computedChecksum],
        );
        await txn.execute('PRAGMA user_version = 1;');
      });
    }

    // Migração 1 -> 2: Índices de Busca e Performance
    final v1Check = await _db.rawQuery('PRAGMA user_version;');
    if ((v1Check.first['user_version'] as int? ?? 0) == 1) {
      final sql = sql002;
      final computedChecksum = sha256.convert(utf8.encode(sql)).toString();

      await _db.transaction((txn) async {
        final statements = _splitSqlStatements(sql);
        for (final statement in statements) {
          final trimmed = statement.trim();
          if (trimmed.isNotEmpty &&
              !trimmed.startsWith('PRAGMA user_version') &&
              !trimmed.startsWith('BEGIN') &&
              !trimmed.startsWith('COMMIT')) {
            await txn.execute(trimmed);
          }
        }

        final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
        await txn.rawInsert(
          'INSERT INTO schema_migrations(version, applied_at, checksum) VALUES(?, ?, ?);',
          [2, nowMs, computedChecksum],
        );
        await txn.execute('PRAGMA user_version = 2;');
      });
    }
  }

  static void _verifyChecksum(String sql, String expected, int version) {
    if (sha256.convert(utf8.encode(sql)).toString() != expected) {
      throw StateError('Checksum inválido para a migração local $version.');
    }
  }

  /// Carrega o script SQL a partir do diretório de migrações do repositório ou assets.
  static Future<String> _loadMigrationFile(String filename) async {
    // Procura em caminhos padrão
    final candidates = [
      'database/migrations/$filename',
      '../../database/migrations/$filename',
    ];

    for (final candidate in candidates) {
      final file = File(candidate);
      if (await file.exists()) {
        return file.readAsString();
      }
    }

    throw FileSystemException('Arquivo de migração obrigatório não encontrado: $filename');
  }

  /// Separa declarações SQL preservando blocos BEGIN ... END em triggers e transações.
  static List<String> _splitSqlStatements(String sql) {
    final statements = <String>[];
    final buffer = StringBuffer();
    bool insideTrigger = false;

    final lines = sql.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('--')) continue; // Ignora comentários de linha única

      if (trimmed.toUpperCase().contains('CREATE TRIGGER')) {
        insideTrigger = true;
      }

      buffer.writeln(line);

      if (insideTrigger) {
        if (trimmed.toUpperCase().endsWith('END;')) {
          insideTrigger = false;
          statements.add(buffer.toString());
          buffer.clear();
        }
      } else {
        if (trimmed.endsWith(';')) {
          statements.add(buffer.toString());
          buffer.clear();
        }
      }
    }

    if (buffer.isNotEmpty && buffer.toString().trim().isNotEmpty) {
      statements.add(buffer.toString());
    }

    return statements;
  }

  /// Retorna as migrações já registradas no banco.
  Future<List<SchemaMigrationRecord>> getAppliedMigrations() async {
    final rows = await _db.query('schema_migrations', orderBy: 'version ASC');
    return rows.map((r) {
      return SchemaMigrationRecord(
        version: r['version'] as int,
        appliedAt: r['appliedAt'] as int? ?? r['applied_at'] as int,
        checksum: r['checksum'] as String,
      );
    }).toList();
  }

  /// Fecha a conexão com o banco de dados.
  Future<void> close() async {
    await _db.close();
  }
}
