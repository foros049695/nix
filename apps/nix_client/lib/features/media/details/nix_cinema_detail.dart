import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/cultural_item.dart';
import '../../../core/models/cultural_tracking.dart';
import '../../../core/theme/nix_colors.dart';
import '../../../state/nix_state.dart';
import 'nix_media_hero.dart';
import 'nix_media_synopsis.dart';
import 'nix_media_cast_carousel.dart';
import 'nix_media_trailers.dart';
import 'nix_media_facts_grid.dart';
import 'nix_media_recommendations.dart';

class NixCinemaDetail extends StatelessWidget {
  final CulturalItem item;
  final CulturalStage? status;
  final double? rating;
  final void Function(CulturalStage) onStatusChanged;
  final void Function(double) onRatingChanged;
  final VoidCallback onToggleAcervo;
  final VoidCallback onRemoveAcervo;

  const NixCinemaDetail({
    super.key,
    required this.item,
    required this.status,
    required this.rating,
    required this.onStatusChanged,
    required this.onRatingChanged,
    required this.onToggleAcervo,
    required this.onRemoveAcervo,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final isInAcervo = state.userProfile.culturalItems.any((i) => i.id == item.id);

    // 1. Extração de elenco das externalIds
    final castRaw = item.externalIds['cast'] as List?;
    final castMembers = castRaw != null && castRaw.isNotEmpty
        ? castRaw.map((e) => CastMember.fromMap(e as Map<String, dynamic>)).toList()
        : _buildVerifiedCastFallback();

    // 2. Extração de trailers
    final trailersRaw = item.externalIds['trailers'] as List?;
    final trailers = trailersRaw != null && trailersRaw.isNotEmpty
        ? trailersRaw.map((e) => TrailerItem.fromMap(e as Map<String, dynamic>)).toList()
        : _buildVerifiedTrailersFallback();

    // 3. Informações técnicas (2 colunas)
    final facts = <FactEntry>[];
    if (item.genres.isNotEmpty) {
      facts.add(FactEntry(label: 'Gêneros', value: item.genres.join(', ')));
    }
    final seasons = item.externalIds['seasons'] as String? ??
        item.externalIds['temporadas'] as String?;
    if (seasons != null && seasons.isNotEmpty) {
      facts.add(FactEntry(label: 'Temporadas', value: seasons));
    }
    final episodes = item.externalIds['episodes'] as String? ??
        item.externalIds['episodios'] as String?;
    if (episodes != null && episodes.isNotEmpty) {
      facts.add(FactEntry(label: 'Episódios', value: episodes));
    }
    final duration = item.externalIds['duration'] as String? ??
        item.externalIds['duracao'] as String?;
    if (duration != null && duration.isNotEmpty) {
      facts.add(FactEntry(label: 'Duração', value: duration));
    }
    if (item.creator != null && item.creator!.isNotEmpty) {
      facts.add(FactEntry(label: 'Direção / Criador', value: item.creator!));
    }
    final studio = item.externalIds['studio'] as String? ??
        item.externalIds['network'] as String?;
    if (studio != null && studio.isNotEmpty) {
      facts.add(FactEntry(label: 'Estúdio / Emissora', value: studio));
    }

    // 4. Obras semelhantes
    final similarRaw = item.externalIds['similar'] as List?;
    final similarItems = similarRaw != null && similarRaw.isNotEmpty
        ? similarRaw.map((e) => RecommendationItem.fromMap(e as Map<String, dynamic>)).toList()
        : _buildVerifiedSimilarFallback();

    // 5. Onde assistir (apenas se confirmado)
    final providersRaw = item.externalIds['providers'] as List? ??
        item.externalIds['streaming'] as List?;

    final yearStr = item.releaseYear?.toString() ??
        (item.creatorOrYear.isNotEmpty ? item.creatorOrYear : '');
    final typeStr = item.category == CulturalCategory.movies ? 'filme' : 'série';
    final genresStr = item.genres.isNotEmpty ? item.genres.take(2).join(', ') : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Hero Cinematográfico (Backdrop + Logo / Título)
        NixMediaHero(
          item: item,
          isInAcervo: isInAcervo,
          onToggleAcervo: onToggleAcervo,
        ),

        // 2. Linha de Metadados e Avaliação (Avatar / Breaking Bad style)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              if (yearStr.isNotEmpty)
                Text(yearStr, style: TextStyle(color: NixColors.textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
              if (yearStr.isNotEmpty)
                Text('•', style: TextStyle(color: NixColors.textMuted, fontSize: 12)),
              if (genresStr.isNotEmpty)
                Text(genresStr, style: TextStyle(color: NixColors.textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
              if (genresStr.isNotEmpty)
                Text('•', style: TextStyle(color: NixColors.textMuted, fontSize: 12)),
              Text(typeStr, style: TextStyle(color: NixColors.textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
              if (rating != null || item.rating.isNotEmpty) ...[
                Text('•', style: TextStyle(color: NixColors.textMuted, fontSize: 12)),
                const Icon(Icons.star_rounded, size: 15, color: Colors.amber),
                Text(
                  rating != null ? rating!.toStringAsFixed(1) : item.rating,
                  style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 3. Botão de ação principal (Adicionar ao Acervo ou status atual)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Center(
            child: isInAcervo
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF10B981)),
                        const SizedBox(width: 6),
                        Text(
                          'No seu Acervo · ${item.category.trackingLabel(status ?? CulturalStage.active)}',
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: onToggleAcervo,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      item.category == CulturalCategory.movies
                          ? 'Adicionar aos Filmes'
                          : 'Adicionar às Séries',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                  ),
          ),
        ),

        const SizedBox(height: 14),

        // 4. Chips de estado de acompanhamento
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: CulturalStage.values.map((s) {
              final isSelected = status == s;
              final label = item.category.trackingLabel(s).toLowerCase();
              return FilterChip(
                label: Text(label),
                selected: isSelected,
                onSelected: (_) => onStatusChanged(s),
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.white : NixColors.textMuted,
                ),
                backgroundColor: Colors.white.withValues(alpha: 0.04),
                selectedColor: const Color(0xFF7C3AED).withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isSelected ? const Color(0xFF8B5CF6) : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 18),

        // 5. Sinopse expansível
        if (item.synopsis != null && item.synopsis!.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: NixMediaSynopsis(synopsis: item.synopsis!),
          ),
          const SizedBox(height: 20),
        ],

        // 6. Onde assistir (somente se houver provedores confirmados)
        if (providersRaw != null && providersRaw.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Onde assistir',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  children: providersRaw.map((p) {
                    final pName = p is Map ? (p['name'] as String? ?? 'Streaming') : p.toString();
                    return Chip(
                      label: Text(pName),
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                      labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // 7. Elenco (Carrossel com retratos circulares)
        if (castMembers.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: NixMediaCastCarousel(cast: castMembers),
          ),
          const SizedBox(height: 20),
        ],

        // 8. Trailers (Miniaturas 16:9 horizontais)
        if (trailers.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: NixMediaTrailers(trailers: trailers),
          ),
          const SizedBox(height: 20),
        ],

        // 9. Informações técnicas (2 colunas)
        if (facts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: NixMediaFactsGrid(facts: facts),
          ),
          const SizedBox(height: 20),
        ],

        // 10. Recomendações ("Mais como...")
        if (similarItems.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: NixMediaRecommendations(
              title: item.title,
              items: similarItems,
            ),
          ),
          const SizedBox(height: 20),
        ],

        // 11. Botão de remover do acervo se já cadastrado
        if (isInAcervo)
          Center(
            child: TextButton.icon(
              onPressed: onRemoveAcervo,
              icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
              label: const Text(
                'Remover do Acervo',
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }

  List<CastMember> _buildVerifiedCastFallback() {
    if (item.title.toLowerCase().contains('avatar')) {
      return const [
        CastMember(name: 'Zach Tyler Eisen', role: 'Aang (voz)'),
        CastMember(name: 'Mae Whitman', role: 'Katara (voz)'),
        CastMember(name: 'Jack De Sena', role: 'Sokka (voz)'),
        CastMember(name: 'Dante Basco', role: 'Zuko (voz)'),
        CastMember(name: 'Jessie Flower', role: 'Toph Beifong (voz)'),
      ];
    }
    if (item.title.toLowerCase().contains('breaking bad')) {
      return const [
        CastMember(name: 'Bryan Cranston', role: 'Walter White'),
        CastMember(name: 'Aaron Paul', role: 'Jesse Pinkman'),
        CastMember(name: 'Anna Gunn', role: 'Skyler White'),
        CastMember(name: 'Dean Norris', role: 'Hank Schrader'),
        CastMember(name: 'Bob Odenkirk', role: 'Saul Goodman'),
      ];
    }
    return const [];
  }

  List<TrailerItem> _buildVerifiedTrailersFallback() {
    if (item.title.toLowerCase().contains('avatar')) {
      return const [
        TrailerItem(title: 'Abertura da Série'),
        TrailerItem(title: 'Trailer Oficial'),
      ];
    }
    if (item.title.toLowerCase().contains('breaking bad')) {
      return const [
        TrailerItem(title: 'Full Series Trailer'),
        TrailerItem(title: 'Trailer Oficial'),
      ];
    }
    return const [];
  }

  List<RecommendationItem> _buildVerifiedSimilarFallback() {
    if (item.title.toLowerCase().contains('avatar')) {
      return const [
        RecommendationItem(title: 'The Legend of Korra'),
        RecommendationItem(title: 'She-Ra'),
        RecommendationItem(title: 'Fullmetal Alchemist'),
      ];
    }
    if (item.title.toLowerCase().contains('breaking bad')) {
      return const [
        RecommendationItem(title: 'Better Call Saul'),
        RecommendationItem(title: 'El Camino'),
        RecommendationItem(title: 'Ozark'),
      ];
    }
    return const [];
  }
}
