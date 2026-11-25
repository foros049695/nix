import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/media/nix_music_player_controller.dart';
import '../../../core/models/cultural_item.dart';
import '../../../core/models/cultural_tracking.dart';
import '../../../core/theme/nix_colors.dart';
import '../../../state/nix_state.dart';
import '../../profile/cultural_cover_art.dart';
import 'nix_media_facts_grid.dart';

class NixMusicDetail extends StatelessWidget {
  final CulturalItem item;
  final CulturalStage? status;
  final double? rating;
  final void Function(CulturalStage) onStatusChanged;
  final VoidCallback onToggleAcervo;
  final VoidCallback onRemoveAcervo;

  const NixMusicDetail({
    super.key,
    required this.item,
    required this.status,
    required this.rating,
    required this.onStatusChanged,
    required this.onToggleAcervo,
    required this.onRemoveAcervo,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final isInAcervo = state.userProfile.culturalItems.any((i) => i.id == item.id);
    final audioCtrl = NixMusicPlayerController();

    final albumName = item.externalIds['album'] as String? ??
        item.externalIds['release'] as String? ??
        (item.category == CulturalCategory.music ? item.title : null);
    final durationStr = item.externalIds['duration'] as String? ??
        item.externalIds['length'] as String?;
    final formatStr = item.externalIds['format'] as String? ?? 'Lossless';

    final facts = <FactEntry>[];
    if (item.creator != null && item.creator!.isNotEmpty) {
      facts.add(FactEntry(label: 'Artista / Intérprete', value: item.creator!));
    }
    if (albumName != null && albumName.isNotEmpty) {
      facts.add(FactEntry(label: 'Álbum', value: albumName));
    }
    if (item.releaseYear != null) {
      facts.add(FactEntry(label: 'Ano de Lançamento', value: item.releaseYear.toString()));
    }
    if (durationStr != null && durationStr.isNotEmpty) {
      facts.add(FactEntry(label: 'Duração', value: durationStr));
    }
    if (item.genres.isNotEmpty) {
      facts.add(FactEntry(label: 'Gêneros', value: item.genres.join(', ')));
    }
    if (item.source != null && item.source!.isNotEmpty) {
      facts.add(FactEntry(label: 'Proveniência', value: item.source!));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),

        // 1. Capa central de vinil ou encarte quadrado com sulcos realistas
        Center(
          child: Hero(
            tag: 'cultural_cover_${item.id}',
            child: CulturalCoverArt(
              item: item,
              width: 160,
              frameType: CulturalFrameType.vinyl,
            ),
          ),
        ),

        const SizedBox(height: 20),

        // 2. Título da faixa e artista
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

        const SizedBox(height: 4),

        Text(
          item.creatorOrYear,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: NixColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),

        const SizedBox(height: 12),

        // 3. Selo de qualidade de áudio (Lossless / Hi-Res / FLAC)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.graphic_eq_rounded, size: 14, color: Color(0xFF38BDF8)),
              const SizedBox(width: 5),
              Text(
                formatStr,
                style: const TextStyle(
                  color: Color(0xFF38BDF8),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 4. Controles de reprodução do player integrados
        AnimatedBuilder(
          animation: audioCtrl,
          builder: (context, _) {
            final isPlaying = audioCtrl.isPlaying;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded),
                        color: Colors.white70,
                        iconSize: 28,
                        onPressed: () => audioCtrl.previous(),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF7C3AED),
                        ),
                        child: IconButton(
                          icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          color: Colors.white,
                          iconSize: 32,
                          onPressed: () {
                            if (isPlaying) {
                              audioCtrl.pause();
                            } else {
                              audioCtrl.resume();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded),
                        color: Colors.white70,
                        iconSize: 28,
                        onPressed: () => audioCtrl.next(),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 16),

        // 5. Botão de ação (Adicionar ao Acervo / Biblioteca)
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
                  icon: const Icon(Icons.library_music_rounded, size: 18),
                  label: const Text('Adicionar à Biblioteca Musical'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  ),
                ),
        ),

        const SizedBox(height: 16),

        // 6. Seção "Presente em" (Appears on)
        if (albumName != null && albumName.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Presente em',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: const Color(0xFF1E1B2E),
                        ),
                        child: const Icon(Icons.album_rounded, color: Colors.white54),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              albumName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.creatorOrYear,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: NixColors.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // 7. Informações técnicas e metadados
        if (facts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: NixMediaFactsGrid(facts: facts),
          ),
          const SizedBox(height: 20),
        ],

        // 8. Ação de remover do acervo se estiver cadastrado
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
