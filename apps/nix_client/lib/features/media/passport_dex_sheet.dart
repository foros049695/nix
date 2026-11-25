import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/cultural_item.dart';
import '../../core/models/cultural_tracking.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import '../profile/cultural_cover_art.dart';

class PassportDexSheet extends StatefulWidget {
  final CulturalItem item;
  final VoidCallback? onClose;
  final bool isSidebar;

  const PassportDexSheet({
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
        child: PassportDexSheet(item: item),
      ),
    );
  }

  @override
  State<PassportDexSheet> createState() => _PassportDexSheetState();
}

class _PassportDexSheetState extends State<PassportDexSheet> {
  CulturalStage? _status;
  double? _rating;

  @override
  void initState() {
    super.initState();
    _status = widget.item.tracking.stage;
    final r = double.tryParse(widget.item.rating);
    // Só considera rating válido se for maior que zero e diferente de 0.0
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
    final synopsis = widget.item.synopsis?.trim() ?? '';
    final isBook = widget.item.category == CulturalCategory.books;
    final hasImage = widget.item.localImagePath != null &&
        File(widget.item.localImagePath!).existsSync();

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
            // Fundo derivado da capa com desfoque profundo (PassportDex & Fireside Folio)
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
                // Barra de título com botão fechar (Nomenclatura do projeto)
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
                        key: const Key('close_passport_dex_button'),
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
                  // Capa da obra em destaque (2.5D ou disco ou pôster)
                  Center(
                    child: Hero(
                      tag: 'passport_cover_${widget.item.id}',
                      child: CulturalCoverArt(
                        item: widget.item,
                        width: widget.isSidebar ? 140 : 160,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Título principal
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
                  // Criador / Autor e Ano
                  Text(
                    widget.item.creatorOrYear,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: NixColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Avaliação pessoal real (apenas se avaliada)
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

                  // Seletor rápido de avaliação em estrelas
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

                  // Botão de Adicionar ao Acervo (caso não esteja adicionado)
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
                        label: const Text('Adicionar à Minha Biblioteca / Acervo',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Botões de Status de Acompanhamento Pessoal (Responsivo com Wrap)
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

                  // Sinopse Real da Obra
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: NixColors.surfaceCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: NixColors.surfaceBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sinopse da Obra',
                          style: TextStyle(
                            color: NixColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          synopsis.isNotEmpty ? synopsis : 'Sinopse não disponível.',
                          style: TextStyle(
                            color: synopsis.isNotEmpty ? NixColors.textSecondary : NixColors.textMuted,
                            fontSize: 12.5,
                            height: 1.4,
                            fontStyle: synopsis.isNotEmpty ? FontStyle.normal : FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Gêneros e Detalhes Técnicos Reais
                  if (widget.item.genres.isNotEmpty) ...[
                    const SizedBox(height: 14),
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

                  // Ficha Editorial Especializada para Livros (Fireside Folio)
                  if (isBook) ...[
                    _buildFiresideFolioEditorialSection(context, state),
                  ],

                  // Links Externos Verificados (Se existirem)
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

                  // Proveniência dos Dados
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

                  // Ação rápida: Pesquisar referências no Nix Torrent Index
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
              Icon(Icons.auto_stories_outlined, size: 16, color: const Color(0xFFFBBF24)),
              const SizedBox(width: 8),
              Text(
                'Ficha Editorial · Fireside Folio',
                style: TextStyle(
                  color: const Color(0xFFFBBF24),
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
      padding: const EdgeInsets.symmetric(vertical: 2.5),
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

  Widget _statusChip({
    required String label,
    required CulturalStage status,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: Key('passport_status_chip_${status.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? Colors.white.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? Colors.white : Colors.white24,
            width: active ? 1.2 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : NixColors.textMuted,
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _linkButton(String name, IconData icon, String url) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.cyanAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            const Icon(Icons.arrow_outward_rounded, size: 14, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}
