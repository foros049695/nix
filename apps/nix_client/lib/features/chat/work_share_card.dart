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
  final int year;
  final String kind;
  final double rating;
  final int reviewsCount;
  final int passportsCount;
  final int episodesCount;
  final int completedPercent;
  final String status;
  final String tier;
  final String synopsis;
  final List<String> genres;
  final String? coverPath;

  const WorkShareData({
    required this.id,
    required this.title,
    this.originalTitle = '',
    required this.creator,
    required this.year,
    required this.kind,
    this.rating = 9.4,
    this.reviewsCount = 1700,
    this.passportsCount = 12546,
    this.episodesCount = 10,
    this.completedPercent = 100,
    this.status = 'WATCHED 🏆',
    this.tier = 'S-TIER ⭐',
    this.synopsis = '',
    this.genres = const ['Ação', 'Sci-Fi', 'Cyberpunk'],
    this.coverPath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'originalTitle': originalTitle,
        'creator': creator,
        'year': year,
        'kind': kind,
        'rating': rating,
        'reviewsCount': reviewsCount,
        'passportsCount': passportsCount,
        'episodesCount': episodesCount,
        'completedPercent': completedPercent,
        'status': status,
        'tier': tier,
        'synopsis': synopsis,
        'genres': genres,
        if (coverPath != null) 'coverPath': coverPath,
      };

  static WorkShareData? tryParse(String raw) {
    if (!raw.startsWith('[NIX_WORK]:')) return null;
    try {
      final jsonStr = raw.substring('[NIX_WORK]:'.length).trim();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return WorkShareData(
        id: map['id'] as String? ?? 'work_${DateTime.now().millisecondsSinceEpoch}',
        title: map['title'] as String? ?? 'Obra Cultural',
        originalTitle: map['originalTitle'] as String? ?? '',
        creator: map['creator'] as String? ?? 'Autor desconhecido',
        year: (map['year'] as num?)?.toInt() ?? 2024,
        kind: map['kind'] as String? ?? 'anime',
        rating: (map['rating'] as num?)?.toDouble() ?? 9.4,
        reviewsCount: (map['reviewsCount'] as num?)?.toInt() ?? 1700,
        passportsCount: (map['passportsCount'] as num?)?.toInt() ?? 12546,
        episodesCount: (map['episodesCount'] as num?)?.toInt() ?? 10,
        completedPercent: (map['completedPercent'] as num?)?.toInt() ?? 100,
        status: map['status'] as String? ?? 'WATCHED 🏆',
        tier: map['tier'] as String? ?? 'S-TIER ⭐',
        synopsis: map['synopsis'] as String? ?? '',
        genres: (map['genres'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            const ['Sci-Fi', 'Cyberpunk'],
        coverPath: map['coverPath'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  String toMessageText() => '[NIX_WORK]:${jsonEncode(toJson())}';

  CulturalItem toCulturalItem() {
    final cat = switch (kind.toLowerCase()) {
      'manga' => CulturalCategory.manga,
      'book' || 'livro' => CulturalCategory.books,
      'movie' || 'filme' => CulturalCategory.movies,
      'series' || 'série' => CulturalCategory.series,
      'music' || 'música' => CulturalCategory.music,
      _ => CulturalCategory.anime,
    };
    return CulturalItem(
      id: id,
      title: title,
      creatorOrYear: '$creator ($year)',
      monogram: title.isNotEmpty ? title[0] : 'W',
      category: cat,
      rating: rating.toStringAsFixed(1),
      tracking: const CulturalTracking(stage: CulturalStage.finished),
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
          // Banner com badges Cyberpunk/PassportDex
          Container(
            height: 125,
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
                // Brilho estilizado
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                      gradient: RadialGradient(
                        center: const Alignment(0.4, -0.2),
                        radius: 0.9,
                        colors: [
                          Colors.cyanAccent.withValues(alpha: 0.25),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Ícone temático central
                Center(
                  child: Icon(
                    switch (data.kind.toLowerCase()) {
                      'manga' => Icons.menu_book_rounded,
                      'book' || 'livro' => Icons.auto_stories_rounded,
                      'movie' || 'filme' => Icons.movie_outlined,
                      'series' || 'série' => Icons.tv_rounded,
                      _ => Icons.animation_rounded,
                    },
                    size: 56,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                // Badges superiores: Status e Tier
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
                      data.status,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 9.5,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade700.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      data.tier,
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
                  '${data.kind.toUpperCase()} • ${data.genres.isNotEmpty ? data.genres.first.toUpperCase() : "OBRA"} (${data.year})',
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
                const SizedBox(height: 5),
                // Avaliação em estrelas
                Row(
                  children: [
                    Text(
                      data.rating.toStringAsFixed(1),
                      style: TextStyle(
                        color: NixColors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    for (int i = 0; i < 5; i++)
                      Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Colors.cyanAccent.shade400,
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                // Episódios e conclusão
                Row(
                  children: [
                    Text(
                      '${data.episodesCount} / ${data.episodesCount} eps',
                      style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        'COMPLETED ${data.completedPercent}%',
                        style: TextStyle(
                          color: Colors.cyanAccent.shade200,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Metadados da comunidade / Dex
                Text(
                  'In ${data.passportsCount} Passports • ${(data.reviewsCount / 1000).toStringAsFixed(1)}k Reviews • Favorite ❤️',
                  style: TextStyle(color: NixColors.textMuted, fontSize: 10),
                ),
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
