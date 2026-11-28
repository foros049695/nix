import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/media/catalog_database.dart';
import '../../core/models/cultural_item.dart';
import '../../core/models/cultural_tracking.dart';
import '../../core/security/file_picker_adapter.dart';
import '../../core/security/local_image_helper.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../design/nix_glass.dart';
import '../design/nix_surfaces.dart';
import 'cultural_catalog_picker.dart';
import 'cultural_cover_art.dart';
import 'collection_import_dialog.dart';
import 'cover_enrichment_dialog.dart';
import 'cultural_filters_and_pagination.dart';
import 'book_manga_manager_sheet.dart';
import 'cultural_motion_cover_card.dart';
import '../media/cultural_work_sheet.dart';

class CulturalShowcase extends StatefulWidget {
  const CulturalShowcase({super.key});

  @override
  State<CulturalShowcase> createState() => _CulturalShowcaseState();
}

class _CulturalShowcaseState extends State<CulturalShowcase> {
  String _query = '';
  CulturalFilterOptions _filterOptions = const CulturalFilterOptions();
  bool _isFilterPanelOpen = false;
  int _currentPage = 1;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final items = state.userProfile.culturalItems;

    // Aplica busca textual e filtros avançados (Seção 1 & 1.1)
    final allFiltered = items.where((item) {
      final matchesText = _query.isEmpty ||
          [
            item.title,
            item.originalTitle ?? '',
            item.creatorOrYear,
            item.creator ?? '',
            item.language ?? '',
            item.tracking.collection,
            ...item.tracking.tags,
            ...item.genres,
          ].any((text) => text.toLowerCase().contains(_query));

      return matchesText && _filterOptions.matches(item);
    }).toList();

    return NixGlass(
      key: const Key('cultural_glass'),
      radius: 26,
      mirror: true,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Acervo Cultural', style: NixTokens.headingMedium()),
            const SizedBox(height: 12),
            Wrap(spacing: 7, runSpacing: 6, children: [
              FilledButton.icon(
                key: const Key('cultural_search_catalog'),
                onPressed: _importCatalogWork,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Buscar no catálogo'),
              ),
              OutlinedButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Adicionar ao Acervo'),
              ),
              OutlinedButton.icon(
                key: const Key('import_collection_button'),
                onPressed: () => CollectionImportDialog.show(context),
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('Importar coleção'),
              ),
              OutlinedButton.icon(
                key: const Key('enrich_covers_button'),
                onPressed: () => CoverEnrichmentDialog.show(context),
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: const Text('Buscar capas'),
              ),
            ]),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 15),
              // Barra de pesquisa com botão unificado de Filtrar
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('cultural_catalog_search_input'),
                      onChanged: (query) => setState(() {
                        _query = query.trim().toLowerCase();
                        _currentPage = 1;
                      }),
                      decoration: InputDecoration(
                        hintText: 'Pesquisar obras no acervo...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Badge.count(
                    count: _filterOptions.activeFiltersCount,
                    isLabelVisible: _filterOptions.activeFiltersCount > 0,
                    backgroundColor: Colors.cyanAccent.shade700,
                    textColor: Colors.black,
                    child: OutlinedButton.icon(
                      key: const Key('toggle_cultural_filters_button'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                        foregroundColor: _isFilterPanelOpen || _filterOptions.activeFiltersCount > 0
                            ? Colors.cyanAccent
                            : Colors.white,
                        side: BorderSide(
                          color: _isFilterPanelOpen || _filterOptions.activeFiltersCount > 0
                              ? Colors.cyanAccent
                              : Colors.white24,
                        ),
                      ),
                      onPressed: () => setState(() => _isFilterPanelOpen = !_isFilterPanelOpen),
                      icon: Icon(
                        _isFilterPanelOpen ? Icons.filter_list_off_rounded : Icons.filter_list_rounded,
                        size: 18,
                      ),
                      label: const Text('Filtrar', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              // Painel expansível de checkboxes de filtro
              if (_isFilterPanelOpen)
                CulturalFilterPanel(
                  initialOptions: _filterOptions,
                  onApply: (newOpts) => setState(() {
                    _filterOptions = newOpts;
                    _currentPage = 1;
                  }),
                  onClose: () => setState(() => _isFilterPanelOpen = false),
                ),
              // Indicador discreto de filtros ativos
              if (_filterOptions.activeFiltersCount > 0 && !_isFilterPanelOpen)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '${_filterOptions.activeFiltersCount} filtro(s) ativo(s)',
                          style: TextStyle(color: Colors.cyanAccent.shade200, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => setState(() {
                          _filterOptions = const CulturalFilterOptions();
                          _currentPage = 1;
                        }),
                        child: const Text('Limpar filtros',
                            style: TextStyle(color: Colors.redAccent, fontSize: 11.5, decoration: TextDecoration.underline)),
                      ),
                    ],
                  ),
                ),
            ],
            if (allFiltered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 26),
                child: Text(
                  items.isEmpty
                      ? 'Seu acervo está vazio.'
                      : 'Nenhuma obra neste filtro.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.nixScheme.textSecondary),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final cols = ((box.maxWidth + 12) / 116).floor().clamp(2, 6);
                    final width = ((box.maxWidth - (cols - 1) * 12) / cols).clamp(1.0, 146.0);
                    final pageSize = cols * 4; // Quatro fileiras de obras por página (Seção 2)
                    final totalPages = (allFiltered.length / pageSize).ceil().clamp(1, 999999);
                    final safePage = _currentPage.clamp(1, totalPages);
                    final startIndex = (safePage - 1) * pageSize;
                    final endIndex = (startIndex + pageSize).clamp(0, allFiltered.length);
                    final pageItems = allFiltered.sublist(startIndex, endIndex);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final (index, item) in pageItems.indexed)
                              SizedBox(
                                width: item.isGithubRepo ? 190.0 : width,
                                child: item.isGithubRepo
                                    ? _GithubRepoAcervoCard(
                                        item: item,
                                        onToggleVisibility: () =>
                                            state.toggleItemCardIdVisibility(item.id),
                                        onDelete: () => _confirmDelete(item),
                                      )
                                    : _buildCoverCard(context, state, item, pageItems, index, width),
                              ),
                          ],
                        ),
                        CulturalPaginationControls(
                          currentPage: safePage,
                          totalPages: totalPages,
                          totalItems: allFiltered.length,
                          pageSize: pageSize,
                          onPageChanged: (newPage) => setState(() => _currentPage = newPage),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverCard(BuildContext context, NixState state, CulturalItem item,
      List<CulturalItem> pageItems, int index, double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CulturalMotionCoverCard(
          item: item,
          width: width,
          index: index,
          onTap: () {
            if (MediaQuery.sizeOf(context).width >= 900) {
              state.openWorkDetail(item);
            } else {
              CulturalWorkSheet.showModal(context, item: item);
            }
          },
          onLongPress: () => _confirmDelete(item),
        ),
        const SizedBox(height: 5),
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        if (item.tracking.stage case final stage?)
          Text(
            item.category.trackingLabel(stage),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.cyanAccent.shade200,
                  fontSize: 10,
                ),
          ),
        if (item.missingVolumesSummary.isNotEmpty && item.missingVolumes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              item.missingVolumesSummary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFFBBF24),
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (item.tracking.fraction case final fraction?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: LinearProgressIndicator(
              value: fraction,
              semanticsLabel: 'Progresso de ${item.title}',
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                item.creatorOrYear,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: context.nixScheme.textSecondary,
                ),
              ),
            ),
            if (item.isBookOrManga && width >= 135)
              IconButton(
                tooltip: 'Gerenciar volumes e ComicInfo (BookManager)',
                visualDensity: VisualDensity.compact,
                iconSize: 15,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 38),
                onPressed: () => BookMangaManagerSheet.showModal(context, item: item),
                icon: const Icon(Icons.auto_stories_outlined, color: Color(0xFFC084FC)),
              ),
            IconButton(
              tooltip: item.isPublicInCardId
                  ? 'Ocultar do perfil'
                  : 'Mostrar no perfil',
              visualDensity: VisualDensity.compact,
              iconSize: 15,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 38),
              onPressed: () => state.toggleItemCardIdVisibility(item.id),
              icon: Icon(item.isPublicInCardId
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
            ),
            IconButton(
              tooltip: 'Remover do Acervo',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 38),
              onPressed: () => _confirmDelete(item),
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _importCatalogWork() async {
    final work = await pickCulturalCatalogWork(context);
    if (!mounted || work == null) return;
    final draft = culturalItemFromCatalog(work);
    final existing = context
        .read<NixState>()
        .userProfile
        .culturalItems
        .where((item) => item.id == draft.id)
        .firstOrNull;
    await _edit(existing: existing, draft: draft, work: work);
  }

  Future<void> _edit(
          {CulturalItem? existing, CulturalItem? draft, CatalogWork? work}) =>
      showDialog<void>(
        context: context,
        builder: (_) =>
            _CulturalItemEditor(existing: existing, draft: draft, work: work),
      );

  // ignore: unused_element
  Future<void> _showGallery(List<CulturalItem> items, int index) async {
    final edit = await showDialog<CulturalItem>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => _CoverGallery(items: items, initialIndex: index),
    );
    if (mounted && edit != null) await _edit(existing: edit);
  }

  Future<void> _confirmDelete(CulturalItem item) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: const Text('Remover do Acervo?'),
              content: Text(
                  'Deseja retirar “${item.title}” do seu Acervo Cultural?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('Remover')),
              ],
            ));
    if (mounted && confirmed == true)
      context.read<NixState>().removeCulturalItem(item.id);
  }
}

class _CulturalItemEditor extends StatefulWidget {
  const _CulturalItemEditor({this.existing, this.draft, this.work});

  final CulturalItem? existing;
  final CulturalItem? draft;
  final CatalogWork? work;

  @override
  State<_CulturalItemEditor> createState() => _CulturalItemEditorState();
}

class _CulturalItemEditorState extends State<_CulturalItemEditor> {
  CulturalItem? get _base => widget.existing ?? widget.draft;
  late final _title = TextEditingController(text: _base?.title);
  late final _creator = TextEditingController(text: _base?.creatorOrYear);
  late final _rating = TextEditingController(text: _base?.rating ?? '9.5');
  late final _path = TextEditingController(text: _base?.localImagePath);
  late final _current = TextEditingController(text: _base?.tracking.current?.toString());
  late final _total = TextEditingController(text: _base?.tracking.total?.toString());
  late final _sequence = TextEditingController(text: _base?.tracking.seasonOrVolume?.toString());
  late final _review = TextEditingController(text: _base?.tracking.review);
  late final _notes = TextEditingController(text: _base?.tracking.privateNotes);
  late final _tags = TextEditingController(text: _base?.tracking.tags.join(', '));
  late final _collection = TextEditingController(text: _base?.tracking.collection);
  late CulturalStage? _stage = _base?.tracking.stage;
  late bool _favorite = _base?.tracking.favorite ?? false;
  late var _category = _base?.category ?? CulturalCategory.movies;
  late var _crop = _base?.cropScale.clamp(1.0, 2.2) ?? 1.0;
  late final _thumbnail =
      LocalImageHelper.readCatalogThumbnail(widget.work?.coverThumb);
  bool _saving = false;
  bool _discardThumbnail = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _creator.dispose();
    _rating.dispose();
    _path.dispose();
    _current.dispose();
    _total.dispose();
    _sequence.dispose();
    _review.dispose();
    _notes.dispose();
    _tags.dispose();
    _collection.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    String? path;
    try {
      path = await LocalImageHelper.pickImageNativeDesktop();
    } on FilePickerUnavailableException {
      if (!mounted) return;
      final selected =
          await CrossPlatformFilePickerAdapter.showPortableFileChooserDialog(
        context,
        title: 'Escolher capa local',
        allowedExtensions: LocalImageHelper.supportedExtensions,
      );
      path = selected.firstOrNull;
    }
    if (!mounted || path == null) return;
    setState(() {
      _path.text = path!;
      _error = null;
    });
  }

  CulturalTracking _readTracking() {
    int? parse(TextEditingController field, {int minimum = 0}) {
      final text = field.text.trim();
      if (text.isEmpty) return null;
      final value = int.tryParse(text);
      if (value == null || value < minimum || value > 1000000) {
        throw const FormatException('Informe números válidos nos campos de progresso.');
      }
      return value;
    }
    final current = _category.progressUnit == null ? null : parse(_current);
    final total = _category.progressUnit == null ? null : parse(_total, minimum: 1);
    if (current != null && total != null && current > total) {
      throw const FormatException('O progresso não pode ultrapassar o total.');
    }
    return CulturalTracking(
      stage: _stage,
      current: current,
      total: total,
      seasonOrVolume: _category.sequenceLabel == null ? null : parse(_sequence, minimum: 1),
      favorite: _favorite,
      tags: _tags.text.split(',').map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty).toSet().toList(),
      collection: _collection.text.trim(),
      review: _review.text.trim(),
      privateNotes: _notes.text.trim(),
    );
  }

  Widget _trackingFields() {
    Widget number(String label, TextEditingController controller) => TextField(
      controller: controller,
      enabled: !_saving,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
    );
    final unit = _category.progressUnit;
    return ExpansionTile(
      title: const Text('Progresso e avaliação'),
      tilePadding: EdgeInsets.zero,
      children: [
        DropdownButtonFormField<CulturalStage>(
          isExpanded: true,
          value: _stage,
          decoration: const InputDecoration(labelText: 'Status'),
          items: [
            const DropdownMenuItem(child: Text('Sem status')),
            for (final stage in CulturalStage.values)
              DropdownMenuItem(value: stage, child: Text(_category.trackingLabel(stage))),
          ],
          onChanged: _saving ? null : (stage) => setState(() => _stage = stage),
        ),
        if (unit != null) ...[
          if (_category.sequenceLabel case final sequence?)
            number(sequence, _sequence),
          Row(children: [
            Expanded(child: number('Concluído ($unit)', _current)),
            const SizedBox(width: 12),
            Expanded(child: number('Total', _total)),
          ]),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Favorito'),
          value: _favorite,
          onChanged: _saving ? null : (value) => setState(() => _favorite = value),
        ),
        TextField(controller: _collection, enabled: !_saving, maxLength: 60,
          decoration: const InputDecoration(labelText: 'Coleção')),
        TextField(controller: _tags, enabled: !_saving, maxLength: 240,
          decoration: const InputDecoration(labelText: 'Tags separadas por vírgula')),
        TextField(controller: _review, enabled: !_saving, maxLength: 2000, maxLines: 3,
          decoration: const InputDecoration(labelText: 'Resenha privada')),
        TextField(controller: _notes, enabled: !_saving, maxLength: 2000, maxLines: 3,
          decoration: const InputDecoration(labelText: 'Observações privadas')),
      ],
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (_saving) return;
    if (title.isEmpty) {
      setState(() => _error = 'Informe um título.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final route = ModalRoute.of(context);
    final state = context.read<NixState>();
    final rawPath = _path.text.trim();
    try {
      final tracking = _readTracking();
      String? path;
      if (rawPath.isNotEmpty) {
        path = rawPath == widget.existing?.localImagePath
            ? rawPath
            : await LocalImageHelper.sanitizeAndStoreImage(rawPath);
        if (path == null)
          throw const FormatException(
              'Imagem local inválida ou não encontrada.');
      } else if (!_discardThumbnail && _thumbnail != null) {
        path = await LocalImageHelper.storeCatalogThumbnail(
            widget.work?.coverThumb);
      }
      if (!mounted || route?.isCurrent == false) return;
      final item = (_base ??
              CulturalItem(
                id: 'cult_${DateTime.now().microsecondsSinceEpoch}',
                title: title,
                creatorOrYear: '',
                category: _category,
                monogram: '',
                isPublicInCardId: false,
              ))
          .copyWith(
        title: title,
        creatorOrYear: _creator.text.trim().isEmpty
            ? 'Acervo Pessoal'
            : _creator.text.trim(),
        category: _category,
        rating: _rating.text.trim().isEmpty ? null : _rating.text.trim(),
        monogram: title.characters.take(2).toString().toUpperCase(),
        localImagePath: path,
        clearLocalImage: path == null,
        cropScale: _crop,
        tracking: tracking,
      );
      await state.saveCulturalItem(item);
      if (mounted && route?.isCurrent != false) Navigator.of(context).pop();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FileSystemException {
      if (mounted) setState(() => _error = 'Não foi possível salvar a capa.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível salvar o item no cofre.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _base?.copyWith(
      category: _category,
      localImagePath: _path.text.trim(),
      cropScale: _crop,
      clearLocalImage: _path.text.trim().isEmpty,
    );
    final hasPreview = _path.text.trim().isNotEmpty ||
        (!_discardThumbnail && _thumbnail != null) ||
        preview?.coverMotif != null;
    return AlertDialog(
      scrollable: true,
      title: Text(widget.existing == null
          ? 'Adicionar ao Acervo Cultural'
          : 'Editar capa e metadados'),
      content: SizedBox(
          width: 440,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 5, children: [
              for (final category in CulturalCategory.values)
                ChoiceChip(
                  label: Text(category.label),
                  selected: _category == category,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _category = category),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Título da obra')),
            const SizedBox(height: 9),
            TextField(
                controller: _creator,
                decoration:
                    const InputDecoration(labelText: 'Autor, artista ou ano')),
            const SizedBox(height: 9),
            TextField(
                controller: _rating,
                decoration:
                    const InputDecoration(labelText: 'Avaliação pessoal')),
            const SizedBox(height: 14),
            _trackingFields(),
            if (_path.text.isNotEmpty)
              Text(LocalImageHelper.getFileName(_path.text),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 7),
            OutlinedButton.icon(
                onPressed: _saving ? null : _pickImage,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Escolher imagem')),
            if (hasPreview) ...[
              const SizedBox(height: 10),
              if (_path.text.trim().isEmpty &&
                  !_discardThumbnail &&
                  _thumbnail != null)
                Image.memory(_thumbnail!.bytes,
                    width: 68,
                    height: 90,
                    cacheWidth: 136,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        CulturalCoverArt(item: preview!, width: 68))
              else
                CulturalCoverArt(
                    item: preview ??
                        CulturalItem(
                          id: '',
                          title: '',
                          creatorOrYear: '',
                          category: _category,
                          monogram: '',
                          localImagePath: _path.text.trim(),
                          cropScale: _crop,
                        ),
                    width: 68),
              if (_path.text.trim().isNotEmpty ||
                  (!_discardThumbnail && _thumbnail != null)) ...[
                Slider(
                    value: _crop,
                    min: 1,
                    max: 2.2,
                    onChanged: (value) => setState(() => _crop = value)),
                TextButton(
                    onPressed: () => setState(() {
                          _path.clear();
                          _crop = 1;
                          _discardThumbnail = true;
                        }),
                    child: const Text('Remover imagem')),
              ],
            ],
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ])),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(widget.existing == null
                ? 'Salvar no Acervo'
                : 'Salvar alterações')),
      ],
    );
  }
}

class _CoverGallery extends StatefulWidget {
  const _CoverGallery({required this.items, required this.initialIndex});
  final List<CulturalItem> items;
  final int initialIndex;

  @override
  State<_CoverGallery> createState() => _CoverGalleryState();
}

class _CoverGalleryState extends State<_CoverGallery> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    final reduced = MediaQuery.disableAnimationsOf(context) ||
        context.watch<NixState>().settings.reducedMotion;
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: NixGlass(
          mirror: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  if (widget.items.length > 1)
                    IconButton(
                        tooltip: 'Capa anterior',
                        onPressed: () => setState(
                            () => _index = (_index - 1) % widget.items.length),
                        icon: const Icon(Icons.chevron_left)),
                  Expanded(
                      child: Center(
                          child: LayoutBuilder(
                              builder: (_, box) => AnimatedSwitcher(
                                    duration: reduced
                                        ? Duration.zero
                                        : NixTokens.motionMedium,
                                    child: NixMotionCard(
                                        key: ValueKey(item.id),
                                        child: CulturalCoverArt(
                                            item: item,
                                            width: box.maxWidth.clamp(1, 240))),
                                  )))),
                  if (widget.items.length > 1)
                    IconButton(
                        tooltip: 'Próxima capa',
                        onPressed: () => setState(
                            () => _index = (_index + 1) % widget.items.length),
                        icon: const Icon(Icons.chevron_right)),
                ]),
                const SizedBox(height: 16),
                Text(item.title,
                    style: NixTokens.headingMedium(),
                    textAlign: TextAlign.center),
                const SizedBox(height: 3),
                Text('${item.creatorOrYear} · ${item.rating} ★',
                    textAlign: TextAlign.center),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, item),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Editar capa')),
              ]),
            )),
          )),
    );
  }
}

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
              Icon(Icons.code_rounded,
                  size: 14, color: context.accentTextColor),
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
                message: item.isPublicInCardId
                    ? 'Visível no perfil público'
                    : 'Oculto no perfil público',
                child: InkWell(
                  onTap: onToggleVisibility,
                  child: Icon(
                    item.isPublicInCardId
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 14,
                    color: item.isPublicInCardId
                        ? NixColors.textSecondary
                        : NixColors.textDim,
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
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
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
                    style: TextStyle(
                        color: NixColors.textPrimary,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                    const SizedBox(width: 3),
                    Text(item.rating,
                        style: TextStyle(
                            color: NixColors.textPrimary, fontSize: 10)),
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

/// Cartão de Pôster / Capa (Filmes, Séries, Animes, Mangás e Livros).
