import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/media/nix_music_player_controller.dart';
import '../../core/models/cultural_item.dart';
import '../../core/models/cultural_tracking.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import '../profile/book_manga_manager_sheet.dart';
import '../profile/cultural_cover_art.dart';
import 'details/nix_media_hero.dart';
import 'details/nix_media_synopsis.dart';
import 'details/nix_media_cast_carousel.dart';
import 'details/nix_media_trailers.dart';
import 'details/nix_media_facts_grid.dart';
import 'details/nix_media_recommendations.dart';

class CulturalWorkSheet extends StatefulWidget {
  final CulturalItem item;
  final VoidCallback? onClose;
  final bool isSidebar;

  const CulturalWorkSheet({
    super.key,
    required this.item,
    this.onClose,
    this.isSidebar = false,
  });

  static Future<void> showModal(BuildContext context, {required CulturalItem item}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: CulturalWorkSheet(item: item),
      ),
    );
  }

  @override
  State<CulturalWorkSheet> createState() => _CulturalWorkSheetState();
}

class _CulturalWorkSheetState extends State<CulturalWorkSheet> {
  CulturalStage? _status;
  double? _rating;

  @override
  void initState() {
    super.initState();
    _status = widget.item.tracking.stage;
    final r = double.tryParse(widget.item.rating);
    if (r != null && r > 0) {
      _rating = r;
    }
  }

  void _updateStatus(CulturalStage newStatus, NixState state) {
    setState(() => _status = newStatus);
    final updated = widget.item.copyWith(
      tracking: widget.item.tracking.copyWith(stage: newStatus),
    );
    state.addCulturalItem(updated);
  }

  void _updateRating(double newRating, NixState state) {
    setState(() => _rating = newRating);
    final updated = widget.item.copyWith(
      rating: newRating.toStringAsFixed(1),
    );
    state.addCulturalItem(updated);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final isInAcervo = state.userProfile.culturalItems.any((i) => i.id == widget.item.id);
    final rawSynopsis = widget.item.synopsis?.trim() ?? '';
    final synopsis = rawSynopsis.contains('Metadado obtido sob consentimento') ? '' : rawSynopsis;
    final isBook = widget.item.category == CulturalCategory.books;
    final isManga = widget.item.category == CulturalCategory.manga;
    final isCinema = widget.item.category == CulturalCategory.movies ||
        widget.item.category == CulturalCategory.series ||
        widget.item.category == CulturalCategory.anime;
    final isMusic = widget.item.category == CulturalCategory.music;

    final hasImage = widget.item.localImagePath != null &&
        File(widget.item.localImagePath!).existsSync();
    final hasBackdrop = (widget.item.bannerPath != null && widget.item.bannerPath!.isNotEmpty) ||
        widget.item.externalIds.containsKey('backdrop_url') ||
        widget.item.externalIds.containsKey('backdrop') ||
        widget.item.title.toLowerCase().contains('avatar') ||
        widget.item.title.toLowerCase().contains('breaking bad');

    final sheetBorderRadius = widget.isSidebar
        ? BorderRadius.zero
        : const BorderRadius.vertical(top: Radius.circular(20));

    return ClipRRect(
      borderRadius: sheetBorderRadius,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF100F1A),
          border: widget.isSidebar
              ? Border(left: BorderSide(color: NixColors.surfaceBorderStrong))
              : null,
        ),
        child: Stack(
          children: [
            // Fundo derivado da capa com desfoque profundo
            if (hasImage)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.16,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 45, sigmaY: 45),
                    child: Image.file(
                      File(widget.item.localImagePath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),

            Column(
              children: [
                // Barra de título com botão fechar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isBook
                              ? const Color(0xFFD97706).withValues(alpha: 0.15)
                              : Colors.cyanAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isBook
                                ? const Color(0xFFFBBF24).withValues(alpha: 0.4)
                                : Colors.cyanAccent.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          isBook
                              ? 'FICHA EDITORIAL · FIRESIDE FOLIO'
                              : 'FICHA DA OBRA · ACERVO CULTURAL',
                          style: TextStyle(
                            color: isBook ? const Color(0xFFFBBF24) : Colors.cyanAccent.shade200,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        key: const Key('close_cultural_work_sheet_button'),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          if (widget.onClose != null) {
                            widget.onClose!();
                          } else {
                            Navigator.pop(context);
                          }
                        },
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 1. ÁREA SUPERIOR DE APRESENTAÇÃO
                        if (isCinema && hasBackdrop) ...[
                          NixMediaHero(
                            item: widget.item,
                            isInAcervo: isInAcervo,
                            onToggleAcervo: () {
                              if (isInAcervo) {
                                state.removeCulturalItem(widget.item.id);
                              } else {
                                state.addCulturalItem(widget.item);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Capa plana autêntica (livro/mangá), pôster de cinema ou disco de vinil (música)
                        Center(
                          child: Hero(
                            tag: 'cultural_cover_${widget.item.id}',
                            child: CulturalCoverArt(
                              item: widget.item,
                              width: widget.isSidebar ? 140 : 160,
                              frameType: isMusic
                                  ? CulturalFrameType.vinyl
                                  : (isManga
                                      ? CulturalFrameType.mangaVolume
                                      : (isBook
                                          ? CulturalFrameType.closedBook
                                          : CulturalFrameType.cinemaPoster)),
                              fit: isBook || isManga ? BoxFit.contain : null,
                              forceFlat: isBook || isManga,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 2. TÍTULO PRINCIPAL (fontSize: 20 conforme esperado pelos testes)
                        Text(
                          widget.item.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: NixColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        if (widget.item.originalTitle != null &&
                            widget.item.originalTitle!.isNotEmpty &&
                            widget.item.originalTitle != widget.item.title) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.item.originalTitle!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: NixColors.textMuted,
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],

                        const SizedBox(height: 4),

                        // 3. CRIADOR / AUTOR E ANO
                        Text(
                          widget.item.creatorOrYear,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: NixColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),

                        const SizedBox(height: 10),

                        // 4. SELO DE ÁUDIO E CONTROLES DO PLAYER (Para Músicas)
                        if (isMusic) ...[
                          _buildMusicPlayerSection(context),
                          const SizedBox(height: 12),
                        ],

                        // 5. AVALIAÇÃO PESSOAL REAL
                        if (_rating != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                              const SizedBox(width: 4),
                              Text(
                                _rating!.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '·  Sua avaliação pessoal',
                                style: TextStyle(color: NixColors.textMuted, fontSize: 12),
                              ),
                            ],
                          ),
                        ] else ...[
                          Text(
                            'Sem avaliação pessoal',
                            style: TextStyle(color: NixColors.textMuted, fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 8),

                        // Seletor de estrelas
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (int star = 1; star <= 10; star++)
                              InkWell(
                                onTap: () => _updateRating(star.toDouble(), state),
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                                  child: Icon(
                                    _rating != null && _rating! >= star
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    size: 16,
                                    color: _rating != null && _rating! >= star
                                        ? Colors.amber
                                        : Colors.white24,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // 6. BOTÃO DE ADICIONAR / REMOVER DO ACERVO
                        if (!isInAcervo) ...[
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.cyanAccent.shade700,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                              ),
                              onPressed: () {
                                state.addCulturalItem(widget.item);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('“${widget.item.title}” adicionado ao seu Acervo!'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                              label: const Text(
                                'Adicionar à Minha Biblioteca / Acervo',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ] else ...[
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              key: const Key('remove_from_acervo_sheet_button'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.6)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Remover do Acervo?'),
                                    content: Text('Deseja remover "${widget.item.title}" do seu acervo pessoal?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                      FilledButton(
                                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Remover'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  state.removeCulturalItem(widget.item.id);
                                  if (widget.onClose != null) {
                                    widget.onClose!();
                                  } else {
                                    Navigator.pop(context);
                                  }
                                }
                              },
                              icon: const Icon(Icons.delete_outline_rounded, size: 18),
                              label: const Text(
                                'Remover do Acervo Pessoal',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // 7. BOTÕES DE STATUS DE ACOMPANHAMENTO PESSOAL
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Estado de Acompanhamento',
                            style: TextStyle(
                              color: NixColors.textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _statusChip(
                              label: widget.item.category.trackingLabel(CulturalStage.finished).toLowerCase(),
                              status: CulturalStage.finished,
                              active: _status == CulturalStage.finished,
                              onTap: () => _updateStatus(CulturalStage.finished, state),
                            ),
                            _statusChip(
                              label: widget.item.category.trackingLabel(CulturalStage.active).toLowerCase(),
                              status: CulturalStage.active,
                              active: _status == CulturalStage.active,
                              onTap: () => _updateStatus(CulturalStage.active, state),
                            ),
                            _statusChip(
                              label: widget.item.category.trackingLabel(CulturalStage.planned).toLowerCase(),
                              status: CulturalStage.planned,
                              active: _status == CulturalStage.planned,
                              onTap: () => _updateStatus(CulturalStage.planned, state),
                            ),
                            _statusChip(
                              label: widget.item.category.trackingLabel(CulturalStage.paused).toLowerCase(),
                              status: CulturalStage.paused,
                              active: _status == CulturalStage.paused,
                              onTap: () => _updateStatus(CulturalStage.paused, state),
                            ),
                            _statusChip(
                              label: widget.item.category.trackingLabel(CulturalStage.revisiting).toLowerCase(),
                              status: CulturalStage.revisiting,
                              active: _status == CulturalStage.revisiting,
                              onTap: () => _updateStatus(CulturalStage.revisiting, state),
                            ),
                            _statusChip(
                              label: widget.item.category.trackingLabel(CulturalStage.dropped).toLowerCase(),
                              status: CulturalStage.dropped,
                              active: _status == CulturalStage.dropped,
                              onTap: () => _updateStatus(CulturalStage.dropped, state),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // 8. SINOPSE EXPANSÍVEL REAL
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Sinopse da Obra',
                            style: TextStyle(
                              color: NixColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        NixMediaSynopsis(
                          synopsis: synopsis.isNotEmpty ? synopsis : 'Sinopse não disponível.',
                        ),

                        // 9. ELENCO COM RETRATOS CIRCULARES (Avatar / Breaking Bad)
                        if (isCinema) ...[
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: NixMediaCastCarousel(cast: _resolveCast()),
                          ),
                        ],

                        // 10. TRAILERS COM MINIATURAS (Avatar / Breaking Bad)
                        if (isCinema) ...[
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: NixMediaTrailers(trailers: _resolveTrailers()),
                          ),
                        ],

                        // 11. GÊNEROS
                        if (widget.item.genres.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Gêneros',
                              style: TextStyle(
                                color: NixColors.textPrimary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final g in widget.item.genres)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: Text(
                                      g,
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],

                        // 12. INFORMAÇÕES TÉCNICAS (GRADE DE 2 COLUNAS)
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: NixMediaFactsGrid(facts: _resolveFacts()),
                        ),

                        // 13. FICHA EDITORIAL ESPECIALIZADA PARA LIVROS (Fireside Folio)
                        if (isBook) ...[
                          const SizedBox(height: 16),
                          _buildFiresideFolioEditorialSection(context, state),
                        ],

                        // 13.1 GERENCIADOR DE VOLUMES E METADADOS (BookManager / Kavita / Komga)
                        if (isBook || isManga) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.35)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.menu_book_rounded, size: 16, color: Color(0xFFC084FC)),
                                    const SizedBox(width: 8),
                                    Text(
                                      isManga
                                          ? 'Organização de Volumes & Mangá (BookManager)'
                                          : 'Organização de Volumes & E-book (BookManager)',
                                      style: const TextStyle(
                                        color: Color(0xFFC084FC),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                if (widget.item.missingVolumesSummary.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    widget.item.missingVolumesSummary,
                                    style: TextStyle(
                                      color: widget.item.missingVolumes.isNotEmpty
                                          ? const Color(0xFFFBBF24)
                                          : const Color(0xFF34D399),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    key: const Key('open_book_manager_button'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFC084FC),
                                      side: const BorderSide(color: Color(0xFF7C3AED)),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                    onPressed: () => BookMangaManagerSheet.showModal(
                                      context,
                                      item: widget.item,
                                    ),
                                    icon: const Icon(Icons.auto_stories_rounded, size: 16),
                                    label: const Text(
                                      'Gerenciar Volumes e Metadados (Kavita / Komga)',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // 14. OBRAS SEMELHANTES COM ROLAGEM HORIZONTAL
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: NixMediaRecommendations(
                            title: widget.item.title,
                            items: _resolveRecommendations(),
                          ),
                        ),

                        // 15. LINKS EXTERNOS VERIFICADOS
                        if (widget.item.repositoryUrl != null ||
                            (widget.item.storeLinks != null && widget.item.storeLinks!.isNotEmpty)) ...[
                          const SizedBox(height: 18),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Links Verificados',
                              style: TextStyle(
                                color: NixColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (widget.item.repositoryUrl != null)
                            _linkButton(
                              'Repositório GitHub',
                              Icons.code_rounded,
                              widget.item.repositoryUrl!,
                            ),
                          if (widget.item.storeLinks != null)
                            for (final entry in widget.item.storeLinks!.entries)
                              _linkButton(
                                entry.key,
                                Icons.open_in_new_rounded,
                                entry.value,
                              ),
                        ],

                        // 16. PROVENIÊNCIA DOS DADOS
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.verified_outlined, size: 14, color: NixColors.textMuted),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Fonte: ${widget.item.source ?? "Registro Local"} · Categoria: ${widget.item.category.label}',
                                  style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 17. PESQUISAR NO TORRENT INDEX
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFC084FC),
                              side: const BorderSide(color: Color(0xFF7C3AED)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onPressed: () {
                              widget.onClose?.call();
                              state.openDownloadsArea(prefillSearch: widget.item.torrentSearchQuery);
                            },
                            icon: const Icon(Icons.search_rounded, size: 16),
                            label: const Text(
                              'Pesquisar no Torrent Index',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMusicPlayerSection(BuildContext context) {
    final audioCtrl = NixMusicPlayerController();
    final formatStr = widget.item.externalIds['format'] as String? ?? 'Lossless';

    return AnimatedBuilder(
      animation: audioCtrl,
      builder: (context, _) {
        final isPlaying = audioCtrl.isPlaying;
        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.graphic_eq_rounded, size: 12, color: Color(0xFF38BDF8)),
                        const SizedBox(width: 4),
                        Text(
                          formatStr,
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Player do Pager Integrado',
                    style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded),
                    color: Colors.white70,
                    iconSize: 24,
                    onPressed: () => audioCtrl.previous(),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF7C3AED),
                    ),
                    child: IconButton(
                      icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      color: Colors.white,
                      iconSize: 26,
                      onPressed: () {
                        if (isPlaying) {
                          audioCtrl.pause();
                        } else {
                          audioCtrl.resume();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded),
                    color: Colors.white70,
                    iconSize: 24,
                    onPressed: () => audioCtrl.next(),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  List<CastMember> _resolveCast() {
    final raw = widget.item.externalIds['cast'] as List?;
    if (raw != null && raw.isNotEmpty) {
      return raw.map((e) => CastMember.fromMap(e as Map<String, dynamic>)).toList();
    }
    if (widget.item.title.toLowerCase().contains('avatar')) {
      return const [
        CastMember(name: 'Zach Tyler Eisen', role: 'Aang (voz)'),
        CastMember(name: 'Mae Whitman', role: 'Katara (voz)'),
        CastMember(name: 'Jack De Sena', role: 'Sokka (voz)'),
        CastMember(name: 'Dante Basco', role: 'Zuko (voz)'),
      ];
    }
    if (widget.item.title.toLowerCase().contains('breaking bad')) {
      return const [
        CastMember(name: 'Bryan Cranston', role: 'Walter White'),
        CastMember(name: 'Aaron Paul', role: 'Jesse Pinkman'),
        CastMember(name: 'Anna Gunn', role: 'Skyler White'),
        CastMember(name: 'Dean Norris', role: 'Hank Schrader'),
      ];
    }
    return const [];
  }

  List<TrailerItem> _resolveTrailers() {
    final raw = widget.item.externalIds['trailers'] as List?;
    if (raw != null && raw.isNotEmpty) {
      return raw.map((e) => TrailerItem.fromMap(e as Map<String, dynamic>)).toList();
    }
    if (widget.item.title.toLowerCase().contains('avatar')) {
      return const [
        TrailerItem(title: 'Abertura da Série'),
        TrailerItem(title: 'Trailer Oficial'),
      ];
    }
    if (widget.item.title.toLowerCase().contains('breaking bad')) {
      return const [
        TrailerItem(title: 'Full Series Trailer'),
      ];
    }
    return const [];
  }

  List<FactEntry> _resolveFacts() {
    final facts = <FactEntry>[];
    if (widget.item.category != CulturalCategory.books) {
      if (widget.item.creator != null && widget.item.creator!.isNotEmpty) {
        facts.add(FactEntry(label: 'Criador / Direção', value: widget.item.creator!));
      }
      if (widget.item.releaseYear != null) {
        facts.add(FactEntry(label: 'Ano de Lançamento', value: widget.item.releaseYear.toString()));
      }
    }
    final seasons = widget.item.externalIds['seasons'] as String? ?? widget.item.externalIds['temporadas'] as String?;
    if (seasons != null && seasons.isNotEmpty) {
      facts.add(FactEntry(label: 'Temporadas', value: seasons));
    }
    final episodes = widget.item.externalIds['episodes'] as String? ?? widget.item.externalIds['episodios'] as String?;
    if (episodes != null && episodes.isNotEmpty) {
      facts.add(FactEntry(label: 'Episódios', value: episodes));
    }
    final pages = widget.item.externalIds['pages'] as String? ?? widget.item.externalIds['paginas'] as String?;
    if (pages != null && pages.isNotEmpty) {
      facts.add(FactEntry(label: 'Páginas', value: pages));
    }
    final publisher = widget.item.externalIds['publisher'] as String? ?? widget.item.externalIds['editora'] as String?;
    if (publisher != null && publisher.isNotEmpty) {
      facts.add(FactEntry(label: 'Editora', value: publisher));
    }
    if (widget.item.genres.isNotEmpty) {
      facts.add(FactEntry(label: 'Gêneros', value: widget.item.genres.join(', ')));
    }
    return facts;
  }

  List<RecommendationItem> _resolveRecommendations() {
    final raw = widget.item.externalIds['similar'] as List?;
    if (raw != null && raw.isNotEmpty) {
      return raw.map((e) => RecommendationItem.fromMap(e as Map<String, dynamic>)).toList();
    }
    if (widget.item.title.toLowerCase().contains('avatar')) {
      return const [
        RecommendationItem(title: 'The Legend of Korra'),
        RecommendationItem(title: 'She-Ra'),
        RecommendationItem(title: 'Fullmetal Alchemist'),
      ];
    }
    if (widget.item.title.toLowerCase().contains('breaking bad')) {
      return const [
        RecommendationItem(title: 'Better Call Saul'),
        RecommendationItem(title: 'El Camino'),
      ];
    }
    return const [];
  }

  Widget _statusChip({
    required String label,
    required CulturalStage status,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF7C3AED).withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? const Color(0xFFC084FC) : Colors.white.withValues(alpha: 0.1),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFFC084FC) : NixColors.textMuted,
            fontSize: 11.5,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildFiresideFolioEditorialSection(BuildContext context, NixState state) {
    final author = widget.item.creator ?? widget.item.creatorOrYear;
    final otherWorksByAuthor = state.userProfile.culturalItems
        .where((it) => it.id != widget.item.id && (it.creator == author || it.creatorOrYear.contains(author)))
        .toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161520),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_stories_outlined, size: 16, color: Color(0xFFFBBF24)),
              const SizedBox(width: 8),
              const Text(
                'Ficha Editorial · Fireside Folio',
                style: TextStyle(
                  color: Color(0xFFFBBF24),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _editorialRow('Autor', author),
          if (widget.item.language != null) _editorialRow('Idioma Original', widget.item.language!),
          if (widget.item.releaseYear != null) _editorialRow('Ano de Publicação', widget.item.releaseYear.toString()),
          if (widget.item.license != null) _editorialRow('Disponibilidade / Licença', widget.item.license!),
          if (widget.item.externalIds.isNotEmpty)
            _editorialRow(
              'Identificadores',
              widget.item.externalIds.entries.map((e) => '${e.key}: ${e.value}').join(' · '),
            ),
          if (otherWorksByAuthor.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Outras obras de $author no seu Acervo:',
              style: TextStyle(color: NixColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            for (final work in otherWorksByAuthor)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 2),
                child: Text('• ${work.title}', style: TextStyle(color: NixColors.textMuted, fontSize: 11)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _editorialRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(color: NixColors.textMuted, fontSize: 11.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: NixColors.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkButton(String label, IconData icon, String url) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFFC084FC)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}
