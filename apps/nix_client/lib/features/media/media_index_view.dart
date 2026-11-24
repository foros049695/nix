import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nix_transport/nix_transport.dart';
import '../../core/media/catalog_database.dart';
import '../../core/media/catalog_diagnostics.dart';
import '../../core/media/media_index_updater.dart';
import '../../core/media/pager_playlist.dart';
import '../../core/models/cultural_item.dart';
import '../../core/security/file_picker_adapter.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_palette.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../design/nix_surfaces.dart';
import '../profile/cultural_showcase.dart';
import '../profile/desktop_pager_audio.dart';
import '../navigation/interface_wallpaper_layer.dart';

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
  bool _isLoading = false;
  String? _catalogError;
  int _searchGeneration = 0;

  final List<({String label, String? kind, IconData icon})> _kindFilters = [
    (label: 'Todas', kind: null, icon: Icons.all_inclusive_rounded),
    (label: 'Filmes', kind: 'movie', icon: Icons.movie_outlined),
    (label: 'Séries', kind: 'series', icon: Icons.tv_rounded),
    (label: 'Animes', kind: 'anime', icon: Icons.animation_rounded),
    (label: 'Mangás', kind: 'manga', icon: Icons.menu_book_rounded),
    (label: 'Livros', kind: 'book', icon: Icons.auto_stories_rounded),
    (label: 'Álbuns', kind: 'album', icon: Icons.album_outlined),
    (label: 'Faixas', kind: 'track', icon: Icons.music_note_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _executeSearch();
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
      _catalogError = null;
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
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _catalogError = error is FormatException
            ? error.message
            : 'Falha ao abrir ou consultar o banco local do catálogo.';
        _isLoading = false;
      });
    }
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
      if (!mounted) return;
      try {
        await _nixState.saveCatalogWork(work, status: status,
          rating: rating.toInt(), notes: notesCtrl.text.trim());
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar no Acervo.')));
        return;
      }
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

  Future<void> _showEditPublisherUrlDialog(
    BuildContext parentCtx,
    NixState nixState,
    void Function(void Function()) setParentDlgState,
  ) async {
    final textController = TextEditingController(text: nixState.catalogManifestUrl);
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: parentCtx,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: NixColors.surfaceCard,
          shape: RoundedRectangleBorder(borderRadius: NixTokens.borderMd),
          title: Text(
            'Configurar Publicador Onion',
            style: TextStyle(color: NixColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Insira a URL do manifesto assinado (.onion v3 para Tor ou https:// para espelho seguro). Todo pacote tem assinatura Ed25519 verificada.',
                  style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: textController,
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'URL do Manifesto (.onion ou https://)',
                    labelStyle: TextStyle(color: NixColors.textSecondary),
                    filled: true,
                    fillColor: NixColors.surfaceSidebar,
                    border: OutlineInputBorder(borderRadius: NixTokens.borderSm),
                  ),
                  validator: (value) {
                    final clean = value?.trim() ?? '';
                    final uri = Uri.tryParse(clean);
                    if (uri == null ||
                        (uri.scheme != 'http' && uri.scheme != 'https')) {
                      return 'URL inválida. Deve começar com http:// ou https://';
                    }
                    if (uri.scheme == 'http' && !TransportPolicy.isValidOnionV3Host(uri.host)) {
                      return 'Conexões HTTP simples são restritas a endereços .onion v3.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.vpn_lock_rounded, size: 14),
                      label: const Text('Publicador Tor (.onion)', style: TextStyle(fontSize: 11)),
                      onPressed: () {
                        textController.text = CatalogPublisherKeyring.defaultOfficialManifestUrl;
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.public_rounded, size: 14),
                      label: const Text('Espelho Oficial HTTPS', style: TextStyle(fontSize: 11)),
                      onPressed: () {
                        textController.text = MediaIndexUpdater.officialHttpsManifestUrl;
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text('Cancelar', style: TextStyle(color: NixColors.textSecondary)),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
              child: const Text('Salvar'),
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  await nixState.setCatalogManifestUrl(textController.text.trim());
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  setParentDlgState(() {});
                }
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildDiagnosticChecklistView(CatalogDiagnosticReport report) {
    Widget layerTile(String title, DiagnosticStatus status, String details) {
      Color color;
      IconData icon;
      switch (status) {
        case DiagnosticStatus.passed:
          color = const Color(0xFF34D399);
          icon = Icons.check_circle_outline_rounded;
          break;
        case DiagnosticStatus.warning:
          color = const Color(0xFFFBBF24);
          icon = Icons.warning_amber_rounded;
          break;
        case DiagnosticStatus.failed:
          color = const Color(0xFFF87171);
          icon = Icons.error_outline_rounded;
          break;
        case DiagnosticStatus.skipped:
          color = const Color(0xFF94A3B8);
          icon = Icons.schedule_rounded;
          break;
      }

      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF161524),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          status.label,
                          style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    details,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        layerTile('1. Daemon Tor Local', report.torDaemon, report.torDaemonDetails),
        layerTile('2. Túnel SOCKS5 (RFC 1928)', report.socks5Handshake, report.socks5HandshakeDetails),
        layerTile('3. Serviço Onion Remoto', report.remoteOnion, report.remoteOnionDetails),
        layerTile('4. Download do Manifesto', report.manifestFetch, report.manifestFetchDetails),
        layerTile('5. Assinatura Ed25519', report.ed25519Signature, report.ed25519SignatureDetails),
        layerTile('6. Integridade Anti-Rollback', report.antiRollback, report.antiRollbackDetails),
      ],
    );
  }

  Future<void> _openCatalogUpdateDialog() async {
    final nixState = _nixState;
    final updateManager = nixState.catalogUpdateManager;
    void useTorPort() {
      updateManager.transportPolicy = TransportPolicy(
        socksPort: nixState.embeddedTor.socksPort,
      );
    }
    String? localError;
    CatalogDiagnosticReport? diagnosticReport;
    bool showDiagnosticDetails = false;

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
                final source = state.catalogManifestUrl;
                final manifestUri = Uri.tryParse(source);
                final isHttpsSource = manifestUri != null && manifestUri.scheme == 'https';
                final configured = manifestUri != null &&
                    (manifestUri.scheme == 'http' || manifestUri.scheme == 'https') &&
                    (TransportPolicy.isValidOnionV3Host(manifestUri.host) || isHttpsSource) &&
                    manifestUri.userInfo.isEmpty &&
                    !manifestUri.hasFragment;
                final hasTrustedKey = updateManager.keyring.trustedKeysHex.isNotEmpty;
                final isTorReady = state.securityGate.isTorAnonymityReady ||
                    state.securityGate.torOnionV3Ready ||
                    !state.enforceStartupGate ||
                    state.embeddedTor.socksPort > 0;
                final available = configured && hasTrustedKey &&
                    !state.isStrictOffGridMode && (isTorReady || isHttpsSource);
                final accent = context.accentTextColor;
                final errorColor = NixPalette.crimson.readableAccentOn(context.nixScheme);
                final sourceStatus = !configured
                    ? 'URL do publicador inválida ou não configurada.'
                    : !hasTrustedKey
                        ? 'A chave pública do publicador não foi configurada.'
                        : available
                            ? (isHttpsSource
                                ? 'Espelho Oficial HTTPS: ${manifestUri.host}\nConexão segura com assinatura Ed25519.'
                                : 'Publicador configurado: ${manifestUri.host}\nConexão via Tor.')
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
                                    IconButton(
                                      tooltip: 'Configurar URL do Publicador Onion',
                                      icon: Icon(Icons.edit_outlined, size: 16, color: accent),
                                      onPressed: isUpdating
                                          ? null
                                          : () => _showEditPublisherUrlDialog(ctx, state, setDlgState),
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
                          if (localError != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(localError!, style: TextStyle(color: errorColor, fontSize: 12)),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.public_rounded, size: 14),
                                        label: const Text('Verificar via Espelho HTTPS', style: TextStyle(fontSize: 11)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.amber,
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        ),
                                        onPressed: isUpdating
                                            ? null
                                            : () async {
                                                setDlgState(() => localError = null);
                                                try {
                                                  final mirrorUri = Uri.parse(MediaIndexUpdater.officialHttpsManifestUrl);
                                                  await updateManager.checkForUpdate(manifestUri: mirrorUri, allowClearnet: true);
                                                } catch (err) {
                                                  if (ctx.mounted) {
                                                    setDlgState(() => localError = 'Falha no espelho HTTPS: $err');
                                                  }
                                                }
                                                if (ctx.mounted) setDlgState(() {});
                                              },
                                      ),
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.offline_bolt_rounded, size: 14),
                                        label: const Text('Sincronizar Catálogo Integrado', style: TextStyle(fontSize: 11)),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        ),
                                        onPressed: isUpdating
                                            ? null
                                            : () async {
                                                setDlgState(() => localError = null);
                                                try {
                                                  final newDb = await updateManager.syncBundledCatalog();
                                                  await newDb.installBundledMusic();
                                                  nixState.setCatalogDatabase(newDb);
                                                  currentVer = await updateManager.getInstalledVersion();
                                                  history = await updateManager.getVersionHistory();
                                                  if (mounted) await _executeSearch();
                                                  if (ctx.mounted) setDlgState(() => localError = null);
                                                } catch (err) {
                                                  if (ctx.mounted) {
                                                    setDlgState(() => localError = 'Falha ao sincronizar catálogo: $err');
                                                  }
                                                }
                                                if (ctx.mounted) setDlgState(() {});
                                              },
                                      ),
                                    ],
                                  ),
                                  if (diagnosticReport != null) ...[
                                    const SizedBox(height: 10),
                                    InkWell(
                                      onTap: () => setDlgState(() => showDiagnosticDetails = !showDiagnosticDetails),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(showDiagnosticDetails ? Icons.expand_less : Icons.expand_more, size: 16, color: accent),
                                          const SizedBox(width: 4),
                                          Text(
                                            showDiagnosticDetails ? 'Ocultar Diagnóstico em Camadas' : 'Ver Diagnóstico em Camadas (Tor & Onion)',
                                            style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (showDiagnosticDetails) ...[
                                      const SizedBox(height: 8),
                                      _buildDiagnosticChecklistView(diagnosticReport!),
                                      const SizedBox(height: 4),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton.icon(
                                          icon: const Icon(Icons.copy_rounded, size: 13),
                                          label: const Text('Copiar Diagnóstico', style: TextStyle(fontSize: 10.5)),
                                          onPressed: () {
                                            Clipboard.setData(ClipboardData(text: diagnosticReport!.toSanitizedSummary()));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Diagnóstico sanitizado copiado!'), duration: Duration(seconds: 2)),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ] else if (currentProgress.stage == CatalogUpdateStage.completed ||
                              currentProgress.stage == CatalogUpdateStage.upToDate) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF34D399), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      currentProgress.statusMessage,
                                      style: const TextStyle(color: Color(0xFF34D399), fontSize: 12, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ] else if (currentProgress.statusMessage.isNotEmpty && currentProgress.stage != CatalogUpdateStage.error) ...[
                            Text(
                              currentProgress.statusMessage,
                              style: TextStyle(
                                color: NixColors.textPrimary,
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
                            final isHttps = manifestUri.scheme == 'https';
                            final newDb = await updateManager.downloadAndApplyUpdate(
                              manifest: manifest,
                              packageUri: manifestUri.resolve(package),
                              allowClearnet: isHttps,
                            );
                            await newDb.installBundledMusic();
                            nixState.setCatalogDatabase(newDb);
                            currentVer = await updateManager.getInstalledVersion();
                            history = await updateManager.getVersionHistory();
                            if (mounted) await _executeSearch();
                            if (ctx.mounted) setDlgState(() {});
                          } catch (e) {
                            if (ctx.mounted) {
                              setDlgState(() => localError = 'Falha ao aplicar atualização: $e');
                            }
                          }
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
                            final isHttps = manifestUri.scheme == 'https';

                            CatalogDiagnosticReport? report;
                            try {
                              report = await CatalogDiagnostics.runDiagnostics(
                                manifestUri: manifestUri,
                                socksPort: state.embeddedTor.socksPort > 0 ? state.embeddedTor.socksPort : 9050,
                                keyring: updateManager.keyring,
                                installedVersion: currentVer,
                              );
                              diagnosticReport = report;
                            } catch (_) {}

                            try {
                              await updateManager.checkForUpdate(manifestUri: manifestUri, allowClearnet: isHttps);
                            } catch (e) {
                              if (report != null && report.isPlaceholderOnion) {
                                setDlgState(() => localError =
                                    'Publicador Onion v3 de demonstração configurado (${manifestUri.host}).\n'
                                    'O serviço remoto ainda não está publicado na rede Tor global.\n'
                                    'Sua conexão Tor local e o proxy SOCKS5 estão operando com 100% de integridade.');
                              } else if (report != null && report.socks5Handshake == DiagnosticStatus.passed && report.remoteOnion != DiagnosticStatus.passed) {
                                setDlgState(() => localError =
                                    'O serviço Onion (${manifestUri.host}) está offline ou seu descritor não está disponível na rede Tor.\n'
                                    'Sua conexão Tor local está funcionando normalmente.');
                              } else if (manifestUri.host.endsWith('.onion')) {
                                setDlgState(() => localError =
                                    'Publicador Onion v3 offline ou sem circuito Tor ativo ($e).\n'
                                    'Você pode verificar via Espelho Seguro HTTPS ou Catálogo Integrado.');
                              } else {
                                rethrow;
                              }
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              setDlgState(() => localError = 'Falha ao verificar atualizações: $e');
                            }
                          }
                          if (ctx.mounted) setDlgState(() {});
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

    final isGlass = InterfaceWallpaperLayer.translucentPanelsOf(context);

    return Scaffold(
      backgroundColor: isGlass ? Colors.transparent : NixColors.background,
      appBar: AppBar(
        backgroundColor: isGlass
            ? NixColors.surfaceCard.withValues(
                alpha: InterfaceWallpaperLayer.panelOpacityOf(context))
            : NixColors.surfaceCard,
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
              text: 'Meu Acervo Pessoal (${context.watch<NixState>().userProfile.culturalItems.length})',
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
                        showCheckmark: false,
                        avatar: Icon(
                          f.icon,
                          size: 14,
                          color: isSelected ? context.onAccentColor : NixColors.textSecondary,
                        ),
                        label: Text(f.label),
                        labelStyle: TextStyle(
                          color: isSelected ? context.onAccentColor : NixColors.textPrimary,
                          fontSize: 11.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        backgroundColor: NixColors.surfaceSidebar,
                        selectedColor: context.accentColor,
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
              : _catalogError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_catalogError!, textAlign: TextAlign.center),
                            TextButton.icon(
                              onPressed: _executeSearch,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Tentar novamente'),
                            ),
                          ],
                        ),
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

  void _showWorkDetails(BuildContext context, CatalogWork work) {
    final nixState = context.read<NixState>();
    showDialog<void>(
      context: context,
      builder: (ctx) => _CatalogWorkDetailDialog(work: work, nixState: nixState),
    );
  }

  Widget _buildWorkCard(CatalogWork work) {
    final nixState = context.watch<NixState>();
    final inAcervo = nixState.userProfile.culturalItems.any(
      (item) =>
          item.id == 'catalog:${work.id}' ||
          item.id == work.id ||
          item.title.trim().toLowerCase() == work.title.trim().toLowerCase(),
    );

    final kindIcon = switch (work.kind) {
      'movie' || 'film' => Icons.movie_outlined,
      'series' => Icons.tv_rounded,
      'anime' => Icons.animation_rounded,
      'manga' => Icons.menu_book_rounded,
      'book' => Icons.auto_stories_rounded,
      'album' => Icons.album_outlined,
      'track' => Icons.music_note_outlined,
      _ => Icons.bookmark_outline_rounded,
    };

    final kindColor = switch (work.kind) {
      'movie' || 'film' => Colors.blueAccent,
      'series' => Colors.purpleAccent,
      'anime' => Colors.pinkAccent,
      'manga' => Colors.orangeAccent,
      'book' => Colors.greenAccent,
      'album' || 'track' => Colors.cyanAccent,
      _ => Colors.amber,
    };

    return NixMotionCard(
      child: InkWell(
        onTap: () => _showWorkDetails(context, work),
        borderRadius: NixTokens.borderMd,
        child: NixFrame(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Placeholder Seguro de Capa clicável
                InkWell(
                  onTap: () => _showWorkDetails(context, work),
                  borderRadius: NixTokens.borderSm,
                  child: Container(
                    width: 54,
                    height: 74,
                    decoration: BoxDecoration(
                      color: kindColor.withValues(alpha: 0.12),
                      borderRadius: NixTokens.borderSm,
                      border: Border.all(color: kindColor.withValues(alpha: 0.3)),
                    ),
                    child: Center(
                      child: Icon(kindIcon, size: 28, color: kindColor),
                    ),
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
                              color: kindColor.withValues(alpha: 0.15),
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
                      InkWell(
                        onTap: () => _showWorkDetails(context, work),
                        child: Text(
                          work.title,
                          style: TextStyle(
                            color: NixColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
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
                // Botão Adicionar ou Ver no Acervo
                IconButton(
                  icon: Icon(
                    inAcervo ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
                    color: inAcervo ? Colors.amber : Colors.amber.withValues(alpha: 0.7),
                  ),
                  tooltip: inAcervo ? 'No meu Acervo (Ver detalhes)' : 'Adicionar ao Acervo',
                  onPressed: () {
                    if (inAcervo) {
                      _showWorkDetails(context, work);
                    } else {
                      _openAddToAcervoDialog(work);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAcervoTab(bool isCompact) {
    return const SingleChildScrollView(child: CulturalShowcase());
  }
}

class _CatalogWorkDetailDialog extends StatefulWidget {
  final CatalogWork work;
  final NixState nixState;

  const _CatalogWorkDetailDialog({required this.work, required this.nixState});

  @override
  State<_CatalogWorkDetailDialog> createState() => _CatalogWorkDetailDialogState();
}

class _CatalogWorkDetailDialogState extends State<_CatalogWorkDetailDialog> {
  late final _desktop = switch (defaultTargetPlatform) {
    TargetPlatform.linux || TargetPlatform.windows => DesktopPagerAudio(),
    _ => null,
  };
  List<PagerTrack> _playlistTracks = [];
  String? _playingUri;
  bool _loadingAudio = false;

  @override
  void initState() {
    super.initState();
    _loadPlaylist();
  }

  @override
  void dispose() {
    _desktop?.stop();
    super.dispose();
  }

  Future<void> _loadPlaylist() async {
    final playlist = widget.nixState.pagerPlaylist;
    if (playlist != null) {
      try {
        final tracks = await playlist.load();
        if (mounted) {
          setState(() {
            _playlistTracks = tracks;
          });
        }
      } catch (_) {}
    }
  }

  CulturalItem? _findInAcervo(NixState state) {
    final draftId = 'catalog:${widget.work.id}';
    for (final item in state.userProfile.culturalItems) {
      if (item.id == draftId || item.id == widget.work.id) return item;
      if (item.title.trim().toLowerCase() == widget.work.title.trim().toLowerCase()) return item;
    }
    return null;
  }

  Future<void> _toggleAudio(PagerTrack track) async {
    if (_playingUri == track.uri) {
      _desktop?.stop();
      if (defaultTargetPlatform != TargetPlatform.linux && defaultTargetPlatform != TargetPlatform.windows) {
        await const MethodChannel('com.projetonix.nix/pager_audio').invokeMethod<void>('stop');
      }
      if (mounted) setState(() => _playingUri = null);
      return;
    }
    setState(() => _loadingAudio = true);
    try {
      if (_desktop != null) {
        await _desktop!.play(track);
        if (mounted) setState(() => _playingUri = track.uri);
      } else {
        await const MethodChannel('com.projetonix.nix/pager_audio').invokeMethod<void>('play', {'uri': track.uri});
        if (mounted) setState(() => _playingUri = track.uri);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falha ao reproduzir áudio local.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingAudio = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.nixState,
      builder: (dialogCtx, _) {
        final nixState = widget.nixState;
        final work = widget.work;
        final acervoItem = _findInAcervo(nixState);
        final inAcervo = acervoItem != null;

    final kindIcon = switch (work.kind) {
      'movie' || 'film' => Icons.movie_outlined,
      'series' => Icons.tv_rounded,
      'anime' => Icons.animation_rounded,
      'manga' => Icons.menu_book_rounded,
      'book' => Icons.auto_stories_rounded,
      'album' => Icons.album_outlined,
      'track' => Icons.music_note_outlined,
      _ => Icons.bookmark_outline_rounded,
    };

    final kindColor = switch (work.kind) {
      'movie' || 'film' => Colors.blueAccent,
      'series' => Colors.purpleAccent,
      'anime' => Colors.pinkAccent,
      'manga' => Colors.orangeAccent,
      'book' => Colors.greenAccent,
      'album' || 'track' => Colors.cyanAccent,
      _ => Colors.amber,
    };

    final isMusic = work.kind == 'track' || work.kind == 'album' || work.kind == 'music';
    final matchingTracks = isMusic
        ? _playlistTracks
            .where((t) => t.name.toLowerCase().contains(work.title.toLowerCase()))
            .toList()
        : const <PagerTrack>[];

    return Dialog(
      backgroundColor: NixColors.surfaceCard,
      shape: RoundedRectangleBorder(borderRadius: NixTokens.borderMd),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Column(
          children: [
            // Header com Barra de Fechar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: kindColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: kindColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(kindIcon, size: 13, color: kindColor),
                        const SizedBox(width: 4),
                        Text(
                          work.kind.toUpperCase(),
                          style: TextStyle(color: kindColor, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  if (work.releaseYear != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${work.releaseYear}',
                      style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: NixColors.textSecondary),
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Conteúdo Rolável
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Capa + Título + Criadores
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 80,
                        height: 110,
                        decoration: BoxDecoration(
                          color: kindColor.withValues(alpha: 0.12),
                          borderRadius: NixTokens.borderSm,
                          border: Border.all(color: kindColor.withValues(alpha: 0.3)),
                        ),
                        child: Center(
                          child: Icon(kindIcon, size: 40, color: kindColor),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              work.title,
                              style: TextStyle(
                                color: NixColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (work.originalTitle != null && work.originalTitle != work.title) ...[
                              const SizedBox(height: 3),
                              Text(
                                work.originalTitle!,
                                style: TextStyle(
                                  color: NixColors.textSecondary,
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                            if (work.creators != null && work.creators!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.person_outline_rounded, size: 14, color: NixColors.textMuted),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      work.creators!,
                                      style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Gêneros
                  if (work.genres != null && work.genres!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('GÊNEROS', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: work.genres!
                          .split(',')
                          .map((g) => g.trim())
                          .where((g) => g.isNotEmpty)
                          .map((genre) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: NixColors.surfaceCardHover,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: NixColors.surfaceBorder),
                                ),
                                child: Text(
                                  genre,
                                  style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                                ),
                              ))
                          .toList(),
                    ),
                  ],

                  // Sinopse
                  if (work.summary != null && work.summary!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('SINOPSE & DETALHES', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: NixColors.surfaceSidebar,
                        borderRadius: NixTokens.borderSm,
                        border: Border.all(color: NixColors.surfaceBorder),
                      ),
                      child: Text(
                        work.summary!,
                        style: TextStyle(color: NixColors.textSecondary, fontSize: 12.5, height: 1.45),
                      ),
                    ),
                  ],

                  // Músicas & Álbuns
                  if (isMusic) ...[
                    const SizedBox(height: 16),
                    Text('ÁUDIO & FAIXAS LOCAIS', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    if (matchingTracks.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.08),
                          borderRadius: NixTokens.borderSm,
                          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.music_note_rounded, size: 16, color: Colors.cyanAccent),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Faixa de áudio local disponível',
                                    style: TextStyle(
                                      color: NixColors.textPrimary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final track in matchingTracks)
                              Row(
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      _playingUri == track.uri ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                                      color: Colors.cyanAccent,
                                      size: 26,
                                    ),
                                    onPressed: _loadingAudio ? null : () => _toggleAudio(track),
                                    tooltip: _playingUri == track.uri ? 'Parar reprodução' : 'Reproduzir áudio local',
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      track.name,
                                      style: TextStyle(color: NixColors.textPrimary, fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: NixColors.surfaceSidebar,
                          borderRadius: NixTokens.borderSm,
                          border: Border.all(color: NixColors.surfaceBorder),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 16, color: NixColors.textMuted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Apenas metadados indexados. Para reprodução nesta versão, adicione e vincule um arquivo de áudio (.wav) na playlist do Pager.',
                                style: TextStyle(color: NixColors.textMuted, fontSize: 11.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],

                  // Identificadores Externos
                  if (work.externalIds.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('IDENTIFICADORES DO CATÁLOGO', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: work.externalIds.entries.map((entry) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: NixColors.surfaceSidebar,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: NixColors.surfaceBorder),
                          ),
                          child: Text(
                            '${entry.key.toUpperCase()}: ${entry.value}',
                            style: NixTokens.monoCode(),
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  const SizedBox(height: 20),
                  Divider(height: 1, color: NixColors.surfaceBorder),
                  const SizedBox(height: 16),

                  // Seção Acervo Pessoal
                  Text('STATUS NO ACERVO PESSOAL', style: NixTokens.labelUppercase()),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: inAcervo
                          ? Colors.amber.withValues(alpha: 0.07)
                          : NixColors.surfaceSidebar,
                      borderRadius: NixTokens.borderMd,
                      border: Border.all(
                        color: inAcervo
                            ? Colors.amber.withValues(alpha: 0.35)
                            : NixColors.surfaceBorder,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              inAcervo ? Icons.bookmark_added_rounded : Icons.bookmark_outline_rounded,
                              color: inAcervo ? Colors.amber : NixColors.textMuted,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                inAcervo ? 'Obra presente no seu Acervo Pessoal' : 'Obra não incluída no Acervo',
                                style: TextStyle(
                                  color: inAcervo ? NixColors.textPrimary : NixColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (inAcervo)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Nota: ${acervoItem.rating}/10',
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        if (inAcervo) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                'Status de Consumo: ',
                                style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: DropdownButton<String>(
                                  value: acervoItem.tracking.stage?.name ?? 'planned',
                                  isExpanded: true,
                                  isDense: true,
                                  dropdownColor: NixColors.surfaceCard,
                                  underline: const SizedBox(),
                                  style: TextStyle(color: NixColors.textPrimary, fontSize: 12.5),
                                  items: const [
                                    DropdownMenuItem(value: 'planned', child: Text('Planejado / Quero Ver')),
                                    DropdownMenuItem(value: 'inProgress', child: Text('Em Andamento / Consumindo')),
                                    DropdownMenuItem(value: 'completed', child: Text('Concluído')),
                                    DropdownMenuItem(value: 'onHold', child: Text('Pausado')),
                                    DropdownMenuItem(value: 'dropped', child: Text('Abandonado')),
                                  ],
                                  onChanged: (newStage) {
                                    if (newStage != null) {
                                      final rawRating = ((double.tryParse(acervoItem.rating) ?? 8.0) * 10).toInt();
                                      nixState.saveCatalogWork(
                                        work,
                                        status: newStage == 'completed'
                                            ? 'completed'
                                            : (newStage == 'inProgress' ? 'watching' : 'want_to_watch'),
                                        rating: rawRating,
                                        notes: acervoItem.tracking.privateNotes,
                                      );
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                label: const Text('Remover do Acervo', style: TextStyle(fontSize: 12)),
                                onPressed: () {
                                  nixState.removeCulturalItem(acervoItem.id);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('"${work.title}" removido do seu Acervo.')),
                                  );
                                },
                              ),
                            ],
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                ),
                                icon: const Icon(Icons.bookmark_add_rounded, size: 16),
                                label: const Text('Adicionar ao Acervo', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                onPressed: () async {
                                  try {
                                    await nixState.saveCatalogWork(
                                      work,
                                      status: work.kind == 'book' || work.kind == 'manga' ? 'want_to_read' : 'want_to_watch',
                                      rating: 80,
                                      notes: '',
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('"${work.title}" adicionado ao seu Acervo.')),
                                      );
                                    }
                                  } catch (_) {
                                    // Adiciona diretamente se o repositório estiver em modo sem cofre nativo
                                    nixState.addCulturalItem(CulturalItem(
                                      id: 'catalog:${work.id}',
                                      title: work.title,
                                      creatorOrYear: work.creators ?? '',
                                      category: work.kind == 'book' || work.kind == 'manga' ? CulturalCategory.books : CulturalCategory.movies,
                                      monogram: String.fromCharCodes(work.title.runes.take(2)).toUpperCase(),
                                    ));
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('"${work.title}" adicionado ao seu Acervo.')),
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}
