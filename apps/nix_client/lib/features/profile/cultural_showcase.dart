import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/cultural_item.dart';
import '../../core/security/local_image_helper.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

/// Seção de Personalização Cultural & Acervo do Card ID
/// (Filmes, Séries, Animes, Mangás, Livros, Vinis e Repositórios GitHub).
class CulturalShowcase extends StatefulWidget {
  const CulturalShowcase({super.key});

  @override
  State<CulturalShowcase> createState() => _CulturalShowcaseState();
}

class _CulturalShowcaseState extends State<CulturalShowcase> {
  CulturalCategory? _selectedFilter;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final allItems = nixState.userProfile.culturalItems;
    final queryLower = _searchQuery.trim().toLowerCase();

    final categoryItems = _selectedFilter == null
        ? allItems
        : allItems.where((i) => i.category == _selectedFilter).toList();
    final filteredItems = queryLower.isEmpty
        ? categoryItems
        : categoryItems.where((i) {
            return i.title.toLowerCase().contains(queryLower) ||
                i.creatorOrYear.toLowerCase().contains(queryLower) ||
                (i.language?.toLowerCase().contains(queryLower) ?? false);
          }).toList();

    final musicVinyls = filteredItems.where((i) => i.category == CulturalCategory.music).toList();
    final visualWorks = filteredItems.where((i) => i.category != CulturalCategory.music && i.category != CulturalCategory.github).toList();
    final githubRepos = filteredItems.where((i) => i.category == CulturalCategory.github).toList();

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
          // Cabeçalho da Personalização Cultural & Acervo
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.album_outlined, color: NixColors.textPrimary, size: 18),
                  const SizedBox(width: 8),
                  Flexible(child: Text(
                    'PASSAPORTE CULTURAL & ACERVO',
                    style: NixTokens.labelUppercase().copyWith(
                      color: NixColors.textPrimary,
                      letterSpacing: 1.2,
                    ),
                  )),
                ],
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: NixColors.textPrimary,
                  side: BorderSide(color: NixColors.surfaceBorderStrong),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: NixTokens.borderSm),
                ),
                onPressed: () => _showAddCulturalItemDialog(context),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Adicionar ao Acervo', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('cultural_catalog_search_input'),
                  controller: _searchCtrl,
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                    nixState.searchCulturalCatalog(value);
                  },
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Busca local FTS5 no acervo (título, autor, linguagem)...',
                    prefixIcon: Icon(Icons.search_rounded, size: 16, color: NixColors.textMuted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    filled: true,
                    fillColor: NixColors.surfaceCard,
                    border: OutlineInputBorder(
                      borderRadius: NixTokens.borderSm,
                      borderSide: BorderSide(color: NixColors.surfaceBorder),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (MediaQuery.sizeOf(context).width >= 560)
              Container(
                key: const Key('cultural_catalog_stage_badge'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: NixColors.surfaceCard,
                  borderRadius: NixTokens.borderSm,
                  border: Border.all(color: NixColors.surfaceBorder),
                ),
                child: Text(
                  'BUSCA LOCAL · OPT-IN REMOTO ISOLADO',
                  style: TextStyle(
                    color: NixColors.textSecondary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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

          // 1. DISCOS DE VINIL (Álbuns Musicais)
          if ((_selectedFilter == null || _selectedFilter == CulturalCategory.music) && musicVinyls.isNotEmpty) ...[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'MÚSICA · PRENSAGENS EM VINIL (${musicVinyls.length})',
                  style: NixTokens.labelUppercase(),
                ),
                Text(
                  'Clique para inspecionar capa',
                  style: TextStyle(color: NixColors.textMuted, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: musicVinyls.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _VinylRecordWidget(
                      item: item,
                      onTap: () => _openCoverModal(context, musicVinyls, musicVinyls.indexOf(item)),
                      onToggleVisibility: () => nixState.toggleItemCardIdVisibility(item.id),
                      onDelete: () => _confirmDeleteItem(context, item),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 22),
          ],

          // 2. REPOSITÓRIOS GITHUB SALVOS NO ACERVO
          if ((_selectedFilter == null || _selectedFilter == CulturalCategory.github) && githubRepos.isNotEmpty) ...[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'REPOSITÓRIOS GITHUB NO ACERVO (${githubRepos.length})',
                  style: NixTokens.labelUppercase(),
                ),
                Text(
                  'Sincronizado com aba GitHub Discovery',
                  style: TextStyle(color: NixColors.textMuted, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: githubRepos.map((repo) {
                return _GithubRepoAcervoCard(
                  item: repo,
                  onToggleVisibility: () => nixState.toggleItemCardIdVisibility(repo.id),
                  onDelete: () => nixState.removeCulturalItem(repo.id),
                );
              }).toList(),
            ),
            const SizedBox(height: 22),
          ],

          // 3. CAPAS VISUAIS: FILMES, SÉRIES, ANIMES, MANGÁS E LIVROS
          if (visualWorks.isNotEmpty) ...[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'OBRAS VISUAIS & LITERATURA (${visualWorks.length})',
                  style: NixTokens.labelUppercase(),
                ),
                Text(
                  'Formato pôster com rating',
                  style: TextStyle(color: NixColors.textMuted, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 14,
              children: visualWorks.map((item) {
                return _PosterCoverCard(
                  item: item,
                  onTap: () => _openCoverModal(context, visualWorks, visualWorks.indexOf(item)),
                  onToggleVisibility: () => nixState.toggleItemCardIdVisibility(item.id),
                  onDelete: () => _confirmDeleteItem(context, item),
                );
              }).toList(),
            ),
          ],

          if (allItems.isEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              decoration: BoxDecoration(
                color: NixColors.surfaceCard,
                borderRadius: NixTokens.borderMd,
                border: Border.all(color: NixColors.surfaceBorder),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.album_outlined, size: 44, color: NixColors.accentYellow.withOpacity(0.8)),
                  const SizedBox(height: 14),
                  Text(
                    'Seu Acervo Cultural está Vazio',
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Adicione suas prensagens em vinil, filmes, animes, séries, livros e mangás favoritos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showAddCulturalItemDialog(context),
                    icon: const Icon(Icons.add_rounded, size: 16, color: Colors.black),
                    label: const Text(
                      'Adicionar ao Acervo',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NixColors.accentYellow,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (filteredItems.isEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              child: Text(
                'Nenhuma obra nesta categoria do acervo.',
                style: TextStyle(color: NixColors.textMuted, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openCoverModal(BuildContext context, List<CulturalItem> items, int initialIndex) {
    showDialog(
      context: context,
      builder: (_) => _CoverGalleryModal(
        items: items,
        initialIndex: initialIndex,
        onEditItem: (item) {
          Navigator.of(context).pop();
          _showAddCulturalItemDialog(context, existing: item);
        },
      ),
    );
  }

  void _confirmDeleteItem(BuildContext context, CulturalItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover do Acervo?'),
        content: Text('Deseja retirar "${item.title}" do seu passaporte cultural?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: TextStyle(color: NixColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: NixColors.accentDanger,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              context.read<NixState>().removeCulturalItem(item.id);
              Navigator.pop(ctx);
            },
            child: const Text('Remover'),
          ),
        ],
      ),
    );
  }

  void _showAddCulturalItemDialog(BuildContext context, {CulturalItem? existing}) {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final creatorCtrl = TextEditingController(text: existing?.creatorOrYear ?? '');
    final ratingCtrl = TextEditingController(text: existing?.rating ?? '9.5');
    final imagePathCtrl = TextEditingController(text: existing?.localImagePath ?? '');
    CulturalCategory category = existing?.category ?? CulturalCategory.movies;
    double cropScale = existing?.cropScale ?? 1.0;
    String? previewPath = existing?.localImagePath;
    String? imgError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final accent = context.accentColor;
          return AlertDialog(
            title: Text(
              existing != null ? 'Editar Capa & Metadados' : 'Adicionar ao Acervo Cultural',
              style: TextStyle(color: NixColors.textPrimary, fontSize: 16),
            ),
            content: SizedBox(
              width: 430,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CATEGORIA', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: CulturalCategory.values.map((cat) {
                        final selected = category == cat;
                        return ChoiceChip(
                          label: Text(cat.label, style: const TextStyle(fontSize: 11.5)),
                          selected: selected,
                          selectedColor: accent,
                          backgroundColor: NixColors.surfaceCard,
                          labelStyle: TextStyle(
                            color: selected ? context.onAccentColor : NixColors.textSecondary,
                            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (_) => setModalState(() => category = cat),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Text('TÍTULO DA OBRA / REPOSITÓRIO', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        hintText: 'ex: Sousou no Frieren ou rust-anything',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('AUTOR / DIRETOR / LINGUAGEM', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    TextField(
                      controller: creatorCtrl,
                      decoration: const InputDecoration(
                        hintText: 'ex: 2024 · Kanehito Yamada ou Rust · org',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('AVALIAÇÃO PESSOAL OU STARS', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    TextField(
                      controller: ratingCtrl,
                      decoration: const InputDecoration(hintText: '9.5 ou 14k'),
                    ),
                    const SizedBox(height: 14),
                    Text('CAPA LOCAL (PNG / JPEG / WebP · EXIF SANITIZADO)', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: imagePathCtrl,
                            style: TextStyle(color: NixColors.textPrimary, fontSize: 12),
                            decoration: const InputDecoration(
                              hintText: '/caminho/capa.jpg',
                              isDense: true,
                            ),
                            onChanged: (v) => setModalState(() {
                              previewPath = v.trim();
                              imgError = null;
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await LocalImageHelper.pickImageNativeDesktop();
                            if (picked != null) {
                              imagePathCtrl.text = picked;
                              setModalState(() {
                                previewPath = picked;
                                imgError = null;
                              });
                            }
                          },
                          icon: const Icon(Icons.folder_open_rounded, size: 15),
                          label: const Text('Escolher', style: TextStyle(fontSize: 11.5)),
                        ),
                      ],
                    ),
                    if (previewPath != null &&
                        previewPath!.isNotEmpty &&
                        File(previewPath!).existsSync()) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            width: 54,
                            height: category == CulturalCategory.music ? 54 : 78,
                            decoration: BoxDecoration(
                              borderRadius: NixTokens.borderSm,
                              border: Border.all(color: accent, width: 1.3),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Transform.scale(
                              scale: cropScale,
                              child: Image.file(File(previewPath!), fit: BoxFit.cover),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Recorte / Zoom (${cropScale.toStringAsFixed(1)}x)',
                                  style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                                ),
                                Slider(
                                  value: cropScale,
                                  min: 1.0,
                                  max: 2.2,
                                  onChanged: (v) => setModalState(() => cropScale = v),
                                ),
                                TextButton(
                                  onPressed: () {
                                    imagePathCtrl.clear();
                                    setModalState(() {
                                      previewPath = null;
                                      cropScale = 1.0;
                                    });
                                  },
                                  child: Text(
                                    'Remover Imagem',
                                    style: TextStyle(color: NixColors.accentDanger, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (imgError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(imgError!, style: TextStyle(color: NixColors.accentDanger, fontSize: 11)),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancelar', style: TextStyle(color: NixColors.textMuted)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final t = titleCtrl.text.trim();
                  if (t.isEmpty) return;
                  String? storedPath;
                  final rawPath = imagePathCtrl.text.trim();
                  if (rawPath.isNotEmpty) {
                    if (!LocalImageHelper.isSupportedExtension(rawPath)) {
                      setModalState(() => imgError = 'Formato inválido. Use PNG, JPEG ou WebP.');
                      return;
                    }
                    storedPath = await LocalImageHelper.sanitizeAndStoreImage(rawPath);
                    if (!context.mounted || !ctx.mounted) return;
                    if (storedPath == null) {
                      setModalState(() => imgError = 'Imagem local não encontrada.');
                      return;
                    }
                  }
                  final words = t.split(' ').where((w) => w.isNotEmpty).toList();
                  final mono = words.length >= 2
                      ? '${words[0][0]}${words[1][0]}'.toUpperCase()
                      : t.substring(0, t.length >= 2 ? 2 : 1).toUpperCase();
                  final nixState = context.read<NixState>();
                  if (existing != null) {
                    nixState.updateCulturalItem(
                      existing.copyWith(
                        title: t,
                        creatorOrYear: creatorCtrl.text.trim().isEmpty
                            ? 'Acervo Pessoal'
                            : creatorCtrl.text.trim(),
                        category: category,
                        rating: ratingCtrl.text.trim().isEmpty ? '9.5' : ratingCtrl.text.trim(),
                        monogram: mono,
                        localImagePath: storedPath,
                        clearLocalImage: rawPath.isEmpty,
                        cropScale: cropScale,
                      ),
                    );
                  } else {
                    nixState.addCulturalItem(
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
                        localImagePath: storedPath,
                        cropScale: cropScale,
                        isPublicInCardId: true,
                      ),
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(existing != null ? 'Salvar Alterações' : 'Salvar no Acervo'),
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
    final accent = context.accentColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: NixTokens.motionFast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? accent : NixColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accent : NixColors.surfaceBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? context.onAccentColor : NixColors.textSecondary,
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Componente de Disco de Vinil para Álbuns Musicais.
class _VinylRecordWidget extends StatelessWidget {
  final CulturalItem item;
  final VoidCallback onTap;
  final VoidCallback onToggleVisibility;
  final VoidCallback onDelete;

  const _VinylRecordWidget({
    required this.item,
    required this.onTap,
    required this.onToggleVisibility,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onDelete,
      borderRadius: NixTokens.borderMd,
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: NixColors.surfaceCard,
          borderRadius: NixTokens.borderMd,
          border: Border.all(color: NixColors.surfaceBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Disco de Vinil
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
              clipBehavior: Clip.antiAlias,
              child: item.localImagePath != null && File(item.localImagePath!).existsSync()
                  ? Transform.scale(
                      scale: item.cropScale.clamp(1.0, 2.2),
                      child: Image.file(
                        File(item.localImagePath!),
                        fit: BoxFit.cover,
                        width: 72,
                        height: 72,
                      ),
                    )
                  : Center(
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white12, width: 0.8),
                        ),
                        child: Center(
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
              style: TextStyle(
                color: NixColors.textPrimary,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              item.creatorOrYear,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: NixColors.textMuted, fontSize: 9),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                InkWell(
                  onTap: onToggleVisibility,
                  child: Icon(
                    item.isPublicInCardId ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                    size: 13,
                    color: item.isPublicInCardId ? NixColors.textSecondary : NixColors.textDim,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Cartão para Repositório GitHub no Acervo
class _GithubRepoAcervoCard extends StatelessWidget {
  final CulturalItem item;
  final VoidCallback onToggleVisibility;
  final VoidCallback onDelete;

  const _GithubRepoAcervoCard({
    required this.item,
    required this.onToggleVisibility,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NixColors.surfaceCard,
        borderRadius: NixTokens.borderSm,
        border: Border.all(color: NixColors.surfaceBorderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.code_rounded, size: 14, color: context.accentTextColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(
                    color: NixColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Tooltip(
                message: item.isPublicInCardId ? 'Visível no Card ID' : 'Oculto no Card ID',
                child: InkWell(
                  onTap: onToggleVisibility,
                  child: Icon(
                    item.isPublicInCardId ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                    size: 14,
                    color: item.isPublicInCardId ? NixColors.textSecondary : NixColors.textDim,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.creatorOrYear,
            style: TextStyle(color: NixColors.textMuted, fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: NixColors.surfaceActive,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.language ?? 'Código',
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 9.5, fontWeight: FontWeight.bold),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                  const SizedBox(width: 3),
                  Text(item.rating, style: TextStyle(color: NixColors.textPrimary, fontSize: 10)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cartão de Pôster / Capa (Filmes, Séries, Animes, Mangás e Livros).
class _PosterCoverCard extends StatelessWidget {
  final CulturalItem item;
  final VoidCallback onTap;
  final VoidCallback onToggleVisibility;
  final VoidCallback onDelete;

  const _PosterCoverCard({
    required this.item,
    required this.onTap,
    required this.onToggleVisibility,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final shade = item.toneShade.clamp(18, 90);
    return InkWell(
      onTap: onTap,
      onLongPress: onDelete,
      borderRadius: NixTokens.borderMd,
      child: Container(
        width: 120,
        height: 175,
        decoration: BoxDecoration(
          borderRadius: NixTokens.borderMd,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.fromARGB(255, shade + 15, shade + 15, shade + 20),
              Color.fromARGB(255, shade - 8, shade - 8, shade - 4),
              const Color(0xFF08080A),
            ],
          ),
          border: Border.all(
            color: item.isFeatured ? Colors.white60 : NixColors.surfaceBorder,
            width: item.isFeatured ? 1.5 : 1.0,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black87,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            if (item.localImagePath != null && File(item.localImagePath!).existsSync())
              Positioned.fill(
                child: Transform.scale(
                  scale: item.cropScale.clamp(1.0, 2.2),
                  child: Image.file(
                    File(item.localImagePath!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            if (item.localImagePath == null || !File(item.localImagePath!).existsSync())
              Center(
                child: Text(
                  item.monogram,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.09),
                    fontSize: 54,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2,
                  ),
                ),
              ),
            // Rating no topo direito
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
                    color: Colors.white,
                    fontSize: 8.5,
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
                    color: Color(0xFFE0E2E8),
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            // Scrim inferior e Título/Autor sobre a capa
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 22, 8, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
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
                      style: const TextStyle(color: Color(0xFFB7BAC4), fontSize: 9.5),
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
}

/// Modal de Galeria de Capas estilo Cover-Flow.
class _CoverGalleryModal extends StatefulWidget {
  final List<CulturalItem> items;
  final int initialIndex;
  final ValueChanged<CulturalItem>? onEditItem;

  const _CoverGalleryModal({
    required this.items,
    required this.initialIndex,
    this.onEditItem,
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
          Positioned(
            top: 24,
            left: 28,
            child: Text(
              'Capa · ${current.title}',
              style: const TextStyle(color: Color(0xFFD0D4DE), fontSize: 13),
            ),
          ),
          Positioned(
            top: 18,
            right: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onEditItem != null) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentColor,
                      foregroundColor: context.onAccentColor,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => widget.onEditItem!(current),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('Editar Capa', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF1F2229),
                    side: const BorderSide(color: Colors.white24),
                  ),
                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

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
                              color: Colors.white,
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
                        style: const TextStyle(color: Color(0xFFB7BAC4), fontSize: 12.5),
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

          Positioned(
            left: 28,
            child: IconButton(
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF1F2229),
                side: const BorderSide(color: Colors.white24),
              ),
              icon: const Icon(Icons.chevron_left, color: Colors.white),
              onPressed: _prev,
            ),
          ),

          Positioned(
            right: 28,
            child: IconButton(
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF1F2229),
                side: const BorderSide(color: Colors.white24),
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
