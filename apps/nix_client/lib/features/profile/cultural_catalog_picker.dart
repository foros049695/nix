import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/media/catalog_database.dart';
import '../../core/models/cultural_item.dart';
import '../../state/nix_state.dart';
import 'cultural_cover_art.dart';

CulturalItem culturalItemFromCatalog(CatalogWork work) {
  final category = switch (work.kind) {
    'series' => CulturalCategory.series,
    'anime' => CulturalCategory.anime,
    'manga' => CulturalCategory.manga,
    'book' => CulturalCategory.books,
    'music' || 'album' => CulturalCategory.music,
    _ => CulturalCategory.movies,
  };
  final thumb = work.coverThumb;
  return CulturalItem(
    id: 'catalog:${work.id}',
    title: work.title,
    creatorOrYear: [
      if (work.creators case final creators? when creators.isNotEmpty) creators,
      if (work.releaseYear case final year?) '$year',
    ].join(' · '),
    category: category,
    monogram: work.title.characters.take(2).toString().toUpperCase(),
    coverMotif:
        thumb != null && thumb.startsWith('placeholder:') && thumb.length < 100
            ? thumb
            : null,
    isPublicInCardId: false,
  );
}

Future<CatalogWork?> pickCulturalCatalogWork(BuildContext context) =>
    showDialog<CatalogWork>(
      context: context,
      builder: (_) => const _CulturalCatalogPicker(),
    );

class _CulturalCatalogPicker extends StatefulWidget {
  const _CulturalCatalogPicker();
  @override
  State<_CulturalCatalogPicker> createState() => _CulturalCatalogPickerState();
}

class _CulturalCatalogPickerState extends State<_CulturalCatalogPicker> {
  Timer? _debounce;
  int _generation = 0;
  bool _busy = false;
  String? _message;
  List<CatalogWork> _works = [];

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String query) {
    _debounce?.cancel();
    final current = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
    });
    _debounce = Timer(const Duration(milliseconds: 180), () async {
      try {
        final state = context.read<NixState>();
        await state.ensureCatalogDatabaseOpened();
        final catalog = state.catalogDatabase;
        if (catalog == null) throw StateError('Catálogo local indisponível');
        final results =
            await catalog.searchWorks(query: query.trim(), limit: 40);
        if (!mounted || current != _generation) return;
        setState(() {
          _works = results;
          _busy = false;
          _message = results.isEmpty ? 'Nenhuma obra encontrada.' : null;
        });
      } catch (_) {
        if (!mounted || current != _generation) return;
        setState(() {
          _works = [];
          _busy = false;
          _message = 'Não foi possível abrir o catálogo local.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Buscar no catálogo local'),
        content: SizedBox(
          width: 490,
          height: MediaQuery.sizeOf(context).height * .45,
          child: Column(children: [
            TextField(
              key: const Key('passport_catalog_query'),
              textInputAction: TextInputAction.search,
              onChanged: _search,
              onSubmitted: _search,
              decoration: const InputDecoration(
                  labelText: 'Título ou autor', prefixIcon: Icon(Icons.search)),
            ),
            const SizedBox(height: 10),
            Expanded(
                child: _busy
                    ? const Center(child: CircularProgressIndicator())
                    : _message != null
                        ? Center(
                            child: Text(_message!, textAlign: TextAlign.center))
                        : ListView.separated(
                            itemCount: _works.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 8),
                            itemBuilder: (context, index) {
                              final work = _works[index];
                              final item = culturalItemFromCatalog(work);
                              return ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                leading:
                                    CulturalCoverArt(item: item, width: 32),
                                title: Text(work.title),
                                subtitle: Text(item.creatorOrYear.isEmpty
                                    ? item.category.label
                                    : item.creatorOrYear),
                                onTap: () => Navigator.pop(context, work),
                              );
                            },
                          )),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'))
        ],
      );
}
