import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/cultural_item.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

/// Seção de Personalização Cultural do Card ID (Filmes, Séries, Animes, Mangás, Livros e Vinis).
class CulturalShowcase extends StatefulWidget {
  const CulturalShowcase({super.key});

  @override
  State<CulturalShowcase> createState() => _CulturalShowcaseState();
}

class _CulturalShowcaseState extends State<CulturalShowcase> {
  CulturalCategory? _selectedFilter;

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final allItems = nixState.userProfile.culturalItems;

    final filteredItems = _selectedFilter == null
        ? allItems
        : allItems.where((i) => i.category == _selectedFilter).toList();

    final musicVinyls = allItems.where((i) => i.category == CulturalCategory.music).toList();
    final visualWorks = filteredItems.where((i) => i.category != CulturalCategory.music).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NixColors.surfaceSidebar,
        borderRadius: NixTokens.borderLg,
        border: Border.all(color: NixColors.surfaceBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho da Personalização Cultural
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.album_outlined, color: NixColors.textPrimary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'PASSAPORTE CULTURAL & ACERVO',
                    style: NixTokens.labelUppercase().copyWith(
                      color: NixColors.textPrimary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: NixColors.textPrimary,
                  side: const BorderSide(color: NixColors.surfaceBorderStrong),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: NixTokens.borderSm),
                ),
                onPressed: () => _showAddCulturalItemDialog(context),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Adicionar Obra', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Pílulas de Filtro de Categoria
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'Todos (${allItems.length})',
                  isSelected: _selectedFilter == null,
                  onTap: () => setState(() => _selectedFilter = null),
                ),
                ...CulturalCategory.values.map((cat) {
                  final count = allItems.where((i) => i.category == cat).length;
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _FilterChip(
                      label: '${cat.label} ($count)',
                      isSelected: _selectedFilter == cat,
                      onTap: () => setState(() => _selectedFilter = cat),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Seção de Discos de Vinil (Álbuns Musicais)
          if ((_selectedFilter == null || _selectedFilter == CulturalCategory.music) &&
              musicVinyls.isNotEmpty) ...[
            Row(
              children: [
                Text('MÚSICA · PRENSAGENS EM VINIL (${musicVinyls.length})',
                    style: NixTokens.labelUppercase()),
                const Spacer(),
                const Text('Clique para inspecionar capa',
                    style: TextStyle(color: NixColors.textDim, fontSize: 10)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 126,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: musicVinyls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, idx) {
                  final vinyl = musicVinyls[idx];
                  return _VinylRecordWidget(
                    item: vinyl,
                    onTap: () => _openCoverShowcaseModal(context, allItems, vinyl),
                    onDelete: () => nixState.removeCulturalItem(vinyl.id),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Grade de Pôsteres & Capas (Filmes, Séries, Animes, Mangás, Livros)
          if (visualWorks.isNotEmpty) ...[
            Text(
              _selectedFilter == null
                  ? 'OBRAS EM DESTAQUE (${visualWorks.length})'
                  : '${_selectedFilter!.label.toUpperCase()} (${visualWorks.length})',
              style: NixTokens.labelUppercase(),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: visualWorks.map((item) {
                return _PosterCoverCard(
                  item: item,
                  onTap: () => _openCoverShowcaseModal(context, allItems, item),
                  onDelete: () => nixState.removeCulturalItem(item.id),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  void _openCoverShowcaseModal(
    BuildContext context,
    List<CulturalItem> items,
    CulturalItem initial,
  ) {
    final initialIdx = items.indexWhere((i) => i.id == initial.id);
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.92),
      builder: (_) => _CoverGalleryModal(
        items: items,
        initialIndex: initialIdx >= 0 ? initialIdx : 0,
      ),
    );
  }

  void _showAddCulturalItemDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final creatorCtrl = TextEditingController();
    final ratingCtrl = TextEditingController(text: '9.5');
    CulturalCategory category = CulturalCategory.movies;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return AlertDialog(
            title: const Text('Adicionar Obra ao Passaporte Cultural'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CATEGORIA', style: NixTokens.labelUppercase()),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: CulturalCategory.values.map((cat) {
                      final selected = category == cat;
                      return ChoiceChip(
                        label: Text(cat.label, style: const TextStyle(fontSize: 12)),
                        selected: selected,
                        selectedColor: NixColors.textPrimary,
                        backgroundColor: NixColors.surfaceCard,
                        labelStyle: TextStyle(
                          color: selected ? Colors.black : NixColors.textSecondary,
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (_) => setModalState(() => category = cat),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text('TÍTULO DA OBRA / ÁLBUM', style: NixTokens.labelUppercase()),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      hintText: 'ex: Sousou no Frieren ~Zensou~',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('AUTOR / DIRETOR / ANO', style: NixTokens.labelUppercase()),
                  const SizedBox(height: 6),
                  TextField(
                    controller: creatorCtrl,
                    decoration: const InputDecoration(
                      hintText: 'ex: 2024 · Kanehito Yamada',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('AVALIAÇÃO PESSOAL', style: NixTokens.labelUppercase()),
                  const SizedBox(height: 6),
                  TextField(
                    controller: ratingCtrl,
                    decoration: const InputDecoration(hintText: '9.5'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: NixColors.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: NixColors.textPrimary,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  final t = titleCtrl.text.trim();
                  if (t.isNotEmpty) {
                    final words = t.split(' ').where((w) => w.isNotEmpty).toList();
                    final mono = words.length >= 2
                        ? '${words[0][0]}${words[1][0]}'.toUpperCase()
                        : t.substring(0, t.length >= 2 ? 2 : 1).toUpperCase();
                    context.read<NixState>().addCulturalItem(
                          CulturalItem(
                            id: 'cult_${DateTime.now().millisecondsSinceEpoch}',
                            title: t,
                            creatorOrYear: creatorCtrl.text.trim().isEmpty
                                ? 'Acervo Pessoal'
                                : creatorCtrl.text.trim(),
                            category: category,
                            rating: ratingCtrl.text.trim().isEmpty ? '9.5' : ratingCtrl.text.trim(),
                            monogram: mono,
                            toneShade: 55,
                          ),
                        );
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Salvar no Card ID', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: NixTokens.motionFast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? NixColors.textPrimary : NixColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? NixColors.textPrimary : NixColors.surfaceBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : NixColors.textSecondary,
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Componente de Disco de Vinil para Álbuns Musicais (Inspirado na Imagem 3).
class _VinylRecordWidget extends StatelessWidget {
  final CulturalItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _VinylRecordWidget({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onDelete,
      borderRadius: NixTokens.borderMd,
      child: Container(
        width: 115,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: NixColors.surfaceCard,
          borderRadius: NixTokens.borderMd,
          border: Border.all(color: NixColors.surfaceBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Disco de Vinil com sulcos concêntricos e selo central
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(
                  colors: [
                    Color(0xFF0A0A0A),
                    Color(0xFF28282C),
                    Color(0xFF0A0A0A),
                    Color(0xFF28282C),
                    Color(0xFF0A0A0A),
                  ],
                ),
                border: Border.all(color: NixColors.surfaceBorderStrong, width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 3)),
                ],
              ),
              child: Center(
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white12, width: 0.8),
                  ),
                  child: Center(
                    // Selo Central do Álbum
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.fromARGB(255, item.toneShade, item.toneShade, item.toneShade),
                        border: Border.all(color: Colors.white38, width: 1),
                      ),
                      child: Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: NixColors.textPrimary,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              item.creatorOrYear,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: NixColors.textMuted, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cartão de Pôster / Capa (Filmes, Séries, Animes, Mangás e Livros).
class _PosterCoverCard extends StatelessWidget {
  final CulturalItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PosterCoverCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final shade = item.toneShade.clamp(18, 90);
    return InkWell(
      onTap: onTap,
      onLongPress: onDelete,
      borderRadius: NixTokens.borderSm,
      child: Container(
        width: 118,
        height: 164,
        decoration: BoxDecoration(
          borderRadius: NixTokens.borderSm,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.fromARGB(255, shade + 16, shade + 16, shade + 18),
              Color.fromARGB(255, shade ~/ 2, shade ~/ 2, shade ~/ 2 + 2),
              const Color(0xFF070708),
            ],
          ),
          border: Border.all(color: NixColors.surfaceBorderStrong, width: 1),
        ),
        child: Stack(
          children: [
            // Monograma tipográfico de fundo
            Positioned(
              right: -6,
              top: 12,
              child: Text(
                item.monogram,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.07),
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                ),
              ),
            ),
            // Badge de nota no topo direito
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white24, width: 0.5),
                ),
                child: Text(
                  '${item.rating} ★',
                  style: const TextStyle(
                    color: NixColors.textPrimary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // Categoria no topo esquerdo
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.category.label.toUpperCase(),
                  style: const TextStyle(
                    color: NixColors.textSecondary,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            // Título e Autor na base
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.creatorOrYear,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: NixColors.textMuted, fontSize: 9.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal de Galeria de Capas estilo Cover-Flow (Inspirado na Imagem 1 — Frieren).
class _CoverGalleryModal extends StatefulWidget {
  final List<CulturalItem> items;
  final int initialIndex;

  const _CoverGalleryModal({
    required this.items,
    required this.initialIndex,
  });

  @override
  State<_CoverGalleryModal> createState() => _CoverGalleryModalState();
}

class _CoverGalleryModalState extends State<_CoverGalleryModal> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _prev() {
    setState(() {
      _currentIndex = (_currentIndex - 1 + widget.items.length) % widget.items.length;
    });
  }

  void _next() {
    setState(() {
      _currentIndex = (_currentIndex + 1) % widget.items.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.items[_currentIndex];

    return Dialog.fullscreen(
      backgroundColor: Colors.black.withOpacity(0.94),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Cabeçalho superior esquerdo e botão fechar (igual à Imagem 1)
          Positioned(
            top: 24,
            left: 28,
            child: Text(
              'Capa · ${current.title}',
              style: const TextStyle(color: NixColors.textSecondary, fontSize: 13),
            ),
          ),
          Positioned(
            top: 18,
            right: 24,
            child: IconButton(
              style: IconButton.styleFrom(
                backgroundColor: NixColors.surfaceCard,
                side: const BorderSide(color: NixColors.surfaceBorderStrong),
              ),
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Capa Central em Destaque Elevado
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: NixTokens.motionMedium,
                child: Container(
                  key: ValueKey(current.id),
                  width: 280,
                  height: 390,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: NixTokens.amoledMetalGradient,
                    borderRadius: NixTokens.borderMd,
                    border: Border.all(color: NixColors.metalEdgeHighlight, width: 1.5),
                    boxShadow: NixTokens.elevationModal,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            current.category.label.toUpperCase(),
                            style: NixTokens.labelUppercase(),
                          ),
                          Text(
                            '${current.rating} ★',
                            style: const TextStyle(
                              color: NixColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Center(
                        child: Text(
                          current.monogram,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.18),
                            fontSize: 96,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -4,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        current.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${current.category.label} · ${current.creatorOrYear}',
                        style: const TextStyle(color: NixColors.textSecondary, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                current.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              // Indicadores de página (bolinhas)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.items.length, (i) {
                  final active = i == _currentIndex;
                  return Container(
                    width: active ? 8 : 6,
                    height: active ? 8 : 6,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? Colors.white : Colors.white24,
                    ),
                  );
                }),
              ),
            ],
          ),

          // Botão Anterior (<)
          Positioned(
            left: 28,
            child: IconButton(
              style: IconButton.styleFrom(
                backgroundColor: NixColors.surfaceCard,
                side: const BorderSide(color: NixColors.surfaceBorderStrong),
              ),
              icon: const Icon(Icons.chevron_left, color: Colors.white),
              onPressed: _prev,
            ),
          ),

          // Botão Próximo (>)
          Positioned(
            right: 28,
            child: IconButton(
              style: IconButton.styleFrom(
                backgroundColor: NixColors.surfaceCard,
                side: const BorderSide(color: NixColors.surfaceBorderStrong),
              ),
              icon: const Icon(Icons.chevron_right, color: Colors.white),
              onPressed: _next,
            ),
          ),
        ],
      ),
    );
  }
}
