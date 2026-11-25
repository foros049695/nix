import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/media/universal_metadata_service.dart';
import '../../core/models/cultural_item.dart';
import '../../core/network/transport_profile.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

/// Modal de Busca Online Universal de Metadados Públicos (Seção 4).
/// Conecta a MusicBrainz, TVmaze, AniList GraphQL, Open Library, Wikidata e fontes Onion
/// sem exigir chave de API privada do usuário, respeitando o perfil de privacidade ativo.
class UniversalMetadataSearchDialog extends StatefulWidget {
  final String? initialQuery;
  final MetadataSourceKind initialSource;

  const UniversalMetadataSearchDialog({
    super.key,
    this.initialQuery,
    this.initialSource = MetadataSourceKind.all,
  });

  static Future<void> show(
    BuildContext context, {
    String? initialQuery,
    MetadataSourceKind initialSource = MetadataSourceKind.all,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => UniversalMetadataSearchDialog(
        initialQuery: initialQuery,
        initialSource: initialSource,
      ),
    );
  }

  @override
  State<UniversalMetadataSearchDialog> createState() =>
      _UniversalMetadataSearchDialogState();
}

class _UniversalMetadataSearchDialogState
    extends State<UniversalMetadataSearchDialog> {
  late final TextEditingController _searchCtrl;
  late MetadataSourceKind _selectedSource;
  final UniversalMetadataService _service = const UniversalMetadataService();

  List<UniversalMetadataItem> _results = [];
  bool _isLoading = false;
  String? _errorMessage;
  final Set<String> _addedCatalogIds = {};
  final Set<String> _addedAcervoIds = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.initialQuery ?? '');
    _selectedSource = widget.initialSource;
    if (_searchCtrl.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _executeSearch());
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _executeSearch() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;

    final nixState = context.read<NixState>();
    final profile = GlobalTransportRegistry.current.getProfile(TransportModule.music);
    final isClearnet = profile == TransportProfileType.directHttps;
    final isTorReady = nixState.embeddedTor.isReady ||
        nixState.securityGate.torOnionV3Ready ||
        nixState.embeddedTor.socksPort > 0;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await _service.search(
        query: query,
        source: _selectedSource,
        allowClearnet: isClearnet,
        isTorReady: isTorReady,
        socksPort: nixState.embeddedTor.socksPort > 0 ? nixState.embeddedTor.socksPort : 9050,
      );

      if (!mounted) return;
      setState(() {
        _results = items;
        _isLoading = false;
        if (items.isEmpty) {
          _errorMessage = 'Nenhum resultado encontrado para "$query". Tente termos mais amplos ou altere a fonte.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _addToCatalog(UniversalMetadataItem item) async {
    final nixState = context.read<NixState>();
    try {
      await nixState.ensureCatalogDatabaseOpened();
      final db = nixState.catalogDatabase;
      if (db != null) {
        await db.insertWork(item.toCatalogWork());
        setState(() => _addedCatalogIds.add(item.id));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${item.title}" adicionado ao Catálogo Offline.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao adicionar: $e')),
        );
      }
    }
  }

  Future<void> _addToAcervo(UniversalMetadataItem item) async {
    final nixState = context.read<NixState>();
    final category = switch (item.kind) {
      'movie' => CulturalCategory.movies,
      'series' => CulturalCategory.series,
      'anime' => CulturalCategory.anime,
      'manga' => CulturalCategory.manga,
      'book' => CulturalCategory.books,
      'album' || 'track' => CulturalCategory.music,
      _ => CulturalCategory.movies,
    };

    final newItem = CulturalItem(
      id: 'acervo_${DateTime.now().microsecondsSinceEpoch}',
      title: item.title,
      originalTitle: item.originalTitle,
      creatorOrYear: item.creators ?? (item.releaseYear != null ? '${item.releaseYear}' : ''),
      creator: item.creators,
      releaseYear: item.releaseYear,
      category: category,
      monogram: item.title.isNotEmpty ? item.title.substring(0, 1).toUpperCase() : 'N',
      localImagePath: item.coverUrl,
      synopsis: item.synopsis,
      genres: item.genres != null ? item.genres!.split(', ') : const [],
      source: item.sourceName.toLowerCase(),
    );

    await nixState.saveCulturalItem(newItem);
    setState(() => _addedAcervoIds.add(item.id));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${item.title}" adicionado ao seu Acervo Pessoal.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = GlobalTransportRegistry.current.getProfile(TransportModule.music);
    final isClearnet = profile == TransportProfileType.directHttps;
    final nixState = context.watch<NixState>();
    final isTorReady = nixState.embeddedTor.isReady ||
        nixState.securityGate.torOnionV3Ready ||
        nixState.embeddedTor.socksPort > 0;

    return Dialog(
      backgroundColor: NixColors.surfaceCard,
      shape: RoundedRectangleBorder(borderRadius: NixTokens.borderLg),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabeçalho
              Row(
                children: [
                  const Icon(Icons.travel_explore_rounded, color: Colors.amber, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Buscar Metadados Online',
                          style: TextStyle(
                            color: NixColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Música (MusicBrainz), Séries (TVmaze), Anime/Mangá (AniList), Livros (Open Library) e Wikidata.',
                          style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Banner de Transporte Ativo
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isClearnet
                      ? Colors.amber.withOpacity(0.12)
                      : (isTorReady ? Colors.teal.withOpacity(0.12) : Colors.red.withOpacity(0.12)),
                  borderRadius: NixTokens.borderSm,
                  border: Border.all(
                    color: isClearnet
                        ? Colors.amber.withOpacity(0.4)
                        : (isTorReady ? Colors.teal.withOpacity(0.4) : Colors.red.withOpacity(0.4)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isClearnet
                          ? Icons.public_rounded
                          : (isTorReady ? Icons.vpn_lock_rounded : Icons.gpp_bad_rounded),
                      size: 16,
                      color: isClearnet
                          ? Colors.amber
                          : (isTorReady ? Colors.tealAccent : Colors.redAccent),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isClearnet
                            ? 'Transporte: Conexão Direta HTTPS (Clearnet) — Alta velocidade e sem proxy'
                            : (isTorReady
                                ? 'Transporte: Tor SOCKS5 Ativo (127.0.0.1:9050) — Isolado por circuito e anônimo'
                                : 'Transporte: Tor SOCKS5 Inativo — Conexão protegida em fail-closed'),
                        style: TextStyle(
                          color: isClearnet
                              ? Colors.amber
                              : (isTorReady ? Colors.tealAccent : Colors.redAccent),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Barra de Busca e Seletor de Fonte
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _searchCtrl,
                      style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Digite o título da obra, artista, autor ou termo...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: NixColors.surfaceSidebar,
                        border: OutlineInputBorder(borderRadius: NixTokens.borderSm),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _executeSearch(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<MetadataSourceKind>(
                      value: _selectedSource,
                      isExpanded: true,
                      dropdownColor: NixColors.surfaceCard,
                      decoration: InputDecoration(
                        labelText: 'Fonte',
                        filled: true,
                        fillColor: NixColors.surfaceSidebar,
                        border: OutlineInputBorder(borderRadius: NixTokens.borderSm),
                        isDense: true,
                      ),
                      items: MetadataSourceKind.values.map((src) {
                        return DropdownMenuItem(
                          value: src,
                          child: Text(
                            src.label,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _selectedSource = v);
                          if (_searchCtrl.text.trim().isNotEmpty) _executeSearch();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _executeSearch,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.search_rounded, size: 18),
                    label: const Text('Buscar'),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Lista de Resultados
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Consultando bases públicas de metadados...'),
                          ],
                        ),
                      )
                    : _errorMessage != null && _results.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.info_outline_rounded, size: 40, color: NixColors.textSecondary),
                                  const SizedBox(height: 10),
                                  Text(_errorMessage!, textAlign: TextAlign.center),
                                ],
                              ),
                            ),
                          )
                        : _results.isEmpty
                            ? Center(
                                child: Text(
                                  'Digite uma obra acima para consultar metadados reais online.',
                                  style: TextStyle(color: NixColors.textSecondary),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _results.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final item = _results[index];
                                  final inCatalog = _addedCatalogIds.contains(item.id);
                                  final inAcervo = _addedAcervoIds.contains(item.id);

                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: NixColors.surfaceSidebar,
                                      borderRadius: NixTokens.borderMd,
                                      border: Border.all(color: NixColors.surfaceBorder),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Miniatura da Capa
                                        ClipRRect(
                                          borderRadius: NixTokens.borderSm,
                                          child: Container(
                                            width: 54,
                                            height: 74,
                                            color: NixColors.surfaceElevated,
                                            child: item.coverUrl != null
                                                ? Image.network(
                                                    item.coverUrl!,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) => Icon(
                                                      _kindIcon(item.kind),
                                                      size: 28,
                                                      color: NixColors.textSecondary,
                                                    ),
                                                  )
                                                : Icon(
                                                    _kindIcon(item.kind),
                                                    size: 28,
                                                    color: NixColors.textSecondary,
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),

                                        // Detalhes da Obra
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      item.title,
                                                      style: TextStyle(
                                                        color: NixColors.textPrimary,
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white.withOpacity(0.08),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      item.sourceName,
                                                      style: const TextStyle(fontSize: 10.5, color: Colors.amber),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (item.creators != null) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  item.creators!,
                                                  style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                                                ),
                                              ],
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Text(
                                                    item.kind.toUpperCase(),
                                                    style: TextStyle(
                                                      color: NixColors.accentPrimary,
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  if (item.releaseYear != null) ...[
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      '${item.releaseYear}',
                                                      style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                                                    ),
                                                  ],
                                                  if (item.genres != null) ...[
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        item.genres!,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              if (item.synopsis != null) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                  item.synopsis!,
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),

                                        // Botões de Ação
                                        Column(
                                          children: [
                                            FilledButton.tonalIcon(
                                              onPressed: inAcervo ? null : () => _addToAcervo(item),
                                              icon: Icon(inAcervo ? Icons.check_rounded : Icons.bookmark_add_outlined, size: 16),
                                              label: Text(inAcervo ? 'No Acervo' : 'Ao Acervo', style: const TextStyle(fontSize: 11)),
                                            ),
                                            const SizedBox(height: 6),
                                            OutlinedButton.icon(
                                              onPressed: inCatalog ? null : () => _addToCatalog(item),
                                              icon: Icon(inCatalog ? Icons.check_rounded : Icons.add_to_photos_outlined, size: 16),
                                              label: Text(inCatalog ? 'No Catálogo' : 'Ao Catálogo', style: const TextStyle(fontSize: 11)),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _kindIcon(String kind) {
    return switch (kind) {
      'movie' => Icons.movie_outlined,
      'series' => Icons.tv_rounded,
      'anime' => Icons.animation_rounded,
      'manga' => Icons.menu_book_rounded,
      'book' => Icons.auto_stories_rounded,
      'album' => Icons.album_outlined,
      'track' => Icons.music_note_outlined,
      _ => Icons.category_outlined,
    };
  }
}
