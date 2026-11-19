import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import '../database/repositories.dart';
import 'catalog_database.dart';

/// Modos de privacidade para operação do Nix Media Index.
enum MediaPrivacyMode {
  /// 100% Offline: busca unificada estritamente no catálogo SQLite FTS5 local, sem tráfego de rede.
  offlineStrict,

  /// Atualizações privadas: busca local + atualização periódica de pacotes assinados `.nixpack` via Tor Onion v3.
  privateTorUpdates,

  /// Conectores externos opt-in: sob demanda, com consentimento prévio e gate Tor obrigatório.
  optInExternalSearch,
}

/// Exceção fail-closed ao tentar resolver tracker/DHT BitTorrent em claro quando Tor estrito está ativo (Fase 8).
class TorrentClearnetLeakBlockedException implements Exception {
  final String message;
  const TorrentClearnetLeakBlockedException(this.message);

  @override
  String toString() => 'TorrentClearnetLeakBlockedException: $message';
}

/// Estágios formalmente diferenciados do catálogo de mídia:
/// - `localCatalogSearch`: busca estritamente local no SQLite/FTS5 (zero rede).
/// - `remoteOptInQuery`: consulta remota a conector externo opt-in (sujeita à política de transporte Tor/SOCKS5).
/// - `sandboxFileTransfer`: transferência/resolução de arquivos em sandbox isolado da identidade Seed A.
enum MediaOperationStage {
  localCatalogSearch,
  remoteOptInQuery,
  sandboxFileTransfer,
}

/// Conectores externos estritamente opt-in (desabilitados por padrão).
enum OptInMediaConnectorKind {
  tmdb,
  anilist,
  jellyfin,
}

/// Fases formalmente desacopladas do catálogo Nix Media:
/// 1) Descoberta offline/catálogo (`OfflineCatalogLookup` / `MediaOperationStage.localCatalogSearch`)
/// 2) Consulta remota opt-in (`OptInMediaConnectorKind` / `MediaOperationStage.remoteOptInQuery`)
/// 3) Gate de resolução magnet e transferência em sandbox (`MediaOperationStage.sandboxFileTransfer`)
class MediaCatalogService {
  final MediaRepository mediaRepo;
  final CatalogRepository? catalogRepo;
  MediaPrivacyMode _privacyMode = MediaPrivacyMode.offlineStrict;

  final Map<OptInMediaConnectorKind, bool> _enabledConnectors = {
    for (final k in OptInMediaConnectorKind.values) k: false,
  };

  MediaCatalogService(this.mediaRepo, {this.catalogRepo});

  MediaPrivacyMode get privacyMode => _privacyMode;

  void setPrivacyMode(MediaPrivacyMode mode) {
    _privacyMode = mode;
  }

  bool isConnectorEnabled(OptInMediaConnectorKind kind) =>
      _enabledConnectors[kind] ?? false;

  void setConnectorEnabled(OptInMediaConnectorKind kind, bool enabled) {
    _enabledConnectors[kind] = enabled;
  }

  /// Busca offline de obras no catálogo cultural público (`CatalogRepository` via FTS5).
  /// Garante ZERO emissão de requisições à rede durante a busca.
  Future<List<CatalogWork>> searchCatalog({
    required String query,
    String? kind,
    String? genre,
    int? releaseYear,
    int limit = 50,
    int offset = 0,
  }) async {
    if (catalogRepo == null) return const [];
    return catalogRepo!.search(
      query: query,
      kind: kind,
      genre: genre,
      releaseYear: releaseYear,
      limit: limit,
      offset: offset,
    );
  }

  /// Lista obras do catálogo com filtros opcionais.
  Future<List<CatalogWork>> listCatalogWorks({
    String? kind,
    String? genre,
    int? releaseYear,
    int limit = 50,
    int offset = 0,
  }) async {
    if (catalogRepo == null) return const [];
    return catalogRepo!.listWorks(
      kind: kind,
      genre: genre,
      releaseYear: releaseYear,
      limit: limit,
      offset: offset,
    );
  }

  /// Recupera detalhes de uma obra específica no catálogo público offline.
  Future<CatalogWork?> getCatalogWork(String id) async {
    if (catalogRepo == null) return null;
    return catalogRepo!.getWork(id);
  }

  /// Salva uma obra no Acervo Cultural pessoal do usuário (`nix_local_v4.db` em SQLCipher).
  ///
  /// Privacidade:
  /// - Status de consumo, nota e anotações pessoais são protegidos com cifragem local.
  /// - NENHUM dado do acervo pessoal é enviado à rede.
  Future<void> saveToAcervo({
    required String identityId,
    required CatalogWork work,
    String status = 'want_to_watch',
    int? rating,
    String? privateNotes,
  }) async {
    final normalizedKind = (work.kind == 'movie') ? 'film' : work.kind;
    await mediaRepo.upsertMediaItem(
      id: work.id,
      kind: normalizedKind,
      title: work.title,
      metadata: {
        'original_title': work.originalTitle,
        'creators': work.creators,
        'genres': work.genres,
        'release_year': work.releaseYear,
        'summary': work.summary,
        'cover_thumb': work.coverThumb,
        'external_ids': work.externalIds,
        if (privateNotes != null) 'private_notes': privateNotes,
      },
      source: 'nix_catalog',
      sourceId: work.id,
    );

    await mediaRepo.upsertLibraryEntry(
      identityId: identityId,
      mediaId: work.id,
      status: status,
      progress: {
        if (privateNotes != null) 'notes': privateNotes,
        'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      rating: rating,
    );
  }

  /// Lista os itens do acervo pessoal do usuário no SQLCipher.
  Future<List<Map<String, dynamic>>> listUserAcervo(String identityId) {
    return mediaRepo.listLibraryEntries(identityId);
  }

  /// Remove item do acervo pessoal do usuário.
  Future<void> removeFromAcervo({
    required String identityId,
    required String workId,
  }) async {
    await mediaRepo.deleteLibraryEntry(identityId: identityId, mediaId: workId);
  }

  /// Fase 1 (Offline / Catálogo): Indexa metadados e instantâneo em `media_items` + FTS5 sem rede P2P.
  Future<String> computeCatalogSnapshotHash(List<Map<String, dynamic>> items) async {
    final canonical = utf8.encode(jsonEncode(items));
    return std_crypto.sha256.convert(canonical).toString();
  }

  Future<void> saveOfflineCatalogEntry({
    required String id,
    required String kind,
    required String title,
    Map<String, dynamic> metadata = const {},
    String source = 'starwire_offline',
  }) async {
    await mediaRepo.upsertMediaItem(
      id: id,
      kind: kind,
      title: title,
      metadata: {
        ...metadata,
        'stage': MediaOperationStage.localCatalogSearch.name,
      },
      source: source,
      sourceId: id,
    );
  }

  /// Busca estritamente local no catálogo SQLite/FTS5 (`MediaOperationStage.localCatalogSearch`).
  Future<List<Map<String, dynamic>>> searchOfflineCatalog(String query) {
    return mediaRepo.searchMedia(query);
  }

  /// Consulta conector externo opt-in (`MediaOperationStage.remoteOptInQuery`).
  /// - Exige que o conector esteja explicitamente habilitado pelo usuário.
  /// - Respeita política fail-closed: quando `isFailClosedTorActive` é verdadeiro,
  ///   rejeita a consulta se `hasActiveTorSocksCircuit` for falso.
  Future<List<Map<String, dynamic>>> queryRemoteOptInConnector({
    required OptInMediaConnectorKind connector,
    required String query,
    required bool isFailClosedTorActive,
    required bool hasActiveTorSocksCircuit,
    Future<List<Map<String, dynamic>>> Function(String query)? transportExecutor,
  }) async {
    if (!isConnectorEnabled(connector)) {
      throw StateError(
        '[Opt-In] Conector externo ${connector.name} está desabilitado por padrão.',
      );
    }
    if (isFailClosedTorActive && !hasActiveTorSocksCircuit) {
      throw const TorrentClearnetLeakBlockedException(
        '[Fail-Closed] Consulta remota a conector externo bloqueada sem circuito Tor SOCKS5 ativo.',
      );
    }
    final q = query.trim();
    if (q.isEmpty) return const [];
    final results = transportExecutor != null
        ? await transportExecutor(q)
        : <Map<String, dynamic>>[];
    for (final item in results) {
      final id = (item['id'] as String?) ??
          '${connector.name}_${std_crypto.sha256.convert(utf8.encode(q)).toString().substring(0, 10)}';
      final kind = (item['kind'] as String?) ?? 'movie';
      final title = (item['title'] as String?) ?? q;
      await mediaRepo.upsertMediaItem(
        id: id,
        kind: kind,
        title: title,
        metadata: {
          ...item,
          'stage': MediaOperationStage.remoteOptInQuery.name,
          'connector': connector.name,
        },
        source: 'optin_${connector.name}',
        sourceId: id,
      );
    }
    return results;
  }

  /// Fase 3 (Resolução Magnet / Transferência): Bloqueia DHT UDP e trackers clearnet por padrão sob Tor fail-closed.
  /// Exige opt-in explícito de transporte isolado (I2P SAM ou VPN/BitTorrent dedicado sem vazar Tor Exit/real IP).
  static String authorizeMagnetResolution({
    required String magnetUri,
    required bool isFailClosedTorActive,
    required bool explicitIsolatedTorrentOptIn,
    required bool disableUdpDhtAndLsd,
  }) {
    final trimmed = magnetUri.trim();
    if (!trimmed.startsWith('magnet:?xt=urn:btih:')) {
      throw const FormatException('Magnet URI inválido.');
    }
    if (isFailClosedTorActive && !explicitIsolatedTorrentOptIn) {
      throw const TorrentClearnetLeakBlockedException(
        '[Fail-Closed] Resolução de magnet bloqueada no modo Tor estrito: confirme opt-in isolado (I2P/VPN dedicada) para evitar vazamento UDP/IP real.',
      );
    }
    if (!disableUdpDhtAndLsd) {
      throw const TorrentClearnetLeakBlockedException(
        '[Fail-Closed] DHT/LSD via UDP deve estar desativado na resolução privada de peers.',
      );
    }
    // Extrai apenas infohash hex/base32 ignorando trackers clearnet embutidos caso strict mode
    final xtMatch = RegExp(r'urn:btih:([a-zA-Z0-9]{32,40})').firstMatch(trimmed);
    if (xtMatch == null) {
      throw const FormatException('Infohash BTIH ausente ou malformado.');
    }
    return xtMatch.group(1)!.toLowerCase();
  }
}

/// Estado explícito da fase de transferência sandboxed (Fase 8), desacoplado da Seed A.
class MediaTransferSandboxRecord {
  final String infoHash;
  final String sandboxPath;
  final bool usesIdentityKeys = false;
  final int downloadedBytes;
  final int totalBytes;

  const MediaTransferSandboxRecord({
    required this.infoHash,
    required this.sandboxPath,
    required this.downloadedBytes,
    required this.totalBytes,
  });

  Uint8List verifyDigest(List<int> content) =>
      Uint8List.fromList(std_crypto.sha256.convert(content).bytes);
}
