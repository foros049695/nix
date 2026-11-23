import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/models/cultural_item.dart';
import '../../core/models/cultural_tracking.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../design/nix_glass.dart';

/// Opções de filtragem avançada de múltiplas seleções do Acervo Cultural (Seção 1).
class CulturalFilterOptions {
  final Set<CulturalCategory> categories;
  final Set<CulturalStage> stages;
  final bool includeNoStage;
  final bool favoriteOnly;
  final bool? hasRating; // true: com avaliação, false: sem avaliação, null: todos
  final bool? hasReview; // true: com review, false: sem review, null: todos
  final bool? hasProgress; // true: com progresso, false: sem progresso, null: todos
  final Set<String> sources; // 'import', 'manual', 'catalog'

  const CulturalFilterOptions({
    this.categories = const {},
    this.stages = const {},
    this.includeNoStage = false,
    this.favoriteOnly = false,
    this.hasRating,
    this.hasReview,
    this.hasProgress,
    this.sources = const {},
  });

  bool get isEmpty =>
      categories.isEmpty &&
      stages.isEmpty &&
      !includeNoStage &&
      !favoriteOnly &&
      hasRating == null &&
      hasReview == null &&
      hasProgress == null &&
      sources.isEmpty;

  int get activeFiltersCount {
    int count = 0;
    count += categories.length;
    count += stages.length;
    if (includeNoStage) count++;
    if (favoriteOnly) count++;
    if (hasRating != null) count++;
    if (hasReview != null) count++;
    if (hasProgress != null) count++;
    count += sources.length;
    return count;
  }

  CulturalFilterOptions copyWith({
    Set<CulturalCategory>? categories,
    Set<CulturalStage>? stages,
    bool? includeNoStage,
    bool? favoriteOnly,
    bool? Function()? hasRating,
    bool? Function()? hasReview,
    bool? Function()? hasProgress,
    Set<String>? sources,
  }) {
    return CulturalFilterOptions(
      categories: categories ?? this.categories,
      stages: stages ?? this.stages,
      includeNoStage: includeNoStage ?? this.includeNoStage,
      favoriteOnly: favoriteOnly ?? this.favoriteOnly,
      hasRating: hasRating != null ? hasRating() : this.hasRating,
      hasReview: hasReview != null ? hasReview() : this.hasReview,
      hasProgress: hasProgress != null ? hasProgress() : this.hasProgress,
      sources: sources ?? this.sources,
    );
  }

  /// Aplica a regra lógica:
  /// Dentro de um grupo (ex: Categorias): OU.
  /// Dentro de Status: OU.
  /// Entre grupos diferentes: E.
  bool matches(CulturalItem item) {
    // 1. Grupo Categorias (OU)
    if (categories.isNotEmpty && !categories.contains(item.category)) {
      return false;
    }

    // 2. Grupo Status (OU)
    if (stages.isNotEmpty || includeNoStage) {
      final itemStage = item.tracking.stage;
      final matchStage = itemStage != null && stages.contains(itemStage);
      final matchNoStage = includeNoStage && itemStage == null;
      if (!matchStage && !matchNoStage) {
        return false;
      }
    }

    // 3. Grupo Outros Filtros (E entre cada critério ativo)
    if (favoriteOnly && !item.tracking.favorite) {
      return false;
    }

    final hasUserRating = item.rating.trim().isNotEmpty &&
        item.rating != '0' &&
        item.rating != '0.0' &&
        item.rating != '9.5';
    if (hasRating == true && !hasUserRating) {
      return false;
    }
    if (hasRating == false && hasUserRating) {
      return false;
    }

    final hasUserReview = item.tracking.review.trim().isNotEmpty;
    if (hasReview == true && !hasUserReview) {
      return false;
    }
    if (hasReview == false && hasUserReview) {
      return false;
    }

    final hasUserProgress =
        item.tracking.current != null && item.tracking.current! > 0;
    if (hasProgress == true && !hasUserProgress) {
      return false;
    }
    if (hasProgress == false && hasUserProgress) {
      return false;
    }

    // 4. Grupo Origem / Proveniência
    if (sources.isNotEmpty) {
      final s = item.source?.toLowerCase() ??
          (item.id.startsWith('catalog:') ? 'catalog' : 'manual');
      final isImport =
          s.contains('import') || s == 'csv_import' || s == 'html_import';
      final isCatalog = s == 'catalog' || item.id.startsWith('catalog:');
      final isManual = s == 'manual' || (!isImport && !isCatalog);

      bool matchSource = false;
      if (sources.contains('import') && isImport) matchSource = true;
      if (sources.contains('catalog') && isCatalog) matchSource = true;
      if (sources.contains('manual') && isManual) matchSource = true;

      if (!matchSource) return false;
    }

    return true;
  }
}

/// Painel expansível sob a barra de busca contendo checkboxes agrupados (Seção 1).
class CulturalFilterPanel extends StatefulWidget {
  final CulturalFilterOptions initialOptions;
  final ValueChanged<CulturalFilterOptions> onApply;
  final VoidCallback onClose;

  const CulturalFilterPanel({
    super.key,
    required this.initialOptions,
    required this.onApply,
    required this.onClose,
  });

  @override
  State<CulturalFilterPanel> createState() => _CulturalFilterPanelState();
}

class _CulturalFilterPanelState extends State<CulturalFilterPanel> {
  late Set<CulturalCategory> _categories;
  late Set<CulturalStage> _stages;
  late bool _includeNoStage;
  late bool _favoriteOnly;
  late bool? _hasRating;
  late bool? _hasReview;
  late bool? _hasProgress;
  late Set<String> _sources;

  @override
  void initState() {
    super.initState();
    _categories = Set.from(widget.initialOptions.categories);
    _stages = Set.from(widget.initialOptions.stages);
    _includeNoStage = widget.initialOptions.includeNoStage;
    _favoriteOnly = widget.initialOptions.favoriteOnly;
    _hasRating = widget.initialOptions.hasRating;
    _hasReview = widget.initialOptions.hasReview;
    _hasProgress = widget.initialOptions.hasProgress;
    _sources = Set.from(widget.initialOptions.sources);
  }

  void _clear() {
    setState(() {
      _categories.clear();
      _stages.clear();
      _includeNoStage = false;
      _favoriteOnly = false;
      _hasRating = null;
      _hasReview = null;
      _hasProgress = null;
      _sources.clear();
    });
    _apply();
  }

  void _apply() {
    final opts = CulturalFilterOptions(
      categories: _categories,
      stages: _stages,
      includeNoStage: _includeNoStage,
      favoriteOnly: _favoriteOnly,
      hasRating: _hasRating,
      hasReview: _hasReview,
      hasProgress: _hasProgress,
      sources: _sources,
    );
    widget.onApply(opts);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NixColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NixColors.surfaceBorderStrong),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            offset: const Offset(0, 4),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabeçalho do Painel
          Row(
            children: [
              const Icon(Icons.filter_list_rounded, size: 18, color: Colors.cyanAccent),
              const SizedBox(width: 8),
              Text(
                'Filtros do Acervo',
                style: TextStyle(
                  color: NixColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _clear,
                child: const Text('Limpar filtros', style: TextStyle(fontSize: 12)),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Fechar painel',
                onPressed: widget.onClose,
              ),
            ],
          ),
          const Divider(height: 16),

          // Grupo 1: Categorias (OU)
          Text('CATEGORIAS',
              style: TextStyle(
                color: Colors.cyanAccent.shade200,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              )),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final cat in CulturalCategory.values)
                _checkboxChip(
                  label: cat.label,
                  checked: _categories.contains(cat),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _categories.add(cat);
                      } else {
                        _categories.remove(cat);
                      }
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Grupo 2: Status / Acompanhamento (OU)
          Text('STATUS DE ACOMPANHAMENTO',
              style: TextStyle(
                color: Colors.cyanAccent.shade200,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              )),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _checkboxChip(
                label: 'Concluído / Assistido / Lido',
                checked: _stages.contains(CulturalStage.finished),
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _stages.add(CulturalStage.finished);
                    } else {
                      _stages.remove(CulturalStage.finished);
                    }
                  });
                },
              ),
              _checkboxChip(
                label: 'Em andamento / Assistindo / Lendo',
                checked: _stages.contains(CulturalStage.active),
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _stages.add(CulturalStage.active);
                    } else {
                      _stages.remove(CulturalStage.active);
                    }
                  });
                },
              ),
              _checkboxChip(
                label: 'Quero assistir / ler / ouvir (Pretendo)',
                checked: _stages.contains(CulturalStage.planned),
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _stages.add(CulturalStage.planned);
                    } else {
                      _stages.remove(CulturalStage.planned);
                    }
                  });
                },
              ),
              _checkboxChip(
                label: 'Em pausa',
                checked: _stages.contains(CulturalStage.paused),
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _stages.add(CulturalStage.paused);
                    } else {
                      _stages.remove(CulturalStage.paused);
                    }
                  });
                },
              ),
              _checkboxChip(
                label: 'Revisitando / Relendo / Reassistindo',
                checked: _stages.contains(CulturalStage.revisiting),
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _stages.add(CulturalStage.revisiting);
                    } else {
                      _stages.remove(CulturalStage.revisiting);
                    }
                  });
                },
              ),
              _checkboxChip(
                label: 'Abandonado',
                checked: _stages.contains(CulturalStage.dropped),
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _stages.add(CulturalStage.dropped);
                    } else {
                      _stages.remove(CulturalStage.dropped);
                    }
                  });
                },
              ),
              _checkboxChip(
                label: 'Sem status definido',
                checked: _includeNoStage,
                onChanged: (val) => setState(() => _includeNoStage = val ?? false),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Grupo 3: Outros Filtros Úteis
          Text('OUTROS FILTROS',
              style: TextStyle(
                color: Colors.cyanAccent.shade200,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              )),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _checkboxChip(
                label: 'Favoritos ❤️',
                checked: _favoriteOnly,
                onChanged: (val) => setState(() => _favoriteOnly = val ?? false),
              ),
              _checkboxChip(
                label: 'Com avaliação pessoal',
                checked: _hasRating == true,
                onChanged: (val) => setState(() => _hasRating = val == true ? true : null),
              ),
              _checkboxChip(
                label: 'Sem avaliação',
                checked: _hasRating == false,
                onChanged: (val) => setState(() => _hasRating = val == true ? false : null),
              ),
              _checkboxChip(
                label: 'Com review escrita',
                checked: _hasReview == true,
                onChanged: (val) => setState(() => _hasReview = val == true ? true : null),
              ),
              _checkboxChip(
                label: 'Com progresso registrado',
                checked: _hasProgress == true,
                onChanged: (val) => setState(() => _hasProgress = val == true ? true : null),
              ),
              _checkboxChip(
                label: 'Origem importada (CSV / HTML)',
                checked: _sources.contains('import'),
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _sources.add('import');
                    } else {
                      _sources.remove('import');
                    }
                  });
                },
              ),
              _checkboxChip(
                label: 'Origem do Catálogo Nix',
                checked: _sources.contains('catalog'),
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _sources.add('catalog');
                    } else {
                      _sources.remove('catalog');
                    }
                  });
                },
              ),
              _checkboxChip(
                label: 'Origem manual',
                checked: _sources.contains('manual'),
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _sources.add('manual');
                    } else {
                      _sources.remove('manual');
                    }
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Botões de Ação
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: widget.onClose,
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('apply_cultural_filters_button'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.cyanAccent.shade700,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  _apply();
                  widget.onClose();
                },
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Aplicar filtros', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _checkboxChip({
    required String label,
    required bool checked,
    required ValueChanged<bool?> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!checked),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: checked ? Colors.cyanAccent.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: checked ? Colors.cyanAccent : Colors.white12,
            width: checked ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 15,
              color: checked ? Colors.cyanAccent : Colors.white54,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: checked ? Colors.white : NixColors.textSecondary,
                fontSize: 11.5,
                fontWeight: checked ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra de Paginação Reutilizável Real (Seção 2 e 3).
///
/// Limite: no máximo quatro fileiras de obras por página (cols × 4).
/// Formato da régua: 1  2  3  4  5  6 ... Próxima
class CulturalPaginationControls extends StatelessWidget {
  final int currentPage; // 1-indexed
  final int totalPages;
  final int totalItems;
  final int pageSize;
  final ValueChanged<int> onPageChanged;

  const CulturalPaginationControls({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.pageSize,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Text(
            '$totalItems obra(s) cadastrada(s)',
            style: TextStyle(color: NixColors.textMuted, fontSize: 11.5),
          ),
        ),
      );
    }

    final isCompact = MediaQuery.sizeOf(context).width < 500;

    // Constrói a lista de números de páginas visíveis
    final List<int?> pageNumbers = [];
    if (totalPages <= 7) {
      for (int i = 1; i <= totalPages; i++) {
        pageNumbers.add(i);
      }
    } else {
      pageNumbers.add(1);
      if (currentPage > 3) {
        pageNumbers.add(null); // elipse ...
      }
      final start = math.max(2, currentPage - 1);
      final end = math.min(totalPages - 1, currentPage + 1);
      for (int i = start; i <= end; i++) {
        pageNumbers.add(i);
      }
      if (currentPage < totalPages - 2) {
        pageNumbers.add(null); // elipse ...
      }
      pageNumbers.add(totalPages);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Botão Anterior
                OutlinedButton.icon(
                  key: const Key('pagination_prev_button'),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 12, vertical: 8),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  onPressed: currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
                  icon: const Icon(Icons.chevron_left_rounded, size: 18),
                  label: Text(isCompact ? '' : 'Anterior', style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 6),

                // Números das páginas
                for (final p in pageNumbers)
                  if (p == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text('…', style: TextStyle(color: Colors.white54, fontSize: 14)),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: InkWell(
                        key: Key('pagination_page_$p'),
                        onTap: p == currentPage ? null : () => onPageChanged(p),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: p == currentPage
                                ? Colors.cyanAccent.shade700
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: p == currentPage ? Colors.cyanAccent : Colors.white12,
                            ),
                          ),
                          child: Text(
                            '$p',
                            style: TextStyle(
                              color: p == currentPage ? Colors.black : Colors.white,
                              fontSize: 12.5,
                              fontWeight: p == currentPage ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),

                const SizedBox(width: 6),
                // Botão Próxima
                OutlinedButton.icon(
                  key: const Key('pagination_next_button'),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 12, vertical: 8),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  onPressed: currentPage < totalPages ? () => onPageChanged(currentPage + 1) : null,
                  icon: Text(isCompact ? '' : 'Próxima', style: const TextStyle(fontSize: 12)),
                  label: const Icon(Icons.chevron_right_rounded, size: 18),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$totalItems obra(s) encontrada(s)  ·  Página $currentPage de $totalPages',
            style: TextStyle(color: NixColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
