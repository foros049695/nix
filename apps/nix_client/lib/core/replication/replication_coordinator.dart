import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;

/// Estados formais da máquina de estados de replicação distribuída (Fase 20).
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
  final String kind; // 'article', 'catalog_package'
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
}

/// Adaptador simulado ou HTTP real para S3 / MinIO.
class S3ReplicationAdapter implements ReplicationAdapter {
  @override
  final String name;
  @override
  final String endpoint;
  final Map<String, List<int>> _storage = {};
  bool isOnline = true;

  S3ReplicationAdapter({
    this.name = 's3_minio',
    required this.endpoint,
  });

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
    _storage[hash.toLowerCase()] = List<int>.from(bytes);
    return true;
  }

  @override
  Future<Uint8List?> retrieveObject(String hash) async {
    if (!isOnline) return null;
    final data = _storage[hash.toLowerCase()];
    return data != null ? Uint8List.fromList(data) : null;
  }

  @override
  Future<bool> verifyObjectExists(String hash) async {
    if (!isOnline) return false;
    return _storage.containsKey(hash.toLowerCase());
  }
}

/// Adaptador simulado ou HTTP RPC para IPFS Kubo (`/api/v0/add`, `/api/v0/cat`).
class IpfsReplicationAdapter implements ReplicationAdapter {
  @override
  final String name;
  @override
  final String endpoint;
  final Map<String, List<int>> _storage = {};
  bool isOnline = true;

  IpfsReplicationAdapter({
    this.name = 'ipfs_kubo',
    required this.endpoint,
  });

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
    _storage[hash.toLowerCase()] = List<int>.from(bytes);
    return true;
  }

  @override
  Future<Uint8List?> retrieveObject(String hash) async {
    if (!isOnline) return null;
    final data = _storage[hash.toLowerCase()];
    return data != null ? Uint8List.fromList(data) : null;
  }

  @override
  Future<bool> verifyObjectExists(String hash) async {
    if (!isOnline) return false;
    return _storage.containsKey(hash.toLowerCase());
  }
}

/// Coordenador de replicação distribuída com barreira estrita de privacidade e tolerância a falhas.
class NixReplicationCoordinator {
  final List<ReplicationAdapter> _adapters;
  final Map<String, ReplicationRecord> _records = {};

  static const Set<String> allowedReplicationKinds = {
    'article',
    'catalog_package',
    'public_refutation',
  };

  NixReplicationCoordinator({
    List<ReplicationAdapter> adapters = const [],
  }) : _adapters = List.from(adapters);

  List<ReplicationAdapter> get adapters => List.unmodifiable(_adapters);
  Map<String, ReplicationRecord> get records => Map.unmodifiable(_records);

  void addAdapter(ReplicationAdapter adapter) {
    _adapters.add(adapter);
  }

  /// Replicar objeto público para a malha S3 / IPFS.
  ///
  /// Política de privacidade:
  /// - Apenas objetos com kind em [allowedReplicationKinds] são permitidos.
  /// - Rascunhos ('draft'), chaves privadas e dados locais são TERMINANTEMENTE bloqueados.
  /// - Verifica SHA-256 dos bytes contra [objectHash] antes de qualquer transmissão.
  Future<ReplicationRecord> replicatePublicObject({
    required String objectHash,
    required String kind,
    required List<int> canonicalBytes,
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

    // 3. Atualiza estado para REPLICATING
    var record = ReplicationRecord(
      objectHash: objectHash,
      kind: kind,
      status: ReplicationStatus.replicating,
    );
    _records[objectHash] = record;

    if (_adapters.isEmpty) {
      record = record.copyWith(
        status: ReplicationStatus.localOnly,
        lastError: 'Nenhum adaptador de replicação configurado.',
      );
      _records[objectHash] = record;
      return record;
    }

    final successfulEndpoints = <String>[];
    String? lastError;

    // 4. Dispara réplicas em paralelo nos adaptadores
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

    // 5. Determinação da máquina de estados
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    ReplicationStatus finalStatus;

    if (successfulEndpoints.isEmpty) {
      finalStatus = ReplicationStatus.failed;
    } else if (successfulEndpoints.length == _adapters.length) {
      finalStatus = ReplicationStatus.replicated;
    } else {
      // Replicado em parte dos nós configurados: parcialmente replicado / degradado
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
    _records[objectHash] = record;
    return record;
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
    final existing = _records[objectHash];
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
    _records[objectHash] = updated;
    return updated;
  }
}
