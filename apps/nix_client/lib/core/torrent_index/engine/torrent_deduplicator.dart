import '../models/torrent_record.dart';

/// Motor de deduplicação e fusão de metadados do Nix Torrent Index.
/// Prioridades inegociáveis:
/// 1. InfoHash BitTorrent v1 idêntico.
/// 2. InfoHash BitTorrent v2 equivalente.
/// NÃO agrupa automaticamente torrents diferentes somente por terem títulos parecidos.
class TorrentDeduplicator {
  /// Deduplica uma lista de registros mesclando suas proveniências.
  static List<TorrentIndexRecord> deduplicate(List<TorrentIndexRecord> records) {
    if (records.isEmpty) return const [];

    final Map<String, TorrentIndexRecord> byHash = {};
    final List<TorrentIndexRecord> nonHashRecords = [];

    for (final rec in records) {
      final key = rec.infoHashV1?.toLowerCase() ?? rec.infoHashV2?.toLowerCase();
      if (key == null || key.isEmpty) {
        nonHashRecords.add(rec);
        continue;
      }

      if (!byHash.containsKey(key)) {
        // Primeiro registro com este hash
        final initialProvenances = List<TorrentSourceProvenance>.from(rec.provenances);
        if (initialProvenances.isEmpty) {
          initialProvenances.add(TorrentSourceProvenance(
            sourceId: rec.sourceId,
            sourceName: rec.sourceName,
            sourceUrl: rec.sourceUrl,
            seeders: rec.seeders,
            leechers: rec.leechers,
            observedAt: rec.lastSeenAt,
          ));
        }
        byHash[key] = rec.copyWith(provenances: initialProvenances);
      } else {
        // Já existe um registro com o mesmo hash: mescla proveniência
        final existing = byHash[key]!;
        final mergedProvenances = List<TorrentSourceProvenance>.from(existing.provenances);

        // Adiciona nova proveniência se ainda não registrada para esta fonte
        final existsForSource = mergedProvenances.any((p) => p.sourceId == rec.sourceId);
        if (!existsForSource) {
          mergedProvenances.add(TorrentSourceProvenance(
            sourceId: rec.sourceId,
            sourceName: rec.sourceName,
            sourceUrl: rec.sourceUrl,
            seeders: rec.seeders,
            leechers: rec.leechers,
            observedAt: rec.lastSeenAt,
          ));
        }

        // Determina o tamanho conhecido
        final bestSize = existing.sizeBytes ?? rec.sizeBytes;

        // Determina a data mais recente
        final bestPubDate = (existing.publicationDate != null && rec.publicationDate != null)
            ? (existing.publicationDate!.isAfter(rec.publicationDate!) ? existing.publicationDate : rec.publicationDate)
            : (existing.publicationDate ?? rec.publicationDate);

        // Seeders: preserva a maior contagem observada recentemente
        final bestSeeders = (existing.seeders != null && rec.seeders != null)
            ? (existing.seeders! > rec.seeders! ? existing.seeders : rec.seeders)
            : (existing.seeders ?? rec.seeders);

        final bestLeechers = (existing.leechers != null && rec.leechers != null)
            ? (existing.leechers! > rec.leechers! ? existing.leechers : rec.leechers)
            : (existing.leechers ?? rec.leechers);

        // Descrição e magnet
        final bestDesc = (existing.description != null && existing.description!.isNotEmpty)
            ? existing.description
            : rec.description;

        final bestMagnet = existing.magnetUri ?? rec.magnetUri;
        final bestTorrentUrl = existing.torrentFileUrl ?? rec.torrentFileUrl;

        // Tags unificadas
        final mergedTags = {...existing.tags, ...rec.tags}.toList();

        byHash[key] = existing.copyWith(
          sizeBytes: bestSize,
          publicationDate: bestPubDate,
          seeders: bestSeeders,
          leechers: bestLeechers,
          description: bestDesc,
          magnetUri: bestMagnet,
          torrentFileUrl: bestTorrentUrl,
          tags: mergedTags,
          lastSeenAt: existing.lastSeenAt.isAfter(rec.lastSeenAt) ? existing.lastSeenAt : rec.lastSeenAt,
          provenances: mergedProvenances,
        );
      }
    }

    return [...byHash.values, ...nonHashRecords];
  }
}
