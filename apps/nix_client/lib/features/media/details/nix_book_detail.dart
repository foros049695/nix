import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/cultural_item.dart';
import '../../../core/models/cultural_tracking.dart';
import '../../../core/theme/nix_colors.dart';
import '../../../state/nix_state.dart';
import '../../profile/cultural_cover_art.dart';
import 'nix_media_synopsis.dart';
import 'nix_media_facts_grid.dart';
import 'nix_media_recommendations.dart';

class NixBookDetail extends StatelessWidget {
  final CulturalItem item;
  final CulturalStage? status;
  final double? rating;
  final void Function(CulturalStage) onStatusChanged;
  final void Function(double) onRatingChanged;
  final VoidCallback onToggleAcervo;
  final VoidCallback onRemoveAcervo;

  const NixBookDetail({
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
    final isManga = item.category == CulturalCategory.manga;
    final facts = <FactEntry>[];

    if (item.creator != null && item.creator!.isNotEmpty) {
      facts.add(FactEntry(label: isManga ? 'Autor / Mangaká' : 'Autor', value: item.creator!));
    }
    if (item.releaseYear != null) {
      facts.add(FactEntry(label: 'Ano', value: item.releaseYear.toString()));
    }
    if (item.genres.isNotEmpty) {
      facts.add(FactEntry(label: 'Gêneros', value: item.genres.join(', ')));
    }
    final pagesOrChapters = item.externalIds['pages'] as String? ??
        item.externalIds['chapters'] as String? ??
        item.externalIds['volumes'] as String?;
    if (pagesOrChapters != null && pagesOrChapters.isNotEmpty) {
      facts.add(FactEntry(label: isManga ? 'Capítulos / Volumes' : 'Páginas', value: pagesOrChapters));
    }
    final publisher = item.externalIds['publisher'] as String? ??
        item.externalIds['editora'] as String?;
    if (publisher != null && publisher.isNotEmpty) {
      facts.add(FactEntry(label: 'Editora', value: publisher));
    }
    final isbn = item.externalIds['isbn'] as String?;
    if (isbn != null && isbn.isNotEmpty) {
      facts.add(FactEntry(label: 'ISBN', value: isbn));
    }

    final similarRaw = item.externalIds['similar'] as List?;
    final similarItems = similarRaw
            ?.map((e) => RecommendationItem.fromMap(e as Map<String, dynamic>))
            .toList() ??
        const <RecommendationItem>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),

        // 1. Capa central plana, limpa e autêntica (Northern Lights / Soul Eater style)
        Center(
          child: Hero(
            tag: 'cultural_cover_${item.id}',
            child: CulturalCoverArt(
              item: item,
              width: 150,
              frameType: isManga ? CulturalFrameType.mangaVolume : CulturalFrameType.closedBook,
              fit: BoxFit.contain,
              forceFlat: true,
            ),
          ),
        ),

        const SizedBox(height: 18),

        // 2. Título da obra
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            item.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ),

        if (item.originalTitle != null &&
            item.originalTitle!.isNotEmpty &&
            item.originalTitle != item.title) ...[
          const SizedBox(height: 4),
          Text(
            item.originalTitle!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: NixColors.textMuted,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],

        const SizedBox(height: 6),

        // 3. Autor e ano
        Text(
          item.creatorOrYear,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: NixColors.textSecondary,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
        ),

        const SizedBox(height: 14),

        // 4. Botão de ação principal (Adicionar ao Acervo ou status atual)
        Center(
          child: isInAcervo
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                  label: Text('Adicionar aos ${isManga ? 'Mangás' : 'Livros'}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  ),
                ),
        ),

        const SizedBox(height: 16),

        // 5. Avaliação pessoal por estrelas (se avaliado)
        if (rating != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
              const SizedBox(width: 4),
              Text(
                rating!.toStringAsFixed(1),
                style: const TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '· Sua avaliação pessoal',
                style: TextStyle(color: NixColors.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],

        // 6. Chips de estado de leitura
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

        const SizedBox(height: 20),

        // 7. Sinopse expansível
        if (item.synopsis != null && item.synopsis!.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: NixMediaSynopsis(synopsis: item.synopsis!),
          ),
          const SizedBox(height: 20),
        ],

        // 8. Informações técnicas em grade de 2 colunas
        if (facts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: NixMediaFactsGrid(facts: facts),
          ),
          const SizedBox(height: 20),
        ],

        // 9. Recomendações
        if (similarItems.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: NixMediaRecommendations(title: item.title, items: similarItems),
          ),
          const SizedBox(height: 20),
        ],

        // 10. Ação de remover do acervo se estiver cadastrado
        if (isInAcervo)
          TextButton.icon(
            onPressed: onRemoveAcervo,
            icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
            label: const Text(
              'Remover do Acervo',
              style: TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
