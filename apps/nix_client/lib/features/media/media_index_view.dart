import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nix_transport/nix_transport.dart';
import '../../core/media/catalog_database.dart';
import '../../core/media/media_index_updater.dart';
import '../../core/security/file_picker_adapter.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_palette.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../design/nix_surfaces.dart';

/// Visão principal do Nix Media Index — Offline-First e Acervo Cultural.
class NixMediaIndexView extends StatefulWidget {
  const NixMediaIndexView({super.key});

  @override
  State<NixMediaIndexView> createState() => _NixMediaIndexViewState();
}

class _NixMediaIndexViewState extends State<NixMediaIndexView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();

  String? _selectedKind; // null = todas, 'movie', 'series', 'anime', 'manga', 'book'
  String? _selectedGenre;
  List<CatalogWork> _searchResults = [];
  List<Map<String, dynamic>> _userAcervo = [];
  bool _isLoading = false;
  bool _catalogFailed = false;
  int _searchGeneration = 0;

  final List<({String label, String? kind, IconData icon})> _kindFilters = [
    (label: 'Todas', kind: null, icon: Icons.all_inclusive_rounded),
    (label: 'Filmes', kind: 'movie', icon: Icons.movie_outlined),
    (label: 'Séries', kind: 'series', icon: Icons.tv_rounded),
    (label: 'Animes', kind: 'anime', icon: Icons.animation_rounded),
    (label: 'Mangás', kind: 'manga', icon: Icons.menu_book_rounded),
    (label: 'Livros', kind: 'book', icon: Icons.auto_stories_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        _loadUserAcervo();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _executeSearch();
      _loadUserAcervo();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  NixState get _nixState => context.read<NixState>();

  Future<void> _executeSearch() async {
    if (!mounted) return;
    final generation = ++_searchGeneration;
    final state = _nixState;
    setState(() {
      _isLoading = true;
      _catalogFailed = false;
    });
    try {
      await state.ensureCatalogDatabaseOpened();
      if (!mounted || generation != _searchGeneration) return;
      final results = await state.catalogDatabase?.searchWorks(
        query: _searchCtrl.text.trim(),
        kind: _selectedKind,
        genre: _selectedGenre,
        limit: 60,
      ) ?? const <CatalogWork>[];
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _catalogFailed = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUserAcervo() async {
    try {
      final identity = _nixState.primaryIdentity;
      if (identity == null) return;
      final entries = await _nixState.mediaRepository.listLibraryEntries(identity.publicId);
      if (mounted) {
        setState(() {
          _userAcervo = entries;
        });
      }
    } catch (_) {}
  }

  Future<void> _openAddToAcervoDialog(CatalogWork work) async {
    final identity = _nixState.primaryIdentity;
    if (identity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identidade soberana não inicializada.')),
      );
      return;
    }

    String status = 'want_to_watch';
    if (work.kind == 'book' || work.kind == 'manga') {
      status = 'want_to_read';
    }
    double rating = 80;
    final notesCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return AlertDialog(
              backgroundColor: NixColors.surfaceCard,
              shape: RoundedRectangleBorder(borderRadius: NixTokens.borderMd),
              title: Row(
                children: [
                  const Icon(Icons.bookmark_add_rounded, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Adicionar ao Acervo',
                      style: TextStyle(color: NixColors.textPrimary, fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      work.title,
                      style: TextStyle(
                        color: NixColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (work.creators != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        work.creators!,
                        style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      'Status:',
                      style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: status,
                      dropdownColor: NixColors.surfaceCard,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: NixColors.surfaceSidebar,
                        border: OutlineInputBorder(borderRadius: NixTokens.borderSm),
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: work.kind == 'book' || work.kind == 'manga'
                              ? 'want_to_read'
                              : 'want_to_watch',
                          child: Text(
                            work.kind == 'book' || work.kind == 'manga'
                                ? 'Quero Ler'
                                : 'Quero Ver',
                            style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                          ),
                        ),
                        DropdownMenuItem(
                          value: work.kind == 'book' || work.kind == 'manga'
                              ? 'reading'
                              : 'watching',
                          child: Text(
                            work.kind == 'book' || work.kind == 'manga'
                                ? 'Lendo'
                                : 'Assistindo',
                            style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'completed',
                          child: Text(
                            'Concluído',
                            style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'favorite',
                          child: Text(
                            'Favorito',
                            style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setDlgState(() => status = v);
                      },
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Sua Avaliação: ${rating.toInt()}/100',
                      style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                    ),
                    Slider(
                      value: rating,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      activeColor: Colors.amber,
                      inactiveColor: Colors.white24,
                      onChanged: (v) => setDlgState(() => rating = v),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      style: TextStyle(color: NixColors.textPrimary, fontSize: 12.5),
                      decoration: InputDecoration(
                        labelText: 'Anotações Pessoais (Privadas)',
                        hintText: 'Impressões, lembretes, edição preferida...',
                        filled: true,
                        fillColor: NixColors.surfaceSidebar,
                        border: OutlineInputBorder(borderRadius: NixTokens.borderSm),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.08),
                        borderRadius: NixTokens.borderSm,
                        border: Border.all(color: Colors.amber.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_rounded, size: 14, color: Colors.amber),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Seu Acervo é protegido com SQLCipher e NUNCA é transmitido à rede.',
                              style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Cancelar', style: TextStyle(color: NixColors.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Salvar no Acervo'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      await _nixState.mediaCatalogService?.saveToAcervo(
        identityId: identity.publicId,
        work: work,
        status: status,
        rating: rating.toInt(),
        privateNotes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
      );
      await _loadUserAcervo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${work.title}" adicionado ao seu Acervo.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _openLocalMedia() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Abrir mídia local'),
        content: const Text(
          'O arquivo selecionado será aberto no player do sistema, '
          'que segue suas próprias regras de privacidade.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Escolher arquivo'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _nixState.isStrictOffGridMode) return;
    try {
      if (Platform.isAndroid) {
        await const MethodChannel('com.projetonix.nix/platform')
            .invokeMethod<void>('openLocalMedia');
        return;
      }
      const extensions = ['mp4', 'mkv', 'webm', 'mp3', 'flac', 'ogg', 'wav'];
      final paths = await const CrossPlatformFilePickerAdapter().pickAttachments(
        allowedExtensions: extensions,
        allowMultiple: false,
      );
      if (paths.length != 1 || !mounted || _nixState.isStrictOffGridMode) return;
      final file = File(paths.single).absolute;
      final suffix = file.path.split('.').last.toLowerCase();
      if (!extensions.contains(suffix) || !await file.exists()) {
        throw const FormatException('Selecione um arquivo local de áudio ou vídeo.');
      }
      final opened = await Process.run('xdg-open', [file.path]);
      if (opened.exitCode != 0) throw StateError('Player do sistema indisponível.');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir a mídia no player do sistema.')),
      );
    }
  }

  Future<void> _openCatalogUpdateDialog() async {
    final nixState = _nixState;
    final updateManager = nixState.catalogUpdateManager;
    const source = String.fromEnvironment('NIX_CATALOG_MANIFEST_URL');
    final manifestUri = Uri.tryParse(source);
    void useTorPort() {
      updateManager.transportPolicy = TransportPolicy(
        socksPort: nixState.embeddedTor.socksPort,
      );
    }
    String? localError;
    final configured = manifestUri != null &&
        (manifestUri.scheme == 'http' || manifestUri.scheme == 'https') &&
        TransportPolicy.isValidOnionV3Host(manifestUri.host) &&
        manifestUri.userInfo.isEmpty &&
        !manifestUri.hasFragment;
    final hasTrustedKey = updateManager.keyring.trustedKeysHex.any(
      (key) => key != CatalogPublisherKeyring.fixtureTestPublisherKeyHex,
    );

    int currentVer = 0;
    List<CatalogVersionEntry> history = [];
    try {
      await nixState.ensureCatalogDatabaseOpened();
      currentVer = await updateManager.getInstalledVersion();
      history = await updateManager.getVersionHistory();
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            final progress = updateManager.currentProgress;

            return StreamBuilder<CatalogUpdateProgress>(
              stream: updateManager.progressStream,
              initialData: progress,
              builder: (context, snapshot) {
                final currentProgress = snapshot.data ?? progress;
                final isUpdating = updateManager.isBusy;
                final state = context.watch<NixState>();
                final available = configured && hasTrustedKey &&
                    !state.isStrictOffGridMode && state.securityGate.isTorAnonymityReady;
                final accent = context.accentTextColor;
                final errorColor = NixPalette.crimson.readableAccentOn(context.nixScheme);
                final sourceStatus = !configured
                    ? 'Esta versão do Nix veio sem um publicador Onion configurado.'
                    : !hasTrustedKey
                        ? 'A chave pública do publicador não foi configurada.'
                        : available
                            ? 'Publicador configurado. Conexão via Tor.'
                            : state.isStrictOffGridMode
                                ? 'Atualização remota indisponível no modo off-grid.'
                                : 'Conecte o Tor para verificar atualizações.';

                return AlertDialog(
                  backgroundColor: NixColors.surfaceCard,
                  shape: RoundedRectangleBorder(borderRadius: NixTokens.borderMd),
                  title: Row(
                    children: [
                      Icon(Icons.shield_outlined, color: accent, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Atualizações Privadas do Catálogo',
                          style: TextStyle(
                            color: NixColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: SizedBox(
                      width: 480,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: NixColors.surfaceSidebar,
                              borderRadius: NixTokens.borderSm,
                              border: Border.all(color: NixColors.surfaceBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.inventory_2_outlined, size: 16, color: accent),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Versão Instalada: ${currentVer > 0 ? "v$currentVer" : "Catálogo Inicial"}',
                                        style: TextStyle(
                                          color: NixColors.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.vpn_lock_rounded, size: 16, color: accent),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        sourceStatus,
                                        style: TextStyle(
                                          color: NixColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Baixa um novo catálogo de metadados assinado. A busca e o acervo pessoal continuam locais.',
                            style: TextStyle(color: NixColors.textSecondary, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          if (localError != null)
                            Text(localError!, style: TextStyle(color: errorColor)),
                          if (currentProgress.statusMessage.isNotEmpty) ...[
                            Text(
                              currentProgress.statusMessage,
                              style: TextStyle(
                                color: currentProgress.stage == CatalogUpdateStage.error
                                    ? errorColor
                                    : NixColors.textPrimary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (isUpdating) ...[
                            LinearProgressIndicator(
                              value: currentProgress.progressPercent > 0
                                  ? currentProgress.progressPercent
                                  : null,
                              backgroundColor: NixColors.surfaceSidebar,
                              color: Colors.amber,
                            ),
                            const SizedBox(height: 12),
                            if (updateManager.canCancel)
                              Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                icon: Icon(Icons.cancel_outlined, size: 16, color: errorColor),
                                label: const Text('Cancelar', style: TextStyle(color: Colors.redAccent)),
                                onPressed: () {
                                  updateManager.cancel();
                                  setDlgState(() {});
                                },
                              ),
                            ),
                          ],
                          if (currentProgress.availableManifest != null &&
                              currentProgress.stage == CatalogUpdateStage.updateAvailable) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.08),
                                borderRadius: NixTokens.borderSm,
                                border: Border.all(color: Colors.amber.withOpacity(0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Nova Versão ${currentProgress.availableManifest!.version} Detectada',
                                    style: const TextStyle(
                                      color: Colors.amber,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Obras: ${currentProgress.availableManifest!.entryCount} | Tamanho: ${(currentProgress.availableManifest!.byteSize / 1024 / 1024).toStringAsFixed(1)} MB',
                                    style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Assinatura: ${currentProgress.availableManifest!.signatureHex.substring(0, 16)}...',
                                    style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (history.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Histórico de Atualizações:',
                              style: TextStyle(
                                color: NixColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 120),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: history.length,
                                itemBuilder: (ctx, idx) {
                                  final item = history[idx];
                                  final date = DateTime.fromMillisecondsSinceEpoch(item.appliedAtUnix * 1000).toLocal();
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 3),
                                    child: Row(
                                      children: [
                                        Icon(
                                          item.status == 'success'
                                              ? Icons.check_circle_outline
                                              : Icons.error_outline,
                                          size: 14,
                                          color: item.status == 'success' ? Colors.greenAccent : Colors.redAccent,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'v${item.version} (${item.entryCount} obras)',
                                          style: TextStyle(color: NixColors.textPrimary, fontSize: 12),
                                        ),
                                        const Spacer(),
                                        Text(
                                          '${date.day}/${date.month}/${date.year}',
                                          style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              icon: const Icon(Icons.cleaning_services_outlined, size: 14),
                              label: const Text('Limpar Cache / Temporários', style: TextStyle(fontSize: 11)),
                              onPressed: isUpdating ? null : () async {
                                final freed = await updateManager.cleanupStorage();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Armazenamento limpo: ${(freed / 1024).toStringAsFixed(1)} KB liberados.')),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      child: Text('Fechar', style: TextStyle(color: NixColors.textSecondary)),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                    if (!isUpdating &&
                        currentProgress.stage == CatalogUpdateStage.updateAvailable &&
                        currentProgress.availableManifest != null)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Aplicar Atualização'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                        onPressed: !available ? null : () async {
                          final manifest = currentProgress.availableManifest!;
                          final package = manifest.artifactName;
                          if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*[.]db$').hasMatch(package)) {
                            setDlgState(() => localError = 'Nome do pacote inválido no manifesto.');
                            return;
                          }
                          setDlgState(() => localError = null);
                          try {
                            useTorPort();
                            final newDb = await updateManager.downloadAndApplyUpdate(
                              manifest: manifest,
                              packageUri: manifestUri.resolve(package),
                            );
                            nixState.setCatalogDatabase(newDb);
                            currentVer = await updateManager.getInstalledVersion();
                            history = await updateManager.getVersionHistory();
                            if (mounted) await _executeSearch();
                            if (ctx.mounted) setDlgState(() {});
                          } catch (_) {}
                        },
                      )
                    else if (!isUpdating)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Verificar Agora'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                        onPressed: !available ? null : () async {
                          setDlgState(() => localError = null);
                          try {
                            useTorPort();
                            await updateManager.checkForUpdate(manifestUri: manifestUri);
                          } catch (_) {}
                        },
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: NixColors.background,
      appBar: AppBar(
        backgroundColor: NixColors.surfaceCard,
        elevation: 0,
        actions: [
          if (Platform.isAndroid || Platform.isLinux)
            IconButton(
              tooltip: 'Abrir mídia local no player do sistema',
              icon: const Icon(Icons.play_circle_outline_rounded),
              onPressed: context.watch<NixState>().isStrictOffGridMode
                  ? null
                  : _openLocalMedia,
            ),
          IconButton(
            tooltip: 'Atualizações Privadas do Catálogo (Tor)',
            icon: Icon(Icons.cloud_sync_rounded, color: context.accentTextColor),
            onPressed: _openCatalogUpdateDialog,
          ),
          const SizedBox(width: 8),
        ],
        title: const NixPanelTitle(
          icon: Icons.local_library_rounded,
          title: 'Nix Media Index',
          subtitle: '100% Offline',
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: context.accentTextColor,
          labelColor: context.accentTextColor,
          unselectedLabelColor: NixColors.textSecondary,
          tabs: [
            Tab(
              icon: const Icon(Icons.travel_explore_rounded, size: 18),
              text: 'Catálogo Offline (${_searchResults.length})',
            ),
            Tab(
              icon: const Icon(Icons.bookmarks_rounded, size: 18),
              text: 'Meu Acervo Pessoal (${_userAcervo.length})',
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildCatalogTab(isCompact),
            _buildAcervoTab(isCompact),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogTab(bool isCompact) {
    return Column(
      children: [
        // Barra de Busca e Filtros
        Container(
          padding: const EdgeInsets.all(12),
          color: NixColors.surfaceCard,
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar por título, autor, diretor, gênero ou palavra-chave...',
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.amber, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            _executeSearch();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: NixColors.surfaceSidebar,
                  border: OutlineInputBorder(
                    borderRadius: NixTokens.borderSm,
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
                onSubmitted: (_) => _executeSearch(),
                onChanged: (_) => _executeSearch(),
              ),
              const SizedBox(height: 8),
              // Chips de Categoria
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _kindFilters.map((f) {
                    final isSelected = _selectedKind == f.kind;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        selected: isSelected,
                        avatar: Icon(
                          f.icon,
                          size: 14,
                          color: isSelected ? Colors.black : NixColors.textSecondary,
                        ),
                        label: Text(f.label),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.black : NixColors.textPrimary,
                          fontSize: 11.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        backgroundColor: NixColors.surfaceSidebar,
                        selectedColor: Colors.amber,
                        checkmarkColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        onSelected: (selected) {
                          setState(() {
                            _selectedKind = selected ? f.kind : null;
                          });
                          _executeSearch();
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),

        // Conteúdo
        Expanded(
          child: _isLoading
              ? const Center(child: Text('Carregando catálogo…'))
              : _catalogFailed
                  ? Center(
                      child: TextButton.icon(
                        onPressed: _executeSearch,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Catálogo indisponível. Tentar novamente'),
                      ),
                    )
                  : _searchResults.isEmpty
                      ? _buildEmptyState()
                      : _buildResultsList(isCompact),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 48, color: NixColors.textSecondary),
              const SizedBox(height: 12),
              Text(
                'Nenhuma obra encontrada no catálogo local',
                style: TextStyle(
                  color: NixColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tente termos mais amplos ou altere o filtro de categoria. A busca é 100% offline via FTS5.',
                textAlign: TextAlign.center,
                style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsList(bool isCompact) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final work = _searchResults[index];
        return _buildWorkCard(work);
      },
    );
  }

  Widget _buildWorkCard(CatalogWork work) {
    final kindIcon = switch (work.kind) {
      'movie' || 'film' => Icons.movie_outlined,
      'series' => Icons.tv_rounded,
      'anime' => Icons.animation_rounded,
      'manga' => Icons.menu_book_rounded,
      'book' => Icons.auto_stories_rounded,
      _ => Icons.bookmark_outline_rounded,
    };

    final kindColor = switch (work.kind) {
      'movie' || 'film' => Colors.blueAccent,
      'series' => Colors.purpleAccent,
      'anime' => Colors.pinkAccent,
      'manga' => Colors.orangeAccent,
      'book' => Colors.greenAccent,
      _ => Colors.amber,
    };

    return NixMotionCard(child: NixFrame(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Placeholder Seguro de Capa (zero conexões de rede externas)
            Container(
              width: 54,
              height: 74,
              decoration: BoxDecoration(
                color: kindColor.withOpacity(0.12),
                borderRadius: NixTokens.borderSm,
                border: Border.all(color: kindColor.withOpacity(0.3)),
              ),
              child: Center(
                child: Icon(kindIcon, size: 28, color: kindColor),
              ),
            ),
            const SizedBox(width: 12),
            // Informações
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: kindColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          work.kind.toUpperCase(),
                          style: TextStyle(
                            color: kindColor,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (work.releaseYear != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${work.releaseYear}',
                          style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    work.title,
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (work.originalTitle != null &&
                      work.originalTitle != work.title) ...[
                    Text(
                      work.originalTitle!,
                      style: TextStyle(
                        color: NixColors.textSecondary,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  if (work.creators != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      work.creators!,
                      style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
                    ),
                  ],
                  if (work.summary != null && work.summary!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      work.summary!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Botão Adicionar ao Acervo
            IconButton(
              icon: const Icon(Icons.bookmark_add_outlined, color: Colors.amber),
              tooltip: 'Adicionar ao Acervo',
              onPressed: () => _openAddToAcervoDialog(work),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _buildAcervoTab(bool isCompact) {
    if (_userAcervo.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bookmarks_outlined, size: 48, color: NixColors.textSecondary),
                const SizedBox(height: 12),
                Text(
                  'Seu Acervo Cultural Pessoal está vazio',
                  style: TextStyle(
                    color: NixColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Adicione filmes, séries, animes, mangás e livros pelo Catálogo Offline. Todas as suas avaliações e anotações são cifradas localmente com SQLCipher.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _userAcervo.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _userAcervo[index];
        final title = (item['title'] as String?) ?? 'Sem título';
        final status = (item['status'] as String?) ?? 'saved';
        final rating = item['rating'] as int?;

        final statusLabel = switch (status) {
          'want_to_watch' => 'Quero Ver',
          'want_to_read' => 'Quero Ler',
          'watching' => 'Assistindo',
          'reading' => 'Lendo',
          'completed' => 'Concluído',
          'favorite' => 'Favorito',
          _ => status,
        };

        return Card(
          color: NixColors.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: NixTokens.borderMd,
            side: BorderSide(color: NixColors.surfaceBorder.withOpacity(0.5)),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.amber.withOpacity(0.15),
              child: const Icon(Icons.bookmark_rounded, color: Colors.amber, size: 18),
            ),
            title: Text(
              title,
              style: TextStyle(
                color: NixColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusLabel,
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (rating != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.star_rounded, size: 13, color: Colors.amber.shade300),
                  const SizedBox(width: 2),
                  Text(
                    '$rating/100',
                    style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                  ),
                ],
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
              tooltip: 'Remover do Acervo',
              onPressed: () async {
                final identity = _nixState.primaryIdentity;
                if (identity != null) {
                  await _nixState.mediaCatalogService?.removeFromAcervo(
                    identityId: identity.publicId,
                    workId: item['media_id'] as String,
                  );
                  await _loadUserAcervo();
                }
              },
            ),
          ),
        );
      },
    );
  }
}
