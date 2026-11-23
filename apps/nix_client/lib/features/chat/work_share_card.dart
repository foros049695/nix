import 'dart:convert';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/cultural_item.dart';
import '../../core/models/cultural_tracking.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import '../media/passport_dex_sheet.dart';

class WorkShareData {
  final String id;
  final String title;
  final String originalTitle;
  final String creator;
  final int? year;
  final String kind;
  final double? rating;
  final int? episodesCount;
  final int? totalEpisodes;
  final int? completedPercent;
  final String? status;
  final String synopsis;
  final List<String> genres;
  final String? coverPath;
  final String? source;
  final String? externalId;

  const WorkShareData({
    required this.id,
    required this.title,
    this.originalTitle = '',
    this.creator = '',
    this.year,
    required this.kind,
    this.rating,
    this.episodesCount,
    this.totalEpisodes,
    this.completedPercent,
    this.status,
    this.synopsis = '',
    this.genres = const [],
    this.coverPath,
    this.source,
    this.externalId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (originalTitle.isNotEmpty) 'originalTitle': originalTitle,
        if (creator.isNotEmpty) 'creator': creator,
        if (year != null) 'year': year,
        'kind': kind,
        if (rating != null) 'rating': rating,
        if (episodesCount != null) 'episodesCount': episodesCount,
        if (totalEpisodes != null) 'totalEpisodes': totalEpisodes,
        if (completedPercent != null) 'completedPercent': completedPercent,
        if (status != null && status!.isNotEmpty) 'status': status,
        if (synopsis.isNotEmpty) 'synopsis': synopsis,
        if (genres.isNotEmpty) 'genres': genres,
        if (coverPath != null) 'coverPath': coverPath,
        if (source != null) 'source': source,
        if (externalId != null) 'externalId': externalId,
      };

  static WorkShareData? tryParse(String raw) {
    if (!raw.startsWith('[NIX_WORK]:')) return null;
    try {
      final jsonStr = raw.substring('[NIX_WORK]:'.length).trim();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Sanitiza status antigos caso tenham emojis de troféus fictícios
      String? rawStatus = map['status'] as String?;
      if (rawStatus != null) {
        rawStatus = rawStatus.replaceAll('🏆', '').trim();
        if (rawStatus.toUpperCase() == 'WATCHED') {
          rawStatus = 'Concluído';
        }
      }

      double? parsedRating;
      if (map['rating'] != null) {
        parsedRating = (map['rating'] as num).toDouble();
      }

      final parsedYear = (map['year'] as num?)?.toInt();
      final episodes = (map['episodesCount'] as num?)?.toInt();
      final totalEps = (map['totalEpisodes'] as num?)?.toInt();
      final percent = (map['completedPercent'] as num?)?.toInt();

      return WorkShareData(
        id: map['id'] as String? ?? 'work_${DateTime.now().millisecondsSinceEpoch}',
        title: map['title'] as String? ?? 'Obra Cultural',
        originalTitle: map['originalTitle'] as String? ?? '',
        creator: map['creator'] as String? ?? '',
        year: parsedYear != null && parsedYear > 0 ? parsedYear : null,
        kind: map['kind'] as String? ?? 'anime',
        rating: parsedRating,
        episodesCount: episodes,
        totalEpisodes: totalEps,
        completedPercent: percent,
        status: rawStatus != null && rawStatus.isNotEmpty ? rawStatus : null,
        synopsis: map['synopsis'] as String? ?? '',
        genres: (map['genres'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
        coverPath: map['coverPath'] as String?,
        source: map['source'] as String?,
        externalId: map['externalId'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  String toMessageText() => '[NIX_WORK]:${jsonEncode(toJson())}';

  CulturalItem toCulturalItem() {
    final cat = switch (kind.toLowerCase()) {
      'manga' || 'mangá' => CulturalCategory.manga,
      'book' || 'livro' => CulturalCategory.books,
      'movie' || 'filme' => CulturalCategory.movies,
      'series' || 'série' => CulturalCategory.series,
      'music' || 'música' || 'album' || 'track' => CulturalCategory.music,
      _ => CulturalCategory.anime,
    };
    final stage = status != null
        ? CulturalStage.values.where((s) =>
            s.label.toLowerCase() == status!.toLowerCase() ||
            s.name.toLowerCase() == status!.toLowerCase()).firstOrNull
        : null;

    return CulturalItem(
      id: id,
      title: title,
      originalTitle: originalTitle.isNotEmpty ? originalTitle : null,
      creatorOrYear: [
        if (creator.isNotEmpty) creator,
        if (year != null && year! > 0) '$year',
      ].join(' · '),
      creator: creator.isNotEmpty ? creator : null,
      releaseYear: year,
      synopsis: synopsis.isNotEmpty ? synopsis : null,
      genres: genres,
      category: cat,
      rating: rating != null ? rating!.toStringAsFixed(1) : '',
      monogram: title.isNotEmpty ? String.fromCharCodes(title.runes.take(2)).toUpperCase() : 'NX',
      coverMotif: coverPath != null && coverPath!.startsWith('placeholder:') ? coverPath : null,
      localImagePath: coverPath != null && !coverPath!.startsWith('placeholder:') ? coverPath : null,
      source: source ?? 'shared_message',
      provenanceConfidence: 'strong_attributes',
      tracking: CulturalTracking(
        stage: stage,
        current: episodesCount,
        total: totalEpisodes,
      ),
    );
  }
}

class WorkShareCard extends StatelessWidget {
  final WorkShareData data;

  const WorkShareCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final isDesktop = defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        MediaQuery.sizeOf(context).width >= 900;

    final kindIcon = switch (data.kind.toLowerCase()) {
      'manga' || 'mangá' => Icons.menu_book_rounded,
      'book' || 'livro' => Icons.auto_stories_rounded,
      'movie' || 'filme' => Icons.movie_outlined,
      'series' || 'série' => Icons.tv_rounded,
      'music' || 'música' || 'track' || 'album' => Icons.music_note_rounded,
      _ => Icons.animation_rounded,
    };

    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      decoration: BoxDecoration(
        color: const Color(0xFF141322),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withValues(alpha: 0.12),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Banner estilizado de cabeçalho
          Container(
            height: 110,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF28183E), Color(0xFF0F2236)],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                      gradient: RadialGradient(
                        center: const Alignment(0.4, -0.2),
                        radius: 0.9,
                        colors: [
                          Colors.cyanAccent.withValues(alpha: 0.22),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Icon(
                    kindIcon,
                    size: 52,
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                // Badge de status real (se informado pelo remetente)
                if (data.status != null && data.status!.isNotEmpty)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.shade700.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        data.status!,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Categoria e ano
                Text(
                  '${data.kind.toUpperCase()}${data.genres.isNotEmpty ? " • ${data.genres.first.toUpperCase()}" : ""}${data.year != null && data.year! > 0 ? " (${data.year})" : ""}',
                  style: TextStyle(
                    color: Colors.cyanAccent.shade200,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                // Título principal
                Text(
                  data.title,
                  style: TextStyle(
                    color: NixColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (data.creator.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    data.creator,
                    style: TextStyle(
                      color: NixColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                // Avaliação pessoal verificada (apenas se avaliada)
                if (data.rating != null && data.rating! > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        data.rating!.toStringAsFixed(1),
                        style: TextStyle(
                          color: NixColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      for (int i = 0; i < 5; i++)
                        Icon(
                          (data.rating! / 2) >= i + 1
                              ? Icons.star_rounded
                              : ((data.rating! / 2) >= i + 0.5
                                  ? Icons.star_half_rounded
                                  : Icons.star_border_rounded),
                          size: 14,
                          color: Colors.cyanAccent.shade400,
                        ),
                      const SizedBox(width: 6),
                      Text(
                        'Avaliação pessoal',
                        style: TextStyle(color: NixColors.textMuted, fontSize: 10.5),
                      ),
                    ],
                  ),
                ],
                // Progresso real de episódios/capítulos (somente se legítimo)
                if (data.episodesCount != null && data.totalEpisodes != null && data.totalEpisodes! > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '${data.episodesCount} / ${data.totalEpisodes}',
                        style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                      ),
                      if (data.completedPercent != null && data.completedPercent! > 0) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.cyanAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            '${data.completedPercent}%',
                            style: TextStyle(
                              color: Colors.cyanAccent.shade200,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                if (data.synopsis.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    data.synopsis,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: NixColors.textSecondary,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // Botões de Ação
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: Key('view_passport_button_${data.id}'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () {
                          final state = context.read<NixState>();
                          final item = data.toCulturalItem();
                          if (isDesktop) {
                            state.openWorkDetail(item);
                          } else {
                            PassportDexSheet.showModal(context, item: item);
                          }
                        },
                        child: const Text('Ver obra ↗', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        key: Key('add_to_dex_button_${data.id}'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.cyanAccent.shade700,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () {
                          final state = context.read<NixState>();
                          state.addCulturalItem(data.toCulturalItem());
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${data.title} adicionado ao seu Acervo!'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        child: const Text('+ Ao Acervo', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
