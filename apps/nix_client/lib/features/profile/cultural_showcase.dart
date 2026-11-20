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

class CulturalShowcase extends StatefulWidget {
  const CulturalShowcase({super.key});

  @override
  State<CulturalShowcase> createState() => _CulturalShowcaseState();
}

class _CulturalShowcaseState extends State<CulturalShowcase> {
  CulturalCategory? _category;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final items = state.userProfile.culturalItems;
    final filtered = items
        .where((item) =>
            (_category == null || item.category == _category) &&
            [item.title, item.creatorOrYear, item.language ?? '',
              item.tracking.collection, ...item.tracking.tags]
                .any((text) => text.toLowerCase().contains(_query)))
        .toList();
    final vinyls = filtered.where((item) => item.isVinyl).toList();
    final books = filtered
        .where((item) =>
            item.category == CulturalCategory.books ||
            item.category == CulturalCategory.manga)
        .toList();
    final posters = filtered
        .where((item) => const [
              CulturalCategory.movies,
              CulturalCategory.series,
              CulturalCategory.anime
            ].contains(item.category))
        .toList();
    final repos = filtered.where((item) => item.isGithubRepo).toList();

    return NixGlass(
      key: const Key('passport_glass'),
      radius: 26,
      mirror: true,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Passaporte cultural & acervo',
                style: NixTokens.headingMedium()),
            const SizedBox(height: 12),
            Wrap(spacing: 7, runSpacing: 6, children: [
              FilledButton.icon(
                key: const Key('passport_search_catalog'),
                onPressed: _importCatalogWork,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Buscar no catálogo'),
              ),
              OutlinedButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Adicionar ao Acervo'),
              ),
            ]),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 15),
              TextField(
                key: const Key('cultural_catalog_search_input'),
                onChanged: (query) =>
                    setState(() => _query = query.trim().toLowerCase()),
                decoration: const InputDecoration(
                  hintText: 'Filtrar meu acervo',
                  prefixIcon: Icon(Icons.filter_alt_outlined),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _filter('Todos (${items.length})', null),
                  for (final category in CulturalCategory.values) ...[
                    const SizedBox(width: 6),
                    _filter(
                        '${category.label} (${items.where((item) => item.category == category).length})',
                        category),
                  ],
                ]),
              ),
            ],
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 26),
                child: Text(
                    items.isEmpty
                        ? 'Seu acervo está vazio.'
                        : 'Nenhuma obra neste filtro.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.nixScheme.textSecondary)),
              ),
            if (vinyls.isNotEmpty) _shelf(state, 'Discos de vinil', vinyls),
            if (books.isNotEmpty) _shelf(state, 'Livros e mangás', books),
            if (posters.isNotEmpty)
              _shelf(state, 'Filmes, séries e animes', posters),
            if (repos.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Repositórios GitHub', style: NixTokens.labelUppercase()),
              const SizedBox(height: 9),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final repo in repos)
                  _GithubRepoAcervoCard(
                    item: repo,
                    onToggleVisibility: () =>
                        state.toggleItemCardIdVisibility(repo.id),
                    onDelete: () => _confirmDelete(repo),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filter(String label, CulturalCategory? category) => ChoiceChip(
        label: Text(label),
        selected: _category == category,
        onSelected: (_) => setState(() => _category = category),
      );

  Widget _shelf(NixState state, String label, List<CulturalItem> items) =>
      Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: NixTokens.labelUppercase()),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, box) {
            final cols = ((box.maxWidth + 12) / 116).floor().clamp(2, 7);
            final width =
                ((box.maxWidth - (cols - 1) * 12) / cols).clamp(1.0, 146.0);
            return Wrap(spacing: 12, runSpacing: 12, children: [
              for (final (index, item) in items.indexed)
                SizedBox(
                    width: width,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          NixMotionCard(
                              child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _showGallery(items, index),
                            onLongPress: () => _confirmDelete(item),
                            child: CulturalCoverArt(item: item, width: width),
                          )),
                          const SizedBox(height: 5),
                          Text(item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700)),
                          if (item.tracking.stage case final stage?)
                            Text(item.category.trackingLabel(stage),
                              style: Theme.of(context).textTheme.labelSmall),
                          if (item.tracking.fraction case final fraction?)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: LinearProgressIndicator(value: fraction,
                                semanticsLabel: 'Progresso de ${item.title}'),
                            ),
                          Row(children: [
                            Expanded(
                                child: Text(item.creatorOrYear,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color:
                                            context.nixScheme.textSecondary))),
                            IconButton(
                              tooltip: item.isPublicInCardId
                                  ? 'Ocultar do perfil'
                                  : 'Mostrar no perfil',
                              visualDensity: VisualDensity.compact,
                              iconSize: 15,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 30, minHeight: 38),
                              onPressed: () =>
                                  state.toggleItemCardIdVisibility(item.id),
                              icon: Icon(item.isPublicInCardId
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                            ),
                          ]),
                        ])),
            ]);
          }),
        ]),
      );

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
                  'Deseja retirar “${item.title}” do seu passaporte cultural?'),
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
        rating: _rating.text.trim().isEmpty ? '9.5' : _rating.text.trim(),
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
                  style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold),
                ),
              ),
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
        ],
      ),
    );
  }
}

/// Cartão de Pôster / Capa (Filmes, Séries, Animes, Mangás e Livros).
