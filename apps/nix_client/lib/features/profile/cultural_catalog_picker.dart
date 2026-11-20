import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/media/catalog_database.dart';
import '../../core/media/catalog_cultural_item.dart';
import '../../core/models/cultural_item.dart';
import '../../state/nix_state.dart';
import 'cultural_cover_art.dart';

export '../../core/media/catalog_cultural_item.dart'
    show culturalItemFromCatalog;

Future<CatalogWork?> pickCulturalCatalogWork(
  BuildContext context, {
  List<String>? playlist,
}) =>
    showDialog<CatalogWork>(
      context: context,
      builder: (_) => _CulturalCatalogPicker(playlist: playlist),
    );

class _CulturalCatalogPicker extends StatefulWidget {
  const _CulturalCatalogPicker({this.playlist});
  final List<String>? playlist;
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
        final results = await catalog.searchWorks(
            query: query.trim(),
            kind: widget.playlist == null ? null : 'track',
            limit: 40);
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
        title: Text(widget.playlist == null
            ? 'Buscar no catálogo local'
            : 'Music Index local'),
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
                  labelText: 'Título, autor ou artista',
                  prefixIcon: Icon(Icons.search)),
            ),
            if (widget.playlist case final names? when names.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Na playlist: ${names.join(' · ')}',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            if (widget.playlist != null)
              const Text(
                  'Escolha uma faixa e vincule um arquivo de áudio local.'),
            const SizedBox(height: 10),
            Expanded(
                child: _busy
                    ? const Center(child: CircularProgressIndicator())
                    : _message != null
                        ? Center(
                            child: Text(_message!, textAlign: TextAlign.center))
                        : widget.playlist != null
                            ? ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _works.length,
                                itemBuilder: (context, index) {
                                  final work = _works[index];
                                  final item = culturalItemFromCatalog(work);
                                  return SizedBox(
                                    width: 132,
                                    child: InkWell(
                                      onTap: () => Navigator.pop(context, work),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          CulturalCoverArt(
                                              item: item, width: 64),
                                          Text(work.title,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center),
                                          Text(item.creatorOrYear,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              )
                            : ListView.separated(
                                itemCount: _works.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 8),
                                itemBuilder: (context, index) {
                                  final work = _works[index];
                                  final item = culturalItemFromCatalog(work);
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 3),
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
