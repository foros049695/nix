import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/media/universal_metadata_service.dart';
import '../../core/models/cultural_item.dart';
import '../../core/network/transport_profile.dart';
import '../../core/security/platform_runtime.dart';
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
    final isTorReady = nixState.isTorRunning ||
        nixState.embeddedTor.isReady ||
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

  Future<String?> _downloadCoverFile(UniversalMetadataItem item) async {
    if (item.coverUrl == null || item.coverUrl!.isEmpty) return null;
    final nixState = context.read<NixState>();
    final profile = GlobalTransportRegistry.current.getProfile(TransportModule.music);
    final isClearnet = profile == TransportProfileType.directHttps;
    final isTorReady = nixState.isTorRunning ||
        nixState.embeddedTor.isReady ||
        nixState.securityGate.torOnionV3Ready ||
        nixState.embeddedTor.socksPort > 0;
    final socksPort = nixState.embeddedTor.socksPort > 0 ? nixState.embeddedTor.socksPort : 9050;

    try {
      final bytes = await _service.downloadImageBytes(
        item.coverUrl!,
        allowClearnet: isClearnet,
        isTorReady: isTorReady,
        socksPort: socksPort,
      );
      if (bytes != null && bytes.isNotEmpty) {
        final coversDir = Directory(NixPlatformPaths.coversDirectory);
        if (!coversDir.existsSync()) {
          coversDir.createSync(recursive: true);
        }
        final safeName = item.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        final file = File('${coversDir.path}/$safeName.jpg');
        await file.writeAsBytes(bytes);
        return file.path;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _addToCatalog(UniversalMetadataItem item) async {
    final nixState = context.read<NixState>();
    final localPath = await _downloadCoverFile(item);
    try {
      await nixState.ensureCatalogDatabaseOpened();
      final db = nixState.catalogDatabase;
      if (db != null) {
        final work = item.toCatalogWork();
        final finalWork = localPath != null ? work.copyWith(coverThumb: localPath) : work;
        await db.insertWork(finalWork);
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
    final localPath = await _downloadCoverFile(item);

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
      localImagePath: localPath,
      synopsis: item.synopsis,
      genres: item.genres != null ? item.genres!.split(', ') : const [],
      source: item.sourceName.toLowerCase(),
    );

    await nixState.saveCulturalItem(newItem);
    setState(() => _addedAcervoIds.add(item.id));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${item.title}" adicionado com capa local ao seu Acervo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = GlobalTransportRegistry.current.getProfile(TransportModule.music);
    final isClearnet = profile == TransportProfileType.directHttps;
    final nixState = context.watch<NixState>();
    final isTorReady = nixState.isTorRunning ||
        nixState.embeddedTor.isReady ||
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
                                        // Miniatura da Capa Cultural Distinta (Vinil, Livro 2.5D ou Pôster)
                                        _SearchResultCover(
                                          item: item,
                                          service: _service,
                                          allowClearnet: isClearnet,
                                          isTorReady: isTorReady,
                                          socksPort: nixState.embeddedTor.socksPort > 0 ? nixState.embeddedTor.socksPort : 9050,
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

  static IconData kindIcon(String kind) {
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

class _SearchResultCover extends StatefulWidget {
  final UniversalMetadataItem item;
  final UniversalMetadataService service;
  final bool allowClearnet;
  final bool isTorReady;
  final int socksPort;

  const _SearchResultCover({
    required this.item,
    required this.service,
    required this.allowClearnet,
    required this.isTorReady,
    required this.socksPort,
  });

  @override
  State<_SearchResultCover> createState() => _SearchResultCoverState();
}

class _SearchResultCoverState extends State<_SearchResultCover> {
  static final Map<String, Uint8List> _thumbCache = {};
  Uint8List? _bytes;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  @override
  void didUpdateWidget(covariant _SearchResultCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.coverUrl != widget.item.coverUrl) {
      _loadThumb();
    }
  }

  Future<void> _loadThumb() async {
    final safeId = widget.item.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final coversDir = NixPlatformPaths.coversDirectory;
    for (final ext in ['jpg', 'png', 'webp', 'jpeg']) {
      final f = File('$coversDir/$safeId.$ext');
      if (f.existsSync() && f.lengthSync() > 0) {
        final b = await f.readAsBytes();
        if (mounted) {
          setState(() {
            _bytes = b;
            _isLoading = false;
          });
        }
        return;
      }
    }

    final url = widget.item.coverUrl;
    if (url == null || url.isEmpty) return;
    if (_thumbCache.containsKey(url)) {
      setState(() => _bytes = _thumbCache[url]);
      return;
    }

    _isLoading = true;
    final b = await widget.service.downloadImageBytes(
      url,
      allowClearnet: widget.allowClearnet,
      isTorReady: widget.isTorReady,
      socksPort: widget.socksPort,
    );
    if (!mounted) return;
    if (b != null) {
      _thumbCache[url] = b;
      setState(() {
        _bytes = b;
        _isLoading = false;
      });
      // Salva no cache local de capas automaticamente
      try {
        final dir = Directory(coversDir);
        if (!dir.existsSync()) dir.createSync(recursive: true);
        final f = File('$coversDir/$safeId.jpg');
        await f.writeAsBytes(b);
      } catch (_) {}
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMusic = widget.item.kind == 'track' || widget.item.kind == 'album';
    final isBook = widget.item.kind == 'book';
    final isManga = widget.item.kind == 'manga';

    if (isMusic) {
      // Disco de vinil soberano 1:1 circular
      return Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(color: Colors.white70, width: 1.5),
        ),
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_bytes != null)
                Image.memory(_bytes!, fit: BoxFit.cover)
              else if (_isLoading)
                Container(
                  color: const Color(0xFF16151F),
                  child: const Center(
                    child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5)),
                  ),
                )
              else
                Container(
                  color: const Color(0xFF16151F),
                  child: Center(
                    child: Text(
                      widget.item.title.isNotEmpty
                          ? widget.item.title.substring(0, math.min(2, widget.item.title.length)).toUpperCase()
                          : '♪',
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              const CustomPaint(painter: _MiniSearchVinylPainter()),
              Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0F0E17),
                    border: Border.all(color: Colors.white60, width: 1.0),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isBook || isManga) {
      // 2.5D Livro / Volume Manga com lombada física e páginas
      return SizedBox(
        width: 54,
        height: 76,
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: 2,
              bottom: 2,
              width: 5,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFE5DDD0),
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
                  border: Border.all(color: const Color(0xFFB5A998), width: 0.5),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 4,
              top: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(2),
                    bottomLeft: const Radius.circular(2),
                    topRight: Radius.circular(isManga ? 2 : 3),
                    bottomRight: Radius.circular(isManga ? 2 : 3),
                  ),
                  border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 4,
                      offset: const Offset(1, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_bytes != null)
                        Image.memory(_bytes!, fit: BoxFit.cover)
                      else if (_isLoading)
                        const Center(
                          child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5)),
                        )
                      else
                        Center(
                          child: Icon(
                            isManga ? Icons.menu_book_rounded : Icons.auto_stories_rounded,
                            size: 24,
                            color: Colors.white54,
                          ),
                        ),
                      // Vinco da lombada
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 3.5,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0x60000000), Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Pôster Cinematográfico Vertical 2:3 (Filmes, Séries, Anime)
    return Container(
      width: 54,
      height: 76,
      decoration: BoxDecoration(
        color: NixColors.surfaceElevated,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_bytes != null)
              Image.memory(_bytes!, fit: BoxFit.cover)
            else if (_isLoading)
              const Center(
                child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5)),
              )
            else
              Center(
                child: Icon(
                  _UniversalMetadataSearchDialogState.kindIcon(widget.item.kind),
                  size: 26,
                  color: NixColors.textSecondary,
                ),
              ),
            // Brilho acetinado diagonal
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x18FFFFFF), Colors.transparent],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniSearchVinylPainter extends CustomPainter {
  const _MiniSearchVinylPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final groovePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (final factor in [0.45, 0.60, 0.75, 0.88]) {
      canvas.drawCircle(center, radius * factor, groovePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
