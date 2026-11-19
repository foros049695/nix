import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as std_crypto;
import '../database/repositories.dart';

/// Exceção fail-closed ao tentar resolver tracker/DHT BitTorrent em claro quando Tor estrito está ativo (Fase 8).
class TorrentClearnetLeakBlockedException implements Exception {
  final String message;
  const TorrentClearnetLeakBlockedException(this.message);

  @override
  String toString() => 'TorrentClearnetLeakBlockedException: $message';
}

/// Fases formalmente desacopladas do catálogo Nix Media (Fase 8):
/// 1) Descoberta offline/catálogo (`OfflineCatalogLookup`)
/// 2) Gate de resolução magnet com isolamento explícito (`MagnetResolutionPolicy`)
/// 3) Registro isolado de progresso/transferência em sandbox (`MediaTransferSandbox`)
class MediaCatalogService {
  final MediaRepository mediaRepo;
  MediaCatalogService(this.mediaRepo);

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
  }) async {
    await mediaRepo.upsertMediaItem(
      id: id,
      kind: kind,
      title: title,
      metadata: metadata,
      source: 'starwire_offline',
      sourceId: id,
    );
  }

  Future<List<Map<String, dynamic>>> searchOfflineCatalog(String query) {
    return mediaRepo.searchMedia(query);
  }

  /// Fase 2 (Resolução Magnet): Bloqueia DHT UDP e trackers clearnet por padrão sob Tor fail-closed.
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
