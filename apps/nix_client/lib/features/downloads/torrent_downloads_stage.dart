import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/downloads/aria2_download_controller.dart';
import '../../core/downloads/models/download_task.dart';
import '../../core/downloads/safe_file_launcher.dart';
import '../../core/torrent_index/adapters/indexer_sources_manager.dart';
import '../../core/torrent_index/api/nix_online_search_api.dart';
import '../../core/torrent_index/api/torrent_online_client.dart';
import '../../core/torrent_index/database/torrent_index_database.dart';
import '../../core/torrent_index/models/indexer_source_config.dart';
import '../../core/torrent_index/models/torrent_record.dart';
import '../../core/torrent_index/models/torrent_search_query.dart';
import '../../core/models/cultural_item.dart';
import '../../core/network/transport_profile.dart';
import '../network/transport_profile_dialog.dart';
import 'network_downloads_diagnostics_dialog.dart';
import '../../state/nix_state.dart';

/// Central unificada do Nix Downloads & Torrent Index.
/// Interface retrô inspirada em terminais digitais e visores analógicos estilo Pager.
class TorrentDownloadsStage extends StatefulWidget {
  final String? initialSearch;
  final TorrentIndexDatabase? database;
  final IndexerSourcesManager? sourcesManager;
  final Aria2DownloadController? downloadController;

  const TorrentDownloadsStage({
    super.key,
    this.initialSearch,
    this.database,
    this.sourcesManager,
    this.downloadController,
  });

  @override
  State<TorrentDownloadsStage> createState() => _TorrentDownloadsStageState();
}

class _TorrentDownloadsStageState extends State<TorrentDownloadsStage> {
  int _currentTab = 0; // 0: Buscador, 1: Downloads, 2: Fontes

  // Estado do Buscador de Torrents
  final TextEditingController _searchController = TextEditingController();
  TorrentSearchMode _searchMode = TorrentSearchMode.online;
  TorrentSortOrder _sortOrder = TorrentSortOrder.seedersDesc;
  int _minSeeds = 0;
  final Set<TorrentCategory> _selectedCategories = {};
  bool _isFilterDrawerOpen = false;
  bool _isSearching = false;
  TorrentSearchResult? _searchResult;
  String? _searchErrorMessage;

  // Serviços
  TorrentIndexDatabase? _db;
  IndexerSourcesManager? _sourcesManager;
  NixOnlineSearchApi? _onlineApi;
  TorrentOnlineClient? _onlineClient;
  Aria2DownloadController? _downloadController;

  // Estado dos downloads
  List<DownloadTask> _downloadTasks = [];
  int _totalLocalRecords = 0;
  DateTime? _lastSyncDate;

  @override
  void initState() {
    super.initState();
    _sourcesManager = widget.sourcesManager ?? IndexerSourcesManager();
    if (widget.initialSearch != null && widget.initialSearch!.isNotEmpty) {
      _searchController.text = widget.initialSearch!;
    }
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    final nixState = context.read<NixState>();

    // Inicializa banco dedicado SQLite FTS5 do índice de torrents
    _db = widget.database ?? await TorrentIndexDatabase.open();
    _sourcesManager ??= widget.sourcesManager ?? IndexerSourcesManager();
    _onlineApi = NixOnlineSearchApi(
      database: _db!,
      sourcesManager: _sourcesManager!,
    );
    _onlineClient = TorrentOnlineClient(
      localApiHandler: _onlineApi!.handleRequest,
    );

    // Inicializa controlador aria2 para downloads HTTP/HTTPS diretos
    if (widget.downloadController != null) {
      _downloadController = widget.downloadController;
    } else {
      _downloadController = nixState.downloadController;
      if (!_downloadController!.isDaemonRunning) {
        await _downloadController!.startDaemon();
      }
    }
    _downloadTasks = List.from(_downloadController!.tasks);
    _downloadController!.removeListener(_onTasksChanged);
    _downloadController!.addListener(_onTasksChanged);

    _totalLocalRecords = await _db!.getRecordCount();
    _lastSyncDate = await _db!.getLastSyncDate();

    // Se houver pesquisa inicial pré-preenchida pelo Acervo, dispara busca
    final prefill = nixState.prefilledTorrentSearch ?? widget.initialSearch;
    if (prefill != null && prefill.isNotEmpty) {
      _searchController.text = prefill;
      nixState.clearPrefilledTorrentSearch();
      _executeSearch();
    } else {
      _executeSearch();
    }

    if (mounted) setState(() {});
  }

  void _onTasksChanged() {
    if (mounted && _downloadController != null) {
      setState(() {
        _downloadTasks = List.from(_downloadController!.tasks);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _downloadController?.removeListener(_onTasksChanged);
    // O downloadController roda em segundo plano vinculado ao NixState; não o encerra ao mudar de aba.
    if (widget.database == null) {
      _db?.close();
    }
    super.dispose();
  }

  void _showSelectFromAcervoDialog() {
    final nixState = context.read<NixState>();
    final items = nixState.userProfile.culturalItems;

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seu Acervo Cultural ainda não possui obras cadastradas.'),
          backgroundColor: Color(0xFF7C3AED),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        String filter = '';
        return StatefulBuilder(
          builder: (context, setDlgState) {
            final filtered = items.where((it) {
              if (filter.isEmpty) return true;
              final q = filter.toLowerCase();
              return it.title.toLowerCase().contains(q) ||
                  (it.creator?.toLowerCase().contains(q) ?? false) ||
                  (it.originalTitle?.toLowerCase().contains(q) ?? false);
            }).toList();

            return AlertDialog(
              backgroundColor: const Color(0xFF131221),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFF2E2248)),
              ),
              title: const Row(
                children: [
                  Icon(Icons.auto_stories_rounded, color: Color(0xFF22D3EE), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Buscar Obra do Acervo Cultural',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 450,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Filtrar obras do acervo...',
                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                        filled: true,
                        fillColor: const Color(0xFF1B1A2C),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF334155)),
                        ),
                      ),
                      onChanged: (val) => setDlgState(() => filter = val.trim()),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text('Nenhuma obra encontrada no acervo.',
                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, idx) {
                                final item = filtered[idx];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  leading: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF7C3AED).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Center(
                                      child: Text(
                                        item.monogram,
                                        style: const TextStyle(color: Color(0xFFDDD6FE), fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    item.title,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${item.category.label} • Termo: ${item.torrentSearchQuery}',
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF64748B)),
                                  onTap: () {
                                    Navigator.of(ctx).pop();
                                    _searchController.text = item.torrentSearchQuery;
                                    _executeSearch();
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancelar', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _executeSearch({int page = 1}) async {
    if (_db == null) return;
    setState(() {
      _isSearching = true;
      _searchErrorMessage = null;
    });

    final query = TorrentSearchQuery(
      query: _searchController.text.trim(),
      categories: _selectedCategories,
      mode: _searchMode,
      sort: _sortOrder,
      page: page,
      pageSize: 20,
      minSeeders: _minSeeds > 0 ? _minSeeds : null,
    );

    try {
      TorrentSearchResult result;
      switch (_searchMode) {
        case TorrentSearchMode.local:
          result = await _db!.search(query);
          if (result.records.isEmpty && query.query.isNotEmpty && _onlineClient != null) {
            result = await _onlineClient!.searchOnline(
              query,
              userConsent: true,
              isTorReady: true,
            );
          }
          break;
        case TorrentSearchMode.online:
          result = await _onlineClient!.searchOnline(
            query,
            userConsent: true,
            isTorReady: true,
          );
          break;
        case TorrentSearchMode.liveFederated:
          result = await _onlineClient!.searchLiveFederated(
            query,
            userConsent: true,
            isTorReady: true,
          );
          break;
      }

      if (mounted) {
        setState(() {
          _searchResult = result;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchErrorMessage = 'Falha na pesquisa: $e';
          _isSearching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Barra de Cabeçalho Superior Retrô
          _buildTerminalHeader(),

          // Navegação das 3 Abas
          _buildStageTabs(),

          // Conteúdo Ativo
          Expanded(
            child: switch (_currentTab) {
              0 => _buildTorrentSearchTab(),
              1 => _buildDownloadsManagerTab(),
              2 => _buildSourcesManagerTab(),
              _ => const SizedBox.shrink(),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalHeader() {
    final nixState = context.watch<NixState>();
    final currentProfile = GlobalTransportRegistry.current.getProfile(
      _currentTab == 0 ? TransportModule.torrents : TransportModule.downloads,
    );
    final isTorVerified = nixState.securityGate.torBootstrapPercent == 100 &&
        nixState.securityGate.isTorAnonymityReady;

    String badgeLabel;
    Color badgeColor;
    Color badgeBorder;
    IconData badgeIcon;

    switch (currentProfile) {
      case TransportProfileType.onionV3Strict:
        badgeLabel = 'ONION V3 ESTRITO';
        badgeColor = const Color(0xFFA855F7);
        badgeBorder = const Color(0xFFA855F7).withOpacity(0.5);
        badgeIcon = Icons.shield_rounded;
        break;
      case TransportProfileType.torSocks5:
        if (isTorVerified) {
          badgeLabel = 'TOR SOCKS5 ATIVO';
          badgeColor = const Color(0xFF34D399);
          badgeBorder = const Color(0xFF10B981).withOpacity(0.5);
          badgeIcon = Icons.shield_outlined;
        } else {
          badgeLabel = 'TOR NÃO VERIFICADO (${nixState.securityGate.torBootstrapPercent}%)';
          badgeColor = const Color(0xFFFBBF24);
          badgeBorder = const Color(0xFFF59E0B).withOpacity(0.5);
          badgeIcon = Icons.hourglass_top_rounded;
        }
        break;
      case TransportProfileType.customSocks5:
        badgeLabel = 'SOCKS5 PERSONALIZADO';
        badgeColor = const Color(0xFF38BDF8);
        badgeBorder = const Color(0xFF0284C7).withOpacity(0.5);
        badgeIcon = Icons.settings_ethernet_rounded;
        break;
      case TransportProfileType.directHttps:
        badgeLabel = 'CLEARNET DIRETA (SEM TOR)';
        badgeColor = const Color(0xFFF97316);
        badgeBorder = const Color(0xFFEA580C).withOpacity(0.5);
        badgeIcon = Icons.warning_amber_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14).withOpacity(0.85),
        border: const Border(bottom: BorderSide(color: Color(0xFF2E2248))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.5)),
            ),
            child: const Text(
              'TORLINK // NIX INDEX',
              style: TextStyle(
                color: Color(0xFFC4B5FD),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Pesquisa de metadados — online e offline (aria2 direto HTTP/HTTPS)',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Botão de Diagnóstico de Rede e Downloads (Seção 9)
          InkWell(
            onTap: () => NetworkDownloadsDiagnosticsDialog.show(
              context,
              downloadController: _downloadController,
            ),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.35)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.analytics_outlined, size: 13, color: Color(0xFF38BDF8)),
                  SizedBox(width: 4),
                  Text(
                    'Diagnóstico',
                    style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Indicador dinâmico de transporte e privacidade (Seção 8 e 5)
          Tooltip(
            message: 'Clique para alterar o perfil de transporte e privacidade deste módulo',
            child: InkWell(
              key: const ValueKey('transport_profile_badge'),
              onTap: () => TransportProfileDialog.show(
                context,
                initialModule: _currentTab == 0 ? TransportModule.torrents : TransportModule.downloads,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: badgeBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 12, color: badgeColor),
                    const SizedBox(width: 4),
                    Text(
                      badgeLabel,
                      style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
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

  Widget _buildStageTabs() {
    return Container(
      color: const Color(0xFF11111B).withOpacity(0.7),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _tabChip(0, Icons.search_rounded, 'Buscador de Torrents'),
            const SizedBox(width: 8),
            _tabChip(
              1,
              Icons.downloading_rounded,
              'Nix Downloads (aria2)',
              badgeCount: _downloadTasks.where((t) => t.status == DownloadStatus.downloading).length,
            ),
            const SizedBox(width: 8),
            _tabChip(2, Icons.hub_outlined, 'Fontes & Conectores'),
          ],
        ),
      ),
    );
  }

  Widget _tabChip(int tabIndex, IconData icon, String label, {int badgeCount = 0}) {
    final isSelected = _currentTab == tabIndex;
    return InkWell(
      onTap: () => setState(() => _currentTab = tabIndex),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF7C3AED).withOpacity(0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFF334155).withOpacity(0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? const Color(0xFFDDD6FE) : const Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (badgeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // ABA 1: Buscador de Torrents
  // -------------------------------------------------------------
  Widget _buildTorrentSearchTab() {
    return Column(
      children: [
        // Barra de busca estilo prompt de terminal
        Container(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              // Linha dos chips de seleção do Modo de Pesquisa
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final mode in TorrentSearchMode.values) ...[
                      _modeChip(mode),
                      const SizedBox(width: 6),
                    ],
                    const SizedBox(width: 12),
                    // Botão de Filtros
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFC4B5FD),
                        side: BorderSide(
                          color: _selectedCategories.isNotEmpty ? const Color(0xFF8B5CF6) : const Color(0xFF475569),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      onPressed: () => setState(() => _isFilterDrawerOpen = !_isFilterDrawerOpen),
                      icon: Icon(
                        _isFilterDrawerOpen ? Icons.filter_alt_off_rounded : Icons.filter_alt_rounded,
                        size: 15,
                      ),
                      label: Text(
                        _selectedCategories.isEmpty ? 'Filtros' : 'Filtros (${_selectedCategories.length})',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Botão Buscar Obra do Acervo (Seção 6.2)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF22D3EE),
                        side: const BorderSide(color: Color(0xFF0891B2)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      onPressed: _showSelectFromAcervoDialog,
                      icon: const Icon(Icons.auto_stories_rounded, size: 15),
                      label: const Text('Buscar obra do Acervo', style: TextStyle(fontSize: 11.5)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Campo de texto estilo terminal
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0E17),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF6D28D9).withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '>',
                        style: TextStyle(
                          color: Color(0xFFA78BFA),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                          hintText: 'Pesquise obras, títulos, hashes ou palavras-chave...',
                          hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onSubmitted: (_) => _executeSearch(),
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16, color: Color(0xFF94A3B8)),
                        onPressed: () {
                          _searchController.clear();
                          _executeSearch();
                        },
                      ),
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: _executeSearch,
                        child: const Text('Pesquisar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),

              // Painel expansível de filtros de categorias
              if (_isFilterDrawerOpen) _buildFilterPanel(),
            ],
          ),
        ),

        // Área dos resultados
        Expanded(
          child: _isSearching
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                      SizedBox(height: 12),
                      Text(
                        'Consultando índice de metadados...',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                )
              : (_searchErrorMessage != null)
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _searchErrorMessage!,
                          style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : (_searchResult == null || _searchResult!.records.isEmpty)
                      ? _buildEmptyResultsView()
                      : _buildResultsList(),
        ),
      ],
    );
  }

  Widget _modeChip(TorrentSearchMode mode) {
    final isSelected = _searchMode == mode;
    return ChoiceChip(
      label: Text(
        mode.label,
        style: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFF94A3B8),
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF7C3AED),
      backgroundColor: const Color(0xFF1E1E2E),
      onSelected: (_) {
        setState(() => _searchMode = mode);
        _executeSearch();
      },
    );
  }

  Widget _buildFilterPanel() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161622),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2D2D42)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(
            children: [
              const Text(
                'Filtrar por Categoria',
                style: TextStyle(color: Color(0xFFDDD6FE), fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_selectedCategories.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _selectedCategories.clear()),
                  child: const Text('Limpar', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 11)),
                ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final cat in TorrentCategory.values)
                FilterChip(
                  label: Text(cat.label, style: const TextStyle(fontSize: 11)),
                  selected: _selectedCategories.contains(cat),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedCategories.add(cat);
                      } else {
                        _selectedCategories.remove(cat);
                      }
                    });
                    _executeSearch();
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF2D2D42), height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'Mínimo de Seeds',
                style: TextStyle(color: Color(0xFFDDD6FE), fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_minSeeds > 0)
                TextButton(
                  onPressed: () {
                    setState(() => _minSeeds = 0);
                    _executeSearch();
                  },
                  child: const Text('Limpar', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 11)),
                ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in const [
                (0, 'Qualquer'),
                (1, '1+ seed'),
                (5, '5+ seeds'),
                (20, '20+ seeds'),
                (50, '50+ seeds'),
                (100, '100+ seeds'),
              ])
                ChoiceChip(
                  label: Text(entry.$2, style: const TextStyle(fontSize: 11)),
                  selected: _minSeeds == entry.$1,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _minSeeds = entry.$1);
                      _executeSearch();
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF2D2D42), height: 1),
          const SizedBox(height: 10),
          const Text(
            'Ordenar Resultados',
            style: TextStyle(color: Color(0xFFDDD6FE), fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final sort in TorrentSortOrder.values)
                ChoiceChip(
                  label: Text(sort.label, style: const TextStyle(fontSize: 11)),
                  selected: _sortOrder == sort,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _sortOrder = sort);
                      _executeSearch();
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    )));
  }

  Widget _buildEmptyResultsView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: const Color(0xFF64748B).withOpacity(0.5)),
          const SizedBox(height: 12),
          const Text(
            'Nenhum resultado encontrado.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tente alternar para "Índice Online" ou "Ao Vivo" para consultar fontes externas via Tor.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    final result = _searchResult!;
    return Column(
      children: [
        // Barra com contagem e paginação
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF0F0E17).withOpacity(0.5),
          child: Row(
            children: [
              Text(
                'Resultados: ${result.totalCount} torrents indexados',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontFamily: 'monospace'),
              ),
              if (result.isCached) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('CACHE', style: TextStyle(color: Color(0xFFC4B5FD), fontSize: 9.5, fontWeight: FontWeight.bold)),
                ),
              ],
              const Spacer(),
              // Paginação
              if (result.hasPreviousPage)
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, size: 18, color: Colors.white70),
                  onPressed: () => _executeSearch(page: result.page - 1),
                  tooltip: 'Página anterior',
                ),
              Text(
                'Página ${result.page} de ${result.totalPages}',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
              if (result.hasNextPage)
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white70),
                  onPressed: () => _executeSearch(page: result.page + 1),
                  tooltip: 'Próxima página',
                ),
            ],
          ),
        ),

        // Lista dos cartões
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: result.records.length,
            itemBuilder: (context, index) {
              final rec = result.records[index];
              return _buildTorrentCard(rec);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTorrentCard(TorrentIndexRecord rec) {
    final nixState = context.watch<NixState>();
    final matchingAcervo = nixState.userProfile.culturalItems.where((it) {
      final t = it.title.trim().toLowerCase();
      if (t.length < 3) return false;
      return rec.title.toLowerCase().contains(t);
    }).firstOrNull;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF13131F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF27273A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Badge de Categoria
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6D28D9).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF6D28D9).withOpacity(0.4)),
                ),
                child: Text(
                  rec.category.label,
                  style: const TextStyle(color: Color(0xFFDDD6FE), fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),

              // Badge do Acervo Cultural (Seção 6.2)
              if (matchingAcervo != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06B6D4).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF06B6D4).withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bookmark_added_rounded, size: 11, color: Color(0xFF22D3EE)),
                      const SizedBox(width: 3),
                      Text(
                        'Acervo: ${matchingAcervo.title}',
                        style: const TextStyle(color: Color(0xFF22D3EE), fontSize: 9.5, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // Título
              Expanded(
                child: Text(
                  rec.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Metadados reais (SEM DADOS FICTÍCIOS)
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _metaItem(Icons.sd_card_outlined, rec.formattedSize),
              _metaItem(Icons.calendar_today_outlined, rec.formattedDate),
              if (rec.seeders != null)
                _metaItem(
                  Icons.arrow_upward_rounded,
                  'Seeds: ${rec.seeders}',
                  color: const Color(0xFF34D399),
                ),
              if (rec.leechers != null)
                _metaItem(
                  Icons.arrow_downward_rounded,
                  'Peers: ${rec.leechers}',
                  color: const Color(0xFFF87171),
                ),
              // Fontes
              for (final p in rec.provenances)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    p.sourceName,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Ações do Cartão
          Row(
            children: [
              // Hash resumido
              if (rec.infoHashV1 != null)
                Text(
                  'Hash: ${rec.infoHashV1!.substring(0, 10)}...',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5, fontFamily: 'monospace'),
                ),
              const Spacer(),

              // Copiar Magnet
              if (rec.magnetUri != null)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFC084FC),
                    side: const BorderSide(color: Color(0xFF7C3AED)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: rec.magnetUri!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Link Magnet copiado com sucesso!'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.link_rounded, size: 14),
                  label: const Text('Copiar Magnet', style: TextStyle(fontSize: 11)),
                ),
              const SizedBox(width: 8),

              // Copiar Origem
              if (rec.sourceUrl != null)
                IconButton(
                  icon: const Icon(Icons.open_in_new_rounded, size: 16, color: Color(0xFF94A3B8)),
                  tooltip: 'Copiar URL de Origem',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: rec.sourceUrl!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('URL de origem copiada!'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaItem(IconData icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color ?? const Color(0xFF64748B)),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            color: color ?? const Color(0xFF94A3B8),
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // ABA 2: Nix Downloads (aria2 HTTP/HTTPS)
  // -------------------------------------------------------------
  Widget _buildDownloadsManagerTab() {
    return Column(
      children: [
        // Barra de ação: Adicionar download direto
        Container(
          padding: const EdgeInsets.all(14),
          color: const Color(0xFF0F0E17).withOpacity(0.5),
          child: Row(
            children: [
              const Icon(Icons.download_rounded, color: Color(0xFFA78BFA), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Fila de Downloads Diretos (HTTP/HTTPS com aria2)',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: _showAddDownloadDialog,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Adicionar URL', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),

        // Barra de diretório de downloads configurável
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          color: const Color(0xFF13111C),
          child: Row(
            children: [
              const Icon(Icons.folder_special_rounded, color: Color(0xFF94A3B8), size: 15),
              const SizedBox(width: 8),
              const Text('Destino: ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
              Expanded(
                child: Text(
                  _downloadController?.downloadDir ?? '',
                  style: const TextStyle(color: Color(0xFFDDD6FE), fontSize: 11, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.edit_rounded, size: 13, color: Color(0xFFA78BFA)),
                label: const Text('Alterar', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 11)),
                onPressed: _showChangeDownloadDirDialog,
              ),
            ],
          ),
        ),

        // Lista de downloads com visor retrô estilo Pager
        Expanded(
          child: _downloadTasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.downloading_rounded, size: 48, color: const Color(0xFF64748B).withOpacity(0.4)),
                      const SizedBox(height: 12),
                      const Text(
                        'Nenhum download ativo na fila.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Clique em "Adicionar URL" para iniciar uma transferência HTTP/HTTPS acelerada.',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _downloadTasks.length,
                  itemBuilder: (context, index) {
                    final task = _downloadTasks[index];
                    return _buildDownloadVisorCard(task);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDownloadVisorCard(DownloadTask task) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4C1D95).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho da tarefa
          Row(
            children: [
              Icon(
                task.isExecutable ? Icons.extension_rounded : Icons.insert_drive_file_outlined,
                color: const Color(0xFFC4B5FD),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.fileName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Motor Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.4)),
                ),
                child: Text(
                  task.downloadEngine,
                  style: const TextStyle(color: Color(0xFFC4B5FD), fontSize: 9.5, fontWeight: FontWeight.bold),
                ),
              ),
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor(task.status).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _statusColor(task.status).withOpacity(0.5)),
                ),
                child: Text(
                  task.status.label,
                  style: TextStyle(color: _statusColor(task.status), fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Barra de progresso segmentada estilo visor digital (Pixel OLED)
          _buildSegmentedProgressBar(task.progressFraction),
          const SizedBox(height: 8),

          // Linha de métricas: Tamanho, Velocidade e ETA
          Row(
            children: [
              Text(
                task.formattedProgressBytes,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontFamily: 'monospace'),
              ),
              const Spacer(),
              if (task.status == DownloadStatus.downloading) ...[
                Text(
                  '⚡ ${task.formattedSpeed}',
                  style: const TextStyle(color: Color(0xFF34D399), fontSize: 11, fontFamily: 'monospace'),
                ),
                if (task.averageSpeedBytesPerSec > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Média: ${task.formattedAverageSpeed}',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontFamily: 'monospace'),
                  ),
                ],
                const SizedBox(width: 8),
                Text(
                  '(${task.activeSegments > 0 ? task.activeSegments : task.splitCount} seg)',
                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontFamily: 'monospace'),
                ),
                const SizedBox(width: 10),
                Text(
                  'ETA: ${task.formattedEta}',
                  style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 11, fontFamily: 'monospace'),
                ),
              ] else if (task.status == DownloadStatus.finalizing) ...[
                const Text(
                  '⚡ Montando e validando arquivo final...',
                  style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ],
          ),

          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Row(
              children: [
                const Icon(Icons.folder_outlined, size: 12, color: Color(0xFF64748B)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    task.destinationPath,
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 10, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          if (task.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              task.errorMessage!,
              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFA78BFA),
                    side: const BorderSide(color: Color(0xFF7C3AED)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: const Text('Tentar novamente via Tor', style: TextStyle(fontSize: 11)),
                  onPressed: () => _downloadController?.resumeDownload(task.id),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  icon: const Icon(Icons.public_rounded, size: 14),
                  label: const Text('Baixar fora da rede Tor (Clearnet)', style: TextStyle(fontSize: 11)),
                  onPressed: () => _downloadController?.retryDownloadWithClearnet(task.id),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),

          // Botões de controle da tarefa
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (task.status == DownloadStatus.pausing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber)),
                      SizedBox(width: 6),
                      Text('Pausando...', style: TextStyle(color: Colors.amber, fontSize: 11)),
                    ],
                  ),
                )
              else if (task.status == DownloadStatus.resuming)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF34D399))),
                      SizedBox(width: 6),
                      Text('Retomando...', style: TextStyle(color: Color(0xFF34D399), fontSize: 11)),
                    ],
                  ),
                )
              else if (task.status == DownloadStatus.downloading)
                IconButton(
                  icon: const Icon(Icons.pause_rounded, size: 18, color: Colors.amber),
                  tooltip: 'Pausar transferência',
                  onPressed: () => _downloadController?.pauseDownload(task.id),
                )
              else if (task.status == DownloadStatus.paused)
                IconButton(
                  icon: const Icon(Icons.play_arrow_rounded, size: 18, color: Color(0xFF34D399)),
                  tooltip: 'Retomar transferência',
                  onPressed: () => _downloadController?.resumeDownload(task.id),
                ),
              if (task.status == DownloadStatus.completed) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  icon: const Icon(Icons.file_open_outlined, size: 14),
                  label: const Text('Abrir Arquivo', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    SafeFileOpeningDialog.show(context, task, () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Abrindo: ${task.destinationPath}')),
                      );
                    });
                  },
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDDD6FE),
                    side: const BorderSide(color: Color(0xFF4C1D95)),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  icon: const Icon(Icons.folder_open_rounded, size: 14),
                  label: const Text('Abrir Pasta', style: TextStyle(fontSize: 11)),
                  onPressed: () async {
                    final parentDir = File(task.destinationPath).parent.path;
                    try {
                      if (Platform.isLinux) {
                        await Process.run('xdg-open', [parentDir]);
                      }
                    } catch (_) {}
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Pasta: $parentDir')),
                      );
                    }
                  },
                ),
              ],
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFF94A3B8)),
                tooltip: 'Remover da fila',
                onPressed: () async {
                  await _downloadController?.removeDownload(task.id, deleteFile: false);
                  if (mounted) {
                    setState(() {
                      _downloadTasks = List.from(_downloadController?.tasks ?? []);
                    });
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedProgressBar(double fraction) {
    const totalSegments = 24;
    final filledSegments = (fraction * totalSegments).round().clamp(0, totalSegments);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          for (var i = 0; i < totalSegments; i++) ...[
            Expanded(
              child: Container(
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: i < filledSegments ? const Color(0xFFA78BFA) : const Color(0xFF1F1F2E),
                  borderRadius: BorderRadius.circular(1.5),
                  boxShadow: i < filledSegments
                      ? [
                          BoxShadow(
                            color: const Color(0xFFA78BFA).withOpacity(0.5),
                            blurRadius: 3,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          Text(
            '${(fraction * 100).toInt()}%',
            style: const TextStyle(
              color: Color(0xFFDDD6FE),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.downloading:
        return const Color(0xFF34D399);
      case DownloadStatus.finalizing:
        return const Color(0xFF38BDF8);
      case DownloadStatus.paused:
        return Colors.amber;
      case DownloadStatus.completed:
        return const Color(0xFFA78BFA);
      case DownloadStatus.failed:
        return const Color(0xFFEF4444);
      case DownloadStatus.cancelled:
        return const Color(0xFF64748B);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  void _showAddDownloadDialog() {
    final urlCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final hashCtrl = TextEditingController();
    String? validationError;
    bool allowClearnet = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF13131F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
            ),
            title: const Row(
              children: [
                Icon(Icons.add_link_rounded, color: Color(0xFFA78BFA), size: 22),
                SizedBox(width: 8),
                Text('Adicionar Download Direto', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Insira uma URL direta com protocolo HTTP ou HTTPS. '
                    'Downloads BitTorrent foram desabilitados para manter a privacidade do usuário.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: urlCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'URL de Download (HTTP/HTTPS)',
                      labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      final clean = val.trim().toLowerCase();
                      if (clean.startsWith('magnet:?') || clean.startsWith('torrent:')) {
                        setDlgState(() {
                          validationError =
                              'O Nix Downloads utiliza aria2 exclusivamente para downloads diretos HTTP/HTTPS. '
                              'Transferências BitTorrent/magnets via Tor foram desabilitadas para evitar vazamento de IP.';
                        });
                      } else {
                        setDlgState(() {
                          validationError = null;
                          if (clean.contains('.onion')) {
                            allowClearnet = false;
                          } else if (clean.startsWith('http://') || clean.startsWith('https://')) {
                            allowClearnet = true;
                          }
                        });
                      }
                    },
                  ),
                  if (validationError != null) ...[
                    const SizedBox(height: 8),
                    Text(validationError!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11)),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Nome do Arquivo (Opcional)',
                      labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: hashCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Hash SHA-256 Esperado (Opcional)',
                      labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Baixar fora da rede Tor (Clearnet Direta)',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      'Selecione caso o servidor de download rejeite conexões Onion v3 ou para acelerar transferências de arquivos públicos.',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                    ),
                    value: allowClearnet,
                    onChanged: (v) => setDlgState(() => allowClearnet = v ?? false),
                    activeColor: const Color(0xFF7C3AED),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                ),
                onPressed: validationError != null || urlCtrl.text.trim().isEmpty
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final url = urlCtrl.text.trim();
                        final name = nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : null;
                        final sha = hashCtrl.text.trim().isNotEmpty ? hashCtrl.text.trim() : null;

                        Navigator.of(ctx).pop();
                        try {
                          await _downloadController?.addDownload(
                            url: url,
                            customFileName: name,
                            sha256Expected: sha,
                            allowClearnet: allowClearnet,
                            transportProfile: allowClearnet ? 'direct_https' : 'tor_socks5',
                          );
                        } catch (e) {
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Falha ao adicionar download: $e')),
                            );
                          }
                        }
                      },
                child: const Text('Iniciar Transferência'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showChangeDownloadDirDialog() {
    final currentDir = _downloadController?.downloadDir ?? '';
    final ctrl = TextEditingController(text: currentDir);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF13131F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
        ),
        title: const Row(
          children: [
            Icon(Icons.folder_special_rounded, color: Color(0xFFA78BFA), size: 20),
            SizedBox(width: 8),
            Text('Alterar Pasta de Download', style: TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Escolha a pasta onde os arquivos baixados pelo Nix Downloads serão salvos.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                labelText: 'Caminho Completo',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                filled: true,
                fillColor: Color(0xFF1E1E2E),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final newPath = ctrl.text.trim();
              if (newPath.isNotEmpty) {
                _downloadController?.setDownloadDir(newPath);
                setState(() {});
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // ABA 3: Fontes & Conectores
  // -------------------------------------------------------------
  Widget _buildSourcesManagerTab() {
    final sources = _sourcesManager?.listSources() ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Painel de Atualizações do Índice Offline
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF13131F),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2E2248)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.system_update_alt_rounded, color: Color(0xFFA78BFA), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Catálogo Offline & Pacotes Assinados',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Registros Indexados Localmente: $_totalLocalRecords',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'Última Sincronização: ${_lastSyncDate != null ? _lastSyncDate!.toIso8601String().substring(0, 10) : "Nunca sincronizado"}',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(
              child: Text(
                'Conectores e Indexadores Registrados',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Configurar Torznab / Newznab', style: TextStyle(fontSize: 11)),
              onPressed: () => _showConfigureTorznabDialog(
                _sourcesManager?.getSourceConfig('torznab_custom') ??
                    const TorrentIndexerSourceConfig(
                      id: 'torznab_custom',
                      name: 'Torznab / Prowlarr Local',
                      url: 'http://127.0.0.1:9696',
                      type: IndexerSourceType.torznab,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        for (final src in sources) ...[
          _buildSourceCard(src),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildSourceCard(TorrentIndexerSourceConfig src) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF13131F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF27273A)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        src.name,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        src.type.label,
                        style: const TextStyle(color: Color(0xFFC4B5FD), fontSize: 9.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  src.url,
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontFamily: 'monospace'),
                ),
                if (src.statusMessage != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    src.statusMessage!,
                    style: TextStyle(
                      color: src.isAvailable ? const Color(0xFF34D399) : const Color(0xFFF87171),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (src.type == IndexerSourceType.torznab) ...[
            IconButton(
              icon: const Icon(Icons.tune_rounded, size: 18, color: Color(0xFFC4B5FD)),
              tooltip: 'Configurar URL e API Key',
              onPressed: () => _showConfigureTorznabDialog(src),
            ),
            const SizedBox(width: 4),
          ],
          // Botão Testar Conexão
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC4B5FD),
              side: const BorderSide(color: Color(0xFF475569)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            onPressed: () async {
              final ok = await _sourcesManager?.testSource(src.id) ?? false;
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Conexão com ${src.name} bem-sucedida!' : 'Falha na resposta de ${src.name}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('Testar', style: TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 8),
          // Switch Ativo/Inativo
          Switch(
            value: src.isEnabled,
            activeColor: const Color(0xFF7C3AED),
            onChanged: (val) {
              _sourcesManager?.setSourceEnabled(src.id, val);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  void _showConfigureTorznabDialog(TorrentIndexerSourceConfig src) {
    final nameCtrl = TextEditingController(text: src.name);
    final urlCtrl = TextEditingController(text: src.url);
    final keyCtrl = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF13131F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
          ),
          title: Row(
            children: [
              const Icon(Icons.tune_rounded, color: Color(0xFFA78BFA), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Configurar ${src.name}',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Insira a URL do indexador Torznab / Newznab (ex: Prowlarr, Jackett, NZBHydra2, NZBPlanet, Usenet) e a chave de API.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Nome do Indexador',
                    labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'URL Base do Endpoint (ex: http://127.0.0.1:9696)',
                    labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Chave de API (API Key)',
                    labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
              ),
              onPressed: isSaving || urlCtrl.text.trim().isEmpty
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      setDlgState(() => isSaving = true);
                      _sourcesManager?.configureTorznabSource(
                        id: src.id,
                        name: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : src.name,
                        url: urlCtrl.text.trim(),
                        apiKey: keyCtrl.text.trim().isNotEmpty ? keyCtrl.text.trim() : null,
                        isEnabled: true,
                      );
                      final testOk = await _sourcesManager?.testSource(src.id) ?? false;
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      if (mounted) {
                        setState(() {});
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(testOk
                                ? 'Indexador ${nameCtrl.text.trim()} configurado e testado com sucesso!'
                                : 'Indexador salvo. Verifique a URL e a chave de API.'),
                          ),
                        );
                      }
                    },
              child: Text(isSaving ? 'Testando...' : 'Salvar e Conectar'),
            ),
          ],
        ),
      ),
    );
  }
}
