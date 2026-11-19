import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/local_database.dart';
import '../security/platform_runtime.dart';

/// Estados formais da máquina de estados de replicação distribuída (Fase 20 / Etapa 5).
enum ReplicationStatus {
  localOnly,
  queued,
  replicating,
  partiallyReplicated,
  replicated,
  degraded,
  failed,
}

/// Registro de rastreamento de réplicas de um objeto público content-addressed.
class ReplicationRecord {
  final String objectHash;
  final String kind; // 'article', 'catalog_package', 'public_refutation'
  final ReplicationStatus status;
  final List<String> replicaEndpoints;
  final int? lastVerifiedAt;
  final String? lastError;
  final int retryCount;

  const ReplicationRecord({
    required this.objectHash,
    required this.kind,
    required this.status,
    this.replicaEndpoints = const [],
    this.lastVerifiedAt,
    this.lastError,
    this.retryCount = 0,
  });

  ReplicationRecord copyWith({
    ReplicationStatus? status,
    List<String>? replicaEndpoints,
    int? lastVerifiedAt,
    String? lastError,
    int? retryCount,
  }) {
    return ReplicationRecord(
      objectHash: objectHash,
      kind: kind,
      status: status ?? this.status,
      replicaEndpoints: replicaEndpoints ?? this.replicaEndpoints,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
      lastError: lastError ?? this.lastError,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  factory ReplicationRecord.fromRow(Map<String, dynamic> row) {
    List<String> endpoints = [];
    try {
      final raw = row['replica_endpoints_json'];
      if (raw is String && raw.isNotEmpty) {
        endpoints = (jsonDecode(raw) as List<dynamic>).cast<String>();
      }
    } catch (_) {}

    return ReplicationRecord(
      objectHash: row['object_hash'] as String,
      kind: row['kind'] as String,
      status: ReplicationStatus.values.firstWhere(
        (e) => e.name == row['status'],
        orElse: () => ReplicationStatus.failed,
      ),
      replicaEndpoints: endpoints,
      lastVerifiedAt: row['last_verified_at'] as int?,
      lastError: row['last_error'] as String?,
      retryCount: row['retry_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'object_hash': objectHash,
        'kind': kind,
        'status': status.name,
        'replica_endpoints_json': jsonEncode(replicaEndpoints),
        'last_verified_at': lastVerifiedAt,
        'last_error': lastError,
        'retry_count': retryCount,
        'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      };
}

/// Item da fila de replicação persistente (Outbox Pattern).
class ReplicationOutboxItem {
  final String id;
  final String objectHash;
  final String kind;
  final List<int> payloadBytes;
  final ReplicationStatus status;
  final int retryCount;
  final int maxRetries;
  final int nextRetryAt;
  final String? lastError;
  final int createdAt;
  final int updatedAt;

  const ReplicationOutboxItem({
    required this.id,
    required this.objectHash,
    required this.kind,
    required this.payloadBytes,
    required this.status,
    this.retryCount = 0,
    this.maxRetries = 5,
    required this.nextRetryAt,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReplicationOutboxItem.fromRow(Map<String, dynamic> row) {
    return ReplicationOutboxItem(
      id: row['id'] as String,
      objectHash: row['object_hash'] as String,
      kind: row['kind'] as String,
      payloadBytes: row['payload_blob'] as Uint8List,
      status: ReplicationStatus.values.firstWhere(
        (e) => e.name == row['status'],
        orElse: () => ReplicationStatus.queued,
      ),
      retryCount: row['retry_count'] as int? ?? 0,
      maxRetries: row['max_retries'] as int? ?? 5,
      nextRetryAt: row['next_retry_at'] as int? ?? 0,
      lastError: row['last_error'] as String?,
      createdAt: row['created_at'] as int? ?? 0,
      updatedAt: row['updated_at'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'object_hash': objectHash,
        'kind': kind,
        'payload_blob': payloadBytes,
        'status': status.name,
        'retry_count': retryCount,
        'max_retries': maxRetries,
        'next_retry_at': nextRetryAt,
        'last_error': lastError,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

/// Repositório SQLite da fila persistente de replicação (Outbox Pattern).
class ReplicationQueueRepository {
  final Database _db;

  ReplicationQueueRepository._(this._db);

  Database get rawDatabase => _db;

  static Future<ReplicationQueueRepository> open({
    String? path,
    bool inMemory = false,
  }) async {
    LocalDatabase.ensureSqliteInitialized();
    final dbFactory = databaseFactoryFfi;
    final resolvedPath = inMemory
        ? inMemoryDatabasePath
        : (path ?? NixPlatformPaths.resolveDataFile('replication_outbox.db'));

    if (!inMemory && resolvedPath != inMemoryDatabasePath) {
      final f = File(resolvedPath);
      if (!f.parent.existsSync()) {
        f.parent.createSync(recursive: true);
      }
    }

    final db = await dbFactory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await _createSchema(db);
        },
      ),
    );

    await _createSchema(db);
    return ReplicationQueueRepository._(db);
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS replication_outbox (
        id TEXT PRIMARY KEY,
        object_hash TEXT NOT NULL,
        kind TEXT NOT NULL,
        payload_blob BLOB NOT NULL,
        status TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        max_retries INTEGER NOT NULL DEFAULT 5,
        next_retry_at INTEGER NOT NULL,
        last_error TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS replication_records (
        object_hash TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        status TEXT NOT NULL,
        replica_endpoints_json TEXT NOT NULL DEFAULT '[]',
        last_verified_at INTEGER,
        last_error TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      );
    ''');
  }

  Future<void> enqueue({
    required String objectHash,
    required String kind,
    required List<int> canonicalBytes,
    int maxRetries = 5,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final id = 'outbox:$objectHash';

    await _db.insert(
      'replication_outbox',
      {
        'id': id,
        'object_hash': objectHash,
        'kind': kind,
        'payload_blob': canonicalBytes,
        'status': ReplicationStatus.queued.name,
        'retry_count': 0,
        'max_retries': maxRetries,
        'next_retry_at': now,
        'last_error': null,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _db.insert(
      'replication_records',
      {
        'object_hash': objectHash,
        'kind': kind,
        'status': ReplicationStatus.queued.name,
        'replica_endpoints_json': '[]',
        'last_verified_at': null,
        'last_error': null,
        'retry_count': 0,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ReplicationOutboxItem>> getPendingItems({
    int limit = 20,
    bool forceImmediate = false,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final whereNextRetry = forceImmediate ? '' : 'AND next_retry_at <= ?';
    final args = forceImmediate ? <dynamic>[limit] : <dynamic>[now, limit];
    final rows = await _db.rawQuery(
      '''
      SELECT * FROM replication_outbox
      WHERE status IN ('queued', 'replicating', 'partiallyReplicated', 'degraded')
        $whereNextRetry
        AND retry_count < max_retries
      ORDER BY next_retry_at ASC
      LIMIT ?
      ''',
      args,
    );
    return rows.map(ReplicationOutboxItem.fromRow).toList();
  }

  Future<void> markCompleted(String id) async {
    await _db.delete('replication_outbox', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> recordRetryFailure({
    required String id,
    required int retryCount,
    required int maxRetries,
    required String error,
    required ReplicationStatus status,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final isPermanent = retryCount >= maxRetries;
    final nextStatus = isPermanent
        ? ReplicationStatus.failed
        : (status == ReplicationStatus.failed ? ReplicationStatus.queued : status);

    // Backoff exponencial: base 2s * 2^retryCount (máximo 1 hora)
    final delaySeconds = (2 * (1 << retryCount.clamp(0, 10))).clamp(1, 3600);
    final nextRetry = now + (delaySeconds * 1000);

    await _db.update(
      'replication_outbox',
      {
        'status': nextStatus.name,
        'retry_count': retryCount,
        'next_retry_at': nextRetry,
        'last_error': error,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> upsertRecord(ReplicationRecord record) async {
    await _db.insert(
      'replication_records',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ReplicationRecord?> getRecord(String objectHash) async {
    final rows = await _db.query(
      'replication_records',
      where: 'object_hash = ?',
      whereArgs: [objectHash],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ReplicationRecord.fromRow(rows.first);
  }

  Future<List<ReplicationRecord>> listRecords() async {
    final rows = await _db.query('replication_records', orderBy: 'updated_at DESC');
    return rows.map(ReplicationRecord.fromRow).toList();
  }

  Future<int> countPending() async {
    final res = await _db.rawQuery(
      "SELECT COUNT(*) as cnt FROM replication_outbox WHERE status NOT IN ('replicated', 'failed');",
    );
    return res.first['cnt'] as int? ?? 0;
  }

  Future<void> close() async {
    await _db.close();
  }
}

/// Exceção de barreira de privacidade: bloqueia qualquer tentativa de replicar dados privados.
class ReplicationPrivacyBarrierException implements Exception {
  final String message;
  const ReplicationPrivacyBarrierException(this.message);

  @override
  String toString() => 'ReplicationPrivacyBarrierException: $message';
}

/// Interface abstrata para adaptadores de armazenamento distribuído (S3 / IPFS).
abstract class ReplicationAdapter {
  String get name;
  String get endpoint;

  Future<bool> storeObject({
    required String hash,
    required List<int> bytes,
    Map<String, String> metadata = const {},
  });

  Future<Uint8List?> retrieveObject(String hash);

  Future<bool> verifyObjectExists(String hash);

  Future<bool> deleteObject(String hash);
}

/// Assinador AWS SigV4 puro Dart para S3, MinIO, Wasabi e Cloudflare R2.
class AwsSigV4Signer {
  final String accessKey;
  final String secretKey;
  final String region;
  final String service;

  const AwsSigV4Signer({
    required this.accessKey,
    required this.secretKey,
    this.region = 'us-east-1',
    this.service = 's3',
  });

  static List<int> _hmacSha256(List<int> key, List<int> data) {
    return std_crypto.Hmac(std_crypto.sha256, key).convert(data).bytes;
  }

  static String _hexSha256(List<int> data) {
    return std_crypto.sha256.convert(data).toString().toLowerCase();
  }

  Map<String, String> sign({
    required String method,
    required Uri uri,
    required List<int> body,
    DateTime? timestamp,
  }) {
    final now = (timestamp ?? DateTime.now()).toUtc();
    final dateOnly =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final dateIso8601 =
        '$dateOnly'
        'T${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}Z';

    final payloadHash = _hexSha256(body);
    final host = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;

    final canonicalHeaders =
        'host:$host\n'
        'x-amz-content-sha256:$payloadHash\n'
        'x-amz-date:$dateIso8601\n';
    const signedHeaders = 'host;x-amz-content-sha256;x-amz-date';

    final path = uri.path.isEmpty ? '/' : uri.path;
    final canonicalRequest =
        '$method\n'
        '$path\n'
        '${uri.query}\n'
        '$canonicalHeaders\n'
        '$signedHeaders\n'
        '$payloadHash';

    final scope = '$dateOnly/$region/$service/aws4_request';
    final stringToSign =
        'AWS4-HMAC-SHA256\n'
        '$dateIso8601\n'
        '$scope\n'
        '${_hexSha256(utf8.encode(canonicalRequest))}';

    final kDate = _hmacSha256(utf8.encode('AWS4$secretKey'), utf8.encode(dateOnly));
    final kRegion = _hmacSha256(kDate, utf8.encode(region));
    final kService = _hmacSha256(kRegion, utf8.encode(service));
    final kSigning = _hmacSha256(kService, utf8.encode('aws4_request'));
    final signature = std_crypto.Hmac(std_crypto.sha256, kSigning)
        .convert(utf8.encode(stringToSign))
        .toString();

    final authorization =
        'AWS4-HMAC-SHA256 Credential=$accessKey/$scope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';

    return {
      'Host': host,
      'x-amz-date': dateIso8601,
      'x-amz-content-sha256': payloadHash,
      'Authorization': authorization,
    };
  }
}

/// Adaptador S3 real com suporte a AWS SigV4, TLS obrigatório e fallback defensivo para mock.
class S3ReplicationAdapter implements ReplicationAdapter {
  @override
  final String name;
  @override
  final String endpoint;
  final String? bucket;
  final String? accessKey;
  final String? secretKey;
  final String region;
  final bool requireTls;
  final Duration timeout;
  final HttpClient? customHttpClient;
  final Map<String, List<int>> _mockStorage = {};
  bool isOnline = true;

  S3ReplicationAdapter({
    this.name = 's3_minio',
    required this.endpoint,
    this.bucket,
    this.accessKey,
    this.secretKey,
    this.region = 'us-east-1',
    this.requireTls = true,
    this.timeout = const Duration(seconds: 30),
    this.customHttpClient,
  });

  bool get isRealHttp => accessKey != null && secretKey != null;

  Uri _buildObjectUri(String hash) {
    final cleanEndpoint = endpoint.endsWith('/')
        ? endpoint.substring(0, endpoint.length - 1)
        : endpoint;
    if (bucket != null && bucket!.isNotEmpty && !cleanEndpoint.endsWith('/$bucket')) {
      return Uri.parse('$cleanEndpoint/$bucket/$hash');
    }
    return Uri.parse('$cleanEndpoint/$hash');
  }

  void _assertTlsPolicy(Uri uri) {
    if (!requireTls) return;
    final host = uri.host.toLowerCase();
    final isLoopback = host == '127.0.0.1' || host == 'localhost' || host == '::1';
    if (!isLoopback && uri.scheme != 'https') {
      throw const SocketException(
        '[Segurança S3] TLS obrigatório para replicação em nós remotos.',
      );
    }
  }

  @override
  Future<bool> storeObject({
    required String hash,
    required List<int> bytes,
    Map<String, String> metadata = const {},
  }) async {
    if (!isOnline) return false;

    final actualHash = std_crypto.sha256.convert(bytes).toString().toLowerCase();
    if (actualHash != hash.toLowerCase()) {
      return false; // Rejeição de integridade
    }

    if (!isRealHttp) {
      _mockStorage[hash.toLowerCase()] = List<int>.from(bytes);
      return true;
    }

    final uri = _buildObjectUri(hash);
    _assertTlsPolicy(uri);

    final signer = AwsSigV4Signer(
      accessKey: accessKey!,
      secretKey: secretKey!,
      region: region,
      service: 's3',
    );

    final headers = signer.sign(
      method: 'PUT',
      uri: uri,
      body: bytes,
    );

    final client = customHttpClient ?? HttpClient();
    try {
      final req = await client.openUrl('PUT', uri).timeout(timeout);
      headers.forEach(req.headers.set);
      metadata.forEach((k, v) => req.headers.set('x-amz-meta-$k', v));
      req.add(bytes);

      final res = await req.close().timeout(timeout);
      await res.drain<void>();
      return res.statusCode == 200 || res.statusCode == 201 || res.statusCode == 204;
    } catch (_) {
      return false;
    } finally {
      if (customHttpClient == null) client.close();
    }
  }

  @override
  Future<Uint8List?> retrieveObject(String hash) async {
    if (!isOnline) return null;

    if (!isRealHttp) {
      final data = _mockStorage[hash.toLowerCase()];
      return data != null ? Uint8List.fromList(data) : null;
    }

    final uri = _buildObjectUri(hash);
    _assertTlsPolicy(uri);

    final signer = AwsSigV4Signer(
      accessKey: accessKey!,
      secretKey: secretKey!,
      region: region,
      service: 's3',
    );

    final headers = signer.sign(
      method: 'GET',
      uri: uri,
      body: const [],
    );

    final client = customHttpClient ?? HttpClient();
    try {
      final req = await client.openUrl('GET', uri).timeout(timeout);
      headers.forEach(req.headers.set);
      final res = await req.close().timeout(timeout);

      if (res.statusCode == 200) {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in res) {
          builder.add(chunk);
        }
        final bytes = builder.takeBytes();
        final actual = std_crypto.sha256.convert(bytes).toString().toLowerCase();
        if (actual == hash.toLowerCase()) {
          return bytes;
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      if (customHttpClient == null) client.close();
    }
  }

  @override
  Future<bool> verifyObjectExists(String hash) async {
    if (!isOnline) return false;

    if (!isRealHttp) {
      return _mockStorage.containsKey(hash.toLowerCase());
    }

    final uri = _buildObjectUri(hash);
    _assertTlsPolicy(uri);

    final signer = AwsSigV4Signer(
      accessKey: accessKey!,
      secretKey: secretKey!,
      region: region,
      service: 's3',
    );

    final headers = signer.sign(
      method: 'HEAD',
      uri: uri,
      body: const [],
    );

    final client = customHttpClient ?? HttpClient();
    try {
      final req = await client.openUrl('HEAD', uri).timeout(timeout);
      headers.forEach(req.headers.set);
      final res = await req.close().timeout(timeout);
      await res.drain<void>();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      if (customHttpClient == null) client.close();
    }
  }

  @override
  Future<bool> deleteObject(String hash) async {
    if (!isOnline) return false;

    if (!isRealHttp) {
      _mockStorage.remove(hash.toLowerCase());
      return true;
    }

    final uri = _buildObjectUri(hash);
    _assertTlsPolicy(uri);

    final signer = AwsSigV4Signer(
      accessKey: accessKey!,
      secretKey: secretKey!,
      region: region,
      service: 's3',
    );

    final headers = signer.sign(
      method: 'DELETE',
      uri: uri,
      body: const [],
    );

    final client = customHttpClient ?? HttpClient();
    try {
      final req = await client.openUrl('DELETE', uri).timeout(timeout);
      headers.forEach(req.headers.set);
      final res = await req.close().timeout(timeout);
      await res.drain<void>();
      return res.statusCode == 200 || res.statusCode == 204 || res.statusCode == 404;
    } catch (_) {
      return false;
    } finally {
      if (customHttpClient == null) client.close();
    }
  }
}

/// Cálculo determinístico de CIDv1 (base32) para IPFS Kubo sem dependências externas.
class IpfsCidV1 {
  static const String base32Alphabet = 'abcdefghijklmnopqrstuvwxyz234567';

  static String computeCidV1Raw(List<int> sha256Bytes) {
    if (sha256Bytes.length != 32) {
      throw ArgumentError('SHA-256 deve conter exatamente 32 bytes.');
    }
    // 0x01: CIDv1, 0x55: raw codec, 0x12: sha2-256, 0x20: 32 bytes
    final multihash = <int>[0x01, 0x55, 0x12, 0x20, ...sha256Bytes];
    return 'b${_base32Encode(multihash)}';
  }

  static String _base32Encode(List<int> bytes) {
    var buffer = 0;
    var bitsLeft = 0;
    final sb = StringBuffer();
    for (final b in bytes) {
      buffer = (buffer << 8) | (b & 0xff);
      bitsLeft += 8;
      while (bitsLeft >= 5) {
        bitsLeft -= 5;
        final index = (buffer >> bitsLeft) & 0x1f;
        sb.write(base32Alphabet[index]);
      }
    }
    if (bitsLeft > 0) {
      final index = (buffer << (5 - bitsLeft)) & 0x1f;
      sb.write(base32Alphabet[index]);
    }
    return sb.toString();
  }
}

/// Adaptador IPFS real para nós Kubo (`/api/v0/add`, `/api/v0/cat`, `/api/v0/pin/ls`, `/api/v0/pin/rm`).
class IpfsReplicationAdapter implements ReplicationAdapter {
  @override
  final String name;
  @override
  final String endpoint;
  final bool isRealHttp;
  final Duration timeout;
  final HttpClient? customHttpClient;
  final Map<String, List<int>> _mockStorage = {};
  final Map<String, String> _hashToCid = {};
  bool isOnline = true;

  IpfsReplicationAdapter({
    this.name = 'ipfs_kubo',
    required this.endpoint,
    this.isRealHttp = false,
    this.timeout = const Duration(seconds: 30),
    this.customHttpClient,
  });

  String getCidForHash(String hash) {
    return _hashToCid[hash.toLowerCase()] ??
        IpfsCidV1.computeCidV1Raw(
          Uint8List.fromList(
            List.generate(32, (i) => int.parse(hash.substring(i * 2, i * 2 + 2), radix: 16)),
          ),
        );
  }

  @override
  Future<bool> storeObject({
    required String hash,
    required List<int> bytes,
    Map<String, String> metadata = const {},
  }) async {
    if (!isOnline) return false;

    final actualHash = std_crypto.sha256.convert(bytes).toString().toLowerCase();
    if (actualHash != hash.toLowerCase()) {
      return false;
    }

    final cid = IpfsCidV1.computeCidV1Raw(
      std_crypto.sha256.convert(bytes).bytes,
    );
    _hashToCid[hash.toLowerCase()] = cid;

    if (!isRealHttp) {
      _mockStorage[hash.toLowerCase()] = List<int>.from(bytes);
      return true;
    }

    final cleanEndpoint = endpoint.endsWith('/') ? endpoint.substring(0, endpoint.length - 1) : endpoint;
    final addUri = Uri.parse('$cleanEndpoint/api/v0/add?pin=true&cid-version=1');

    final client = customHttpClient ?? HttpClient();
    try {
      const boundary = '----NixIpfsBoundary7MA4YWxkTrZu0gW';
      final req = await client.openUrl('POST', addUri).timeout(timeout);
      req.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');

      final bodyBuilder = BytesBuilder(copy: false);
      bodyBuilder.add(utf8.encode('--$boundary\r\n'));
      bodyBuilder.add(utf8.encode('Content-Disposition: form-data; name="file"; filename="$hash"\r\n'));
      bodyBuilder.add(utf8.encode('Content-Type: application/octet-stream\r\n\r\n'));
      bodyBuilder.add(bytes);
      bodyBuilder.add(utf8.encode('\r\n--$boundary--\r\n'));

      final payload = bodyBuilder.takeBytes();
      req.contentLength = payload.length;
      req.add(payload);

      final res = await req.close().timeout(timeout);
      final resBody = await utf8.decodeStream(res);

      if (res.statusCode == 200) {
        try {
          final json = jsonDecode(resBody) as Map<String, dynamic>;
          if (json.containsKey('Hash')) {
            _hashToCid[hash.toLowerCase()] = json['Hash'] as String;
          }
        } catch (_) {}
        return true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      if (customHttpClient == null) client.close();
    }
  }

  @override
  Future<Uint8List?> retrieveObject(String hash) async {
    if (!isOnline) return null;

    if (!isRealHttp) {
      final data = _mockStorage[hash.toLowerCase()];
      return data != null ? Uint8List.fromList(data) : null;
    }

    final cid = getCidForHash(hash);
    final cleanEndpoint = endpoint.endsWith('/') ? endpoint.substring(0, endpoint.length - 1) : endpoint;
    final catUri = Uri.parse('$cleanEndpoint/api/v0/cat?arg=$cid');

    final client = customHttpClient ?? HttpClient();
    try {
      final req = await client.openUrl('POST', catUri).timeout(timeout);
      final res = await req.close().timeout(timeout);

      if (res.statusCode == 200) {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in res) {
          builder.add(chunk);
        }
        final bytes = builder.takeBytes();
        final actual = std_crypto.sha256.convert(bytes).toString().toLowerCase();
        if (actual == hash.toLowerCase()) {
          return bytes;
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      if (customHttpClient == null) client.close();
    }
  }

  @override
  Future<bool> verifyObjectExists(String hash) async {
    if (!isOnline) return false;

    if (!isRealHttp) {
      return _mockStorage.containsKey(hash.toLowerCase());
    }

    final cid = getCidForHash(hash);
    final cleanEndpoint = endpoint.endsWith('/') ? endpoint.substring(0, endpoint.length - 1) : endpoint;
    final pinLsUri = Uri.parse('$cleanEndpoint/api/v0/pin/ls?arg=$cid&type=recursive');

    final client = customHttpClient ?? HttpClient();
    try {
      final req = await client.openUrl('POST', pinLsUri).timeout(timeout);
      final res = await req.close().timeout(timeout);
      final body = await utf8.decodeStream(res);
      return res.statusCode == 200 && body.contains(cid);
    } catch (_) {
      return false;
    } finally {
      if (customHttpClient == null) client.close();
    }
  }

  @override
  Future<bool> deleteObject(String hash) async {
    if (!isOnline) return false;

    if (!isRealHttp) {
      _mockStorage.remove(hash.toLowerCase());
      return true;
    }

    final cid = getCidForHash(hash);
    final cleanEndpoint = endpoint.endsWith('/') ? endpoint.substring(0, endpoint.length - 1) : endpoint;
    final pinRmUri = Uri.parse('$cleanEndpoint/api/v0/pin/rm?arg=$cid');

    final client = customHttpClient ?? HttpClient();
    try {
      final req = await client.openUrl('POST', pinRmUri).timeout(timeout);
      final res = await req.close().timeout(timeout);
      await res.drain<void>();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      if (customHttpClient == null) client.close();
    }
  }
}

/// Coordenador de replicação distribuída com barreira estrita de privacidade,
/// persistência SQLite (Outbox Pattern) e tolerância a falhas.
class NixReplicationCoordinator {
  final List<ReplicationAdapter> _adapters;
  final Map<String, ReplicationRecord> _inMemoryRecords = {};
  final ReplicationQueueRepository? queueRepo;

  static const Set<String> allowedReplicationKinds = {
    'article',
    'catalog_package',
    'public_refutation',
  };

  NixReplicationCoordinator({
    List<ReplicationAdapter> adapters = const [],
    this.queueRepo,
  }) : _adapters = List.from(adapters);

  List<ReplicationAdapter> get adapters => List.unmodifiable(_adapters);
  Map<String, ReplicationRecord> get records => Map.unmodifiable(_inMemoryRecords);

  void addAdapter(ReplicationAdapter adapter) {
    _adapters.add(adapter);
  }

  /// Replicar objeto público para a malha S3 / IPFS com barreira de privacidade e outbox SQLite.
  Future<ReplicationRecord> replicatePublicObject({
    required String objectHash,
    required String kind,
    required List<int> canonicalBytes,
    int maxRetries = 5,
  }) async {
    // 1. Barreira de Privacidade
    if (!allowedReplicationKinds.contains(kind)) {
      throw ReplicationPrivacyBarrierException(
        '[Fail-Closed] O tipo "$kind" não tem permissão para replicação distribuída. Apenas objetos públicos canônicos são replicáveis.',
      );
    }

    // 2. Validação estrita de integridade SHA-256
    final computedSha = std_crypto.sha256.convert(canonicalBytes).toString().toLowerCase();
    if (computedSha != objectHash.toLowerCase()) {
      throw const FormatException(
        '[Integrity] Divergência entre hash informado e SHA-256 real dos bytes.',
      );
    }

    // 3. Persistência na fila outbox SQLite (se disponível)
    if (queueRepo != null) {
      await queueRepo!.enqueue(
        objectHash: objectHash,
        kind: kind,
        canonicalBytes: canonicalBytes,
        maxRetries: maxRetries,
      );
    }

    // 4. Executa replicação imediata nos adaptadores configurados
    return _dispatchReplication(
      objectHash: objectHash,
      kind: kind,
      canonicalBytes: canonicalBytes,
      retryCount: 0,
      maxRetries: maxRetries,
    );
  }

  Future<ReplicationRecord> _dispatchReplication({
    required String objectHash,
    required String kind,
    required List<int> canonicalBytes,
    required int retryCount,
    int maxRetries = 5,
  }) async {
    var record = ReplicationRecord(
      objectHash: objectHash,
      kind: kind,
      status: ReplicationStatus.replicating,
      retryCount: retryCount,
    );
    _inMemoryRecords[objectHash] = record;

    if (_adapters.isEmpty) {
      record = record.copyWith(
        status: ReplicationStatus.localOnly,
        lastError: 'Nenhum adaptador de replicação configurado.',
      );
      _inMemoryRecords[objectHash] = record;
      if (queueRepo != null) await queueRepo!.upsertRecord(record);
      return record;
    }

    final successfulEndpoints = <String>[];
    String? lastError;

    for (final adapter in _adapters) {
      try {
        final ok = await adapter.storeObject(
          hash: objectHash,
          bytes: canonicalBytes,
        );
        if (ok) {
          successfulEndpoints.add(adapter.endpoint);
        } else {
          lastError = 'Adaptador ${adapter.name} (${adapter.endpoint}) falhou ao armazenar.';
        }
      } catch (e) {
        lastError = 'Exceção no adaptador ${adapter.name}: $e';
      }
    }

    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    ReplicationStatus finalStatus;

    if (successfulEndpoints.isEmpty) {
      finalStatus = ReplicationStatus.failed;
    } else if (successfulEndpoints.length == _adapters.length) {
      finalStatus = ReplicationStatus.replicated;
    } else {
      finalStatus = successfulEndpoints.length >= (_adapters.length / 2).ceil()
          ? ReplicationStatus.partiallyReplicated
          : ReplicationStatus.degraded;
    }

    record = record.copyWith(
      status: finalStatus,
      replicaEndpoints: successfulEndpoints,
      lastVerifiedAt: now,
      lastError: lastError,
    );
    _inMemoryRecords[objectHash] = record;

    if (queueRepo != null) {
      await queueRepo!.upsertRecord(record);
      final outboxId = 'outbox:$objectHash';
      if (finalStatus == ReplicationStatus.replicated) {
        await queueRepo!.markCompleted(outboxId);
      } else {
        await queueRepo!.recordRetryFailure(
          id: outboxId,
          retryCount: retryCount + 1,
          maxRetries: maxRetries,
          error: lastError ?? 'Replicação incompleta',
          status: finalStatus,
        );
      }
    }

    return record;
  }

  /// Processa a fila persistente de replicação (Outbox Pattern) com retentativas.
  Future<int> processOutbox({bool forceImmediate = false}) async {
    if (queueRepo == null) return 0;

    final pending = await queueRepo!.getPendingItems(forceImmediate: forceImmediate);
    int processed = 0;

    for (final item in pending) {
      await _dispatchReplication(
        objectHash: item.objectHash,
        kind: item.kind,
        canonicalBytes: item.payloadBytes,
        retryCount: item.retryCount,
        maxRetries: item.maxRetries,
      );
      processed++;
    }

    return processed;
  }

  /// Recupera e reinicia o processamento da fila após reinício do app.
  Future<int> recoverAndProcessQueue({bool forceImmediate = true}) async {
    return processOutbox(forceImmediate: forceImmediate);
  }

  /// Recupera objeto de réplica distribuída verificando integridade de forma estrita.
  Future<Uint8List?> fetchVerifiedObject(String objectHash) async {
    for (final adapter in _adapters) {
      try {
        final bytes = await adapter.retrieveObject(objectHash);
        if (bytes != null) {
          final actualSha = std_crypto.sha256.convert(bytes).toString().toLowerCase();
          if (actualSha == objectHash.toLowerCase()) {
            return bytes; // Integridade confirmada
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Verifica status de réplica e atualiza integridade.
  Future<ReplicationRecord?> checkReplicationHealth(String objectHash) async {
    final existing = queueRepo != null
        ? await queueRepo!.getRecord(objectHash) ?? _inMemoryRecords[objectHash]
        : _inMemoryRecords[objectHash];

    if (existing == null) return null;

    final activeEndpoints = <String>[];
    for (final adapter in _adapters) {
      try {
        final exists = await adapter.verifyObjectExists(objectHash);
        if (exists) {
          activeEndpoints.add(adapter.endpoint);
        }
      } catch (_) {}
    }

    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    ReplicationStatus status;

    if (activeEndpoints.isEmpty) {
      status = ReplicationStatus.failed;
    } else if (activeEndpoints.length == _adapters.length) {
      status = ReplicationStatus.replicated;
    } else {
      status = ReplicationStatus.degraded;
    }

    final updated = existing.copyWith(
      status: status,
      replicaEndpoints: activeEndpoints,
      lastVerifiedAt: now,
    );
    _inMemoryRecords[objectHash] = updated;
    if (queueRepo != null) {
      await queueRepo!.upsertRecord(updated);
    }
    return updated;
  }
}
