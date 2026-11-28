import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/cultural_item.dart';
import '../../core/models/cultural_tracking.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import 'cultural_cover_art.dart';

/// Gerenciador de Livros, Mangás e Quadrinhos inspirado no BookManager, Kavita e Komga.
/// Permite organização de volumes e capítulos, detecção de volumes faltantes (missing volumes),
/// edição de metadados ComicInfo.xml, controle de leitura e conformidade de catálogo.
class BookMangaManagerSheet extends StatefulWidget {
  final CulturalItem item;
  final VoidCallback? onClose;

  const BookMangaManagerSheet({
    super.key,
    required this.item,
    this.onClose,
  });

  static Future<void> showModal(BuildContext context, {required CulturalItem item}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.94,
        child: BookMangaManagerSheet(item: item),
      ),
    );
  }

  @override
  State<BookMangaManagerSheet> createState() => _BookMangaManagerSheetState();
}

class _BookMangaManagerSheetState extends State<BookMangaManagerSheet> {
  late CulturalItem _current;
  late Set<int> _ownedVolumes;
  late int? _totalVolumes;
  late int? _currentVolume;
  late int? _currentChapter;
  late int? _totalChapters;
  late String? _format;
  late String? _readingDirection;
  late Map<String, dynamic> _comicInfo;

  @override
  void initState() {
    super.initState();
    _current = widget.item;
    _totalVolumes = _current.totalVolumes ?? _current.tracking.total;
    _currentVolume = _current.currentVolume ?? _current.tracking.seasonOrVolume ?? _current.tracking.current;
    _ownedVolumes = Set<int>.from(_current.ownedVolumes);
    if (_ownedVolumes.isEmpty && _currentVolume != null && _currentVolume! > 0) {
      _ownedVolumes.addAll(List.generate(_currentVolume!, (i) => i + 1));
    }
    _currentChapter = _current.currentChapter;
    _totalChapters = _current.totalChapters;
    _format = _current.format ?? (_current.category == CulturalCategory.manga ? 'cbz' : 'epub');
    _readingDirection = _current.readingDirection ??
        (_current.category == CulturalCategory.manga ? 'rtl' : 'ltr');
    _comicInfo = Map<String, dynamic>.from(_current.comicInfo);
  }

  void _persistChanges(NixState state) {
    final updated = _current.copyWith(
      format: _format,
      totalVolumes: _totalVolumes,
      currentVolume: _currentVolume,
      ownedVolumes: _ownedVolumes.toList()..sort(),
      totalChapters: _totalChapters,
      currentChapter: _currentChapter,
      comicInfo: _comicInfo,
      readingDirection: _readingDirection,
      tracking: _current.tracking.copyWith(
        current: _currentVolume ?? _current.tracking.current,
        total: _totalVolumes ?? _current.tracking.total,
        seasonOrVolume: _currentVolume ?? _current.tracking.seasonOrVolume,
      ),
    );

    setState(() => _current = updated);
    state.addCulturalItem(updated);
  }

  void _toggleVolumeOwned(int vol, NixState state) {
    setState(() {
      if (_ownedVolumes.contains(vol)) {
        _ownedVolumes.remove(vol);
      } else {
        _ownedVolumes.add(vol);
      }
    });
    _persistChanges(state);
  }

  void _markAllOwned(NixState state) {
    if (_totalVolumes == null || _totalVolumes! <= 0) return;
    setState(() {
      _ownedVolumes = Set.from(List.generate(_totalVolumes!, (i) => i + 1));
    });
    _persistChanges(state);
  }

  void _clearOwned(NixState state) {
    setState(() {
      _ownedVolumes.clear();
    });
    _persistChanges(state);
  }

  void _updateReadingProgress(int vol, NixState state) {
    setState(() {
      _currentVolume = vol;
      // Adiciona todos os volumes lidos como possuídos
      for (int i = 1; i <= vol; i++) {
        _ownedVolumes.add(i);
      }
      if (_totalVolumes != null && vol >= _totalVolumes!) {
        _current = _current.copyWith(
          tracking: _current.tracking.copyWith(stage: CulturalStage.finished),
        );
      } else if (_current.tracking.stage != CulturalStage.active) {
        _current = _current.copyWith(
          tracking: _current.tracking.copyWith(stage: CulturalStage.active),
        );
      }
    });
    _persistChanges(state);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final isManga = _current.category == CulturalCategory.manga;
    final missingVolumes = _current.missingVolumes;
    final hasMissing = missingVolumes.isNotEmpty;
    final totalV = _totalVolumes ?? (_ownedVolumes.isNotEmpty ? _ownedVolumes.reduce((a, b) => a > b ? a : b) : 1);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        color: const Color(0xFF100F18),
        child: Column(
          children: [
            // Topbar com distintivo BookManager
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFC084FC).withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.menu_book_rounded, size: 14, color: Color(0xFFC084FC)),
                        const SizedBox(width: 6),
                        Text(
                          isManga ? 'GERENCIADOR DE MANGÁS & HQS' : 'GERENCIADOR DE LIVROS & EBOOKS',
                          style: const TextStyle(
                            color: Color(0xFFC084FC),
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const Key('close_book_manager_sheet'),
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
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Cabeçalho da Obra com Capa Física 2.5D
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CulturalCoverArt(
                          item: _current,
                          width: 105,
                          frameType: isManga
                              ? CulturalFrameType.mangaVolume
                              : CulturalFrameType.closedBook,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _current.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              if (_current.originalTitle != null &&
                                  _current.originalTitle!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _current.originalTitle!,
                                  style: TextStyle(
                                    color: NixColors.textMuted,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                _current.creatorOrYear,
                                style: TextStyle(
                                  color: NixColors.textSecondary,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 10),
                              // Badges: Formato e Compatibilidade Kavita/Komga
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  // Seletor de Formato (CBZ, CBR, EPUB, PDF)
                                  PopupMenuButton<String>(
                                    tooltip: 'Alterar formato do arquivo',
                                    onSelected: (fmt) {
                                      setState(() => _format = fmt);
                                      _persistChanges(state);
                                    },
                                    itemBuilder: (ctx) => [
                                      for (final fmt in ['cbz', 'cbr', 'epub', 'pdf', 'mobi'])
                                        PopupMenuItem(
                                          value: fmt,
                                          child: Text(fmt.toUpperCase()),
                                        ),
                                    ],
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(color: Colors.white24),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            (_format ?? 'CBZ').toUpperCase(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.arrow_drop_down, size: 14, color: Colors.white70),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Badge de Direção de Leitura (RTL vs LTR)
                                  InkWell(
                                    onTap: () {
                                      final next = _readingDirection == 'rtl' ? 'ltr' : 'rtl';
                                      setState(() => _readingDirection = next);
                                      _persistChanges(state);
                                    },
                                    borderRadius: BorderRadius.circular(5),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.35)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _readingDirection == 'rtl'
                                                ? Icons.arrow_back_rounded
                                                : Icons.arrow_forward_rounded,
                                            size: 11,
                                            color: const Color(0xFF22D3EE),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _readingDirection == 'rtl' ? 'Mangá (RTL)' : 'Ocidental (LTR)',
                                            style: const TextStyle(
                                              color: Color(0xFF22D3EE),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Selo Kavita / Komga Ready
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle_outline_rounded, size: 11, color: Color(0xFF34D399)),
                                        SizedBox(width: 4),
                                        Text(
                                          'Kavita / Komga Ready',
                                          style: TextStyle(
                                            color: Color(0xFF34D399),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // 2. Painel de Volumes Faltantes e Resumo (BookManager Core Feature)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Volumes da Coleção',
                                style: TextStyle(
                                  color: NixColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    '${_ownedVolumes.length} de ${_totalVolumes ?? _ownedVolumes.length} adquiridos',
                                    style: TextStyle(
                                      color: NixColors.textSecondary,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _showEditTotalVolumesDialog(context, state),
                                    child: const Icon(Icons.edit_outlined, size: 14, color: Colors.cyanAccent),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Chip de status de volumes faltantes
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: hasMissing
                                  ? const Color(0xFF78350F).withValues(alpha: 0.25)
                                  : const Color(0xFF065F46).withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: hasMissing
                                    ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                                    : const Color(0xFF10B981).withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  hasMissing ? Icons.warning_amber_rounded : Icons.verified_rounded,
                                  size: 13,
                                  color: hasMissing ? const Color(0xFFFBBF24) : const Color(0xFF34D399),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _current.missingVolumesSummary,
                                  style: TextStyle(
                                    color: hasMissing ? const Color(0xFFFDE68A) : const Color(0xFFA7F3D0),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Matriz Interativa de Volumes (Grid de 1..Total)
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (int v = 1; v <= totalV; v++)
                                _buildVolumeChip(v, state),
                            ],
                          ),

                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => _markAllOwned(state),
                                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                child: const Text('Marcar todos adquiridos', style: TextStyle(fontSize: 11)),
                              ),
                              const SizedBox(width: 6),
                              TextButton(
                                onPressed: () => _clearOwned(state),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: Colors.redAccent,
                                ),
                                child: const Text('Limpar', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 3. Controle de Leitura (Volume Atual e Capítulos)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Progresso de Leitura',
                            style: TextStyle(
                              color: NixColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Volume lido: ${_currentVolume ?? 0} / ${_totalVolumes ?? "?"}',
                                      style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.remove_circle_outline, size: 20),
                                          onPressed: (_currentVolume ?? 0) > 0
                                              ? () => _updateReadingProgress((_currentVolume ?? 1) - 1, state)
                                              : null,
                                        ),
                                        Text(
                                          '${_currentVolume ?? 0}',
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.add_circle_outline, size: 20),
                                          onPressed: () =>
                                              _updateReadingProgress((_currentVolume ?? 0) + 1, state),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Capítulo: ${_currentChapter ?? 0} / ${_totalChapters ?? "?"}',
                                      style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.remove_circle_outline, size: 20),
                                          onPressed: (_currentChapter ?? 0) > 0
                                              ? () {
                                                  setState(() => _currentChapter = (_currentChapter ?? 1) - 1);
                                                  _persistChanges(state);
                                                }
                                              : null,
                                        ),
                                        Text(
                                          '${_currentChapter ?? 0}',
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.add_circle_outline, size: 20),
                                          onPressed: () {
                                            setState(() => _currentChapter = (_currentChapter ?? 0) + 1);
                                            _persistChanges(state);
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 4. Editor de Metadados ComicInfo.xml / Kavita / Komga
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.code_rounded, size: 16, color: Color(0xFFC084FC)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Metadados ComicInfo.xml',
                                    style: TextStyle(
                                      color: NixColors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                ),
                                onPressed: () => _showComicInfoEditorDialog(context, state),
                                icon: const Icon(Icons.edit_rounded, size: 13),
                                label: const Text('Editar Ficha', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _metadataRow('Série:', _comicInfo['series'] ?? _current.title),
                          _metadataRow('Roteirista / Writer:', _comicInfo['writer'] ?? _current.creator ?? 'Não informado'),
                          _metadataRow('Desenhista / Penciller:', _comicInfo['penciller'] ?? 'Não informado'),
                          _metadataRow('Editora / Publisher:', _comicInfo['publisher'] ?? 'Não informada'),
                          _metadataRow('Classificação:', _comicInfo['ageRating'] ?? 'Livre'),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _exportComicInfoXml(context),
                                  icon: const Icon(Icons.file_download_outlined, size: 15),
                                  label: const Text('Visualizar ComicInfo.xml', style: TextStyle(fontSize: 11)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
                                  onPressed: () => _prepareKavitaKomgaStructure(context, state),
                                  icon: const Icon(Icons.folder_special_outlined, size: 15),
                                  label: const Text('Preparar Komga/Kavita', style: TextStyle(fontSize: 11)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeChip(int vol, NixState state) {
    final isOwned = _ownedVolumes.contains(vol);
    final isRead = _currentVolume != null && vol <= _currentVolume!;

    Color bg;
    Color border;
    Color text;

    if (isRead) {
      bg = const Color(0xFF10B981).withValues(alpha: 0.25);
      border = const Color(0xFF10B981);
      text = const Color(0xFFA7F3D0);
    } else if (isOwned) {
      bg = const Color(0xFF7C3AED).withValues(alpha: 0.25);
      border = const Color(0xFF8B5CF6);
      text = Colors.white;
    } else {
      bg = Colors.white.withValues(alpha: 0.04);
      border = Colors.white24;
      text = Colors.white38;
    }

    return Tooltip(
      message: isRead
          ? 'Vol. $vol: Adquirido e lido'
          : isOwned
              ? 'Vol. $vol: Adquirido (a ler)'
              : 'Vol. $vol: Ausente (clique para adicionar à coleção)',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _toggleVolumeOwned(vol, state),
        onLongPress: () => _updateReadingProgress(vol, state),
        child: Container(
          width: 38,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border, width: isRead || isOwned ? 1.5 : 1),
          ),
          child: Text(
            '$vol',
            style: TextStyle(
              color: text,
              fontSize: 12,
              fontWeight: isRead || isOwned ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _metadataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(color: NixColors.textMuted, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: NixColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditTotalVolumesDialog(BuildContext context, NixState state) {
    final ctrl = TextEditingController(text: (_totalVolumes ?? 1).toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quantidade Total de Volumes'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Total de volumes publicados',
            hintText: 'Ex: 12, 24, 36',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(ctrl.text.trim());
              if (parsed != null && parsed > 0) {
                setState(() => _totalVolumes = parsed);
                _persistChanges(state);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  void _showComicInfoEditorDialog(BuildContext context, NixState state) {
    final seriesCtrl = TextEditingController(text: _comicInfo['series'] ?? _current.title);
    final writerCtrl = TextEditingController(text: _comicInfo['writer'] ?? _current.creator ?? '');
    final pencillerCtrl = TextEditingController(text: _comicInfo['penciller'] ?? '');
    final publisherCtrl = TextEditingController(text: _comicInfo['publisher'] ?? '');
    final ageRatingCtrl = TextEditingController(text: _comicInfo['ageRating'] ?? 'Teen');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar Metadados ComicInfo.xml'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: seriesCtrl, decoration: const InputDecoration(labelText: 'Série (Series)')),
              TextField(controller: writerCtrl, decoration: const InputDecoration(labelText: 'Roteirista (Writer)')),
              TextField(controller: pencillerCtrl, decoration: const InputDecoration(labelText: 'Desenhista (Penciller)')),
              TextField(controller: publisherCtrl, decoration: const InputDecoration(labelText: 'Editora (Publisher)')),
              TextField(controller: ageRatingCtrl, decoration: const InputDecoration(labelText: 'Classificação Etária')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              setState(() {
                _comicInfo['series'] = seriesCtrl.text.trim();
                _comicInfo['writer'] = writerCtrl.text.trim();
                _comicInfo['penciller'] = pencillerCtrl.text.trim();
                _comicInfo['publisher'] = publisherCtrl.text.trim();
                _comicInfo['ageRating'] = ageRatingCtrl.text.trim();
              });
              _persistChanges(state);
              Navigator.pop(ctx);
            },
            child: const Text('Salvar Metadados'),
          ),
        ],
      ),
    );
  }

  void _exportComicInfoXml(BuildContext context) {
    final isManga = _current.category == CulturalCategory.manga;
    final xml = '''<?xml version="1.0" encoding="utf-8"?>
<ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <Title>${_current.title}</Title>
  <Series>${_comicInfo['series'] ?? _current.title}</Series>
  <Number>${_currentVolume ?? 1}</Number>
  <Count>${_totalVolumes ?? 1}</Count>
  <Volume>${_currentVolume ?? 1}</Volume>
  <Summary>${_current.synopsis ?? ''}</Summary>
  <Year>${_current.releaseYear ?? ''}</Year>
  <Writer>${_comicInfo['writer'] ?? _current.creator ?? ''}</Writer>
  <Penciller>${_comicInfo['penciller'] ?? ''}</Penciller>
  <Publisher>${_comicInfo['publisher'] ?? ''}</Publisher>
  <Genre>${_current.genres.join(', ')}</Genre>
  <LanguageISO>${_current.language ?? 'pt-BR'}</LanguageISO>
  <AgeRating>${_comicInfo['ageRating'] ?? 'Teen'}</AgeRating>
  <Manga>${isManga ? (_readingDirection == 'rtl' ? 'YesAndRightToLeft' : 'Yes') : 'No'}</Manga>
</ComicInfo>''';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Metadados ComicInfo.xml Gerados'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: SelectableText(
              xml,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      ),
    );
  }

  void _prepareKavitaKomgaStructure(BuildContext context, NixState state) {
    setState(() {
      _comicInfo['kavitaPrepared'] = true;
      _comicInfo['komgaPrepared'] = true;
    });
    _persistChanges(state);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Metadados preparados para bibliotecas Kavita & Komga (${_current.title})!'),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
