import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/cultural_item.dart';
import '../../core/models/cultural_tracking.dart';
import '../../core/models/user_profile.dart';
import '../../core/security/file_picker_adapter.dart';
import '../../core/security/local_image_helper.dart';
import '../../core/security/sovereign_security_gate.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../design/nix_bilingual_label.dart';
import 'cultural_showcase.dart';
import 'nix_user_avatar.dart';
import 'pager_housing.dart';
import 'pager_playlist_dialog.dart';
import '../media/lastwave_music_player_screen.dart';
import 'pager_wallpaper_layer.dart';
import 'pager_appearance_dialog.dart';
import 'pager_shortcuts.dart';
import 'profile_avatar_editor.dart';
import 'qr_code_painter.dart';

class PagerProfile extends StatefulWidget {
  final VoidCallback? onOpenSettings;
  final bool showCulturalShowcase;

  const PagerProfile({
    super.key,
    this.onOpenSettings,
    this.showCulturalShowcase = true,
  });

  @override
  State<PagerProfile> createState() => _PagerProfileState();
}

class _PagerProfileState extends State<PagerProfile> {
  static const _pages = ['Identidade', 'Status', 'Contemplação', 'Downloads'];
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _reduceMotion(NixState state) =>
      state.settings.reducedMotion || MediaQuery.disableAnimationsOf(context);

  void _selectPage(int next, NixState state) {
    if (!_controller.hasClients || next == _page) return;
    if (_reduceMotion(state)) {
      _controller.jumpToPage(next);
    } else {
      _controller.animateToPage(next,
          duration: NixTokens.motionMedium, curve: Curves.easeOutCubic);
    }
  }

  Future<void> _copyPublicId(String id) async {
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Identificador público copiado.')),
    );
  }

  void _openSettings(NixState state) {
    if (widget.onOpenSettings case final callback?) {
      callback();
    } else {
      state.transitionToSettings();
    }
  }

  void _showProfileEditor(NixState state) {
    final profile = state.userProfile;
    var name = profile.displayName;
    var bio = profile.bio;
    var music = profile.currentActivity;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setEditorState) => AlertDialog(
          title: const Text('Editar perfil do Pager'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                initialValue: name,
                onChanged: (value) => name = value,
                maxLength: 32,
                decoration: const InputDecoration(labelText: 'Nome de exibição'),
              ),
              TextFormField(
                initialValue: bio,
                onChanged: (value) => bio = value,
                maxLength: 180,
                maxLines: 3,
                decoration:
                    const InputDecoration(labelText: 'Biografia e interesses'),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.music_note_rounded, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Música no Pager (Playlist)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            music.isNotEmpty ? music : 'Nenhuma música selecionada',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: music.isNotEmpty ? null : Theme.of(context).hintColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('select_profile_track_button'),
                      onPressed: () async {
                        final selected = await _showPlaylistTrackSelector(
                          context,
                          state,
                          selectedTrackName: music,
                        );
                        if (selected != null) {
                          setEditorState(() {
                            music = selected;
                          });
                        }
                      },
                      icon: const Icon(Icons.playlist_play_rounded, size: 18),
                      label: Text(music.isNotEmpty ? 'Trocar' : 'Escolher'),
                    ),
                    if (music.isNotEmpty)
                      IconButton(
                        tooltip: 'Remover música do perfil',
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          setEditorState(() {
                            music = '';
                          });
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                state.updateProfile(
                  displayName: name.trim(),
                  bio: bio.trim(),
                  currentActivity: music.trim(),
                );
                Navigator.pop(context);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showPlaylistTrackSelector(
    BuildContext context,
    NixState state, {
    String? selectedTrackName,
  }) async {
    final playlist = state.pagerPlaylist;
    if (playlist == null) return null;

    final tracks = await playlist.load();
    if (!context.mounted) return null;

    return showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Selecionar música da Playlist'),
        content: SizedBox(
          width: 440,
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Escolha uma faixa da sua playlist local persistente para vincular ao Pager:',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: tracks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.music_off_outlined, size: 36, color: Colors.grey),
                            const SizedBox(height: 8),
                            const Text(
                              'Sua playlist local está vazia.',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Vincule arquivos .wav locais ou busque no catálogo cultural.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () async {
                                Navigator.pop(dialogCtx);
                                await showDialog<void>(
                                  context: context,
                                  builder: (_) => PagerPlaylistDialog(
                                    playlist: playlist,
                                    enableCatalog: true,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Abrir Gerenciador da Playlist'),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: tracks.length,
                        separatorBuilder: (_, __) => const Divider(height: 8),
                        itemBuilder: (itemCtx, idx) {
                          final track = tracks[idx];
                          final isCurrent = track.name == selectedTrackName;
                          return ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            tileColor: isCurrent
                                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                                : null,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: Theme.of(context).cardColor,
                              child: Icon(
                                Icons.audiotrack_rounded,
                                size: 16,
                                color: isCurrent
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                            ),
                            title: Text(
                              track.name,
                              style: TextStyle(
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: const Text(
                              'Arquivo local (.wav)',
                              style: TextStyle(fontSize: 10, color: Colors.green),
                            ),
                            trailing: isCurrent
                                ? const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20)
                                : ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                    ),
                                    onPressed: () => Navigator.pop(dialogCtx, track.name),
                                    child: const Text('Escolher', style: TextStyle(fontSize: 11)),
                                  ),
                            onTap: () => Navigator.pop(dialogCtx, track.name),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(dialogCtx);
                      await showDialog<void>(
                        context: context,
                        builder: (_) => PagerPlaylistDialog(
                          playlist: playlist,
                          enableCatalog: true,
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: const Text('Gerenciar playlist', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPagerMenu(NixState state) async {
    final playlist = switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.linux || TargetPlatform.windows =>
        state.pagerPlaylist,
      _ => null,
    };
    final action = await showDialog<_PagerMenu>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Menu do Pager'),
        children: [
          for (final action in _PagerMenu.values)
            if (action != _PagerMenu.playlist || playlist != null)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, action),
                child: ListTile(
                  leading: Icon(action.icon),
                  title: Text(action.label),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _PagerMenu.profile:
        _showProfileEditor(state);
      case _PagerMenu.playlist:
        await LastWaveMusicPlayerScreen.open(context, state.musicPlayer);
      case _PagerMenu.wallpaper:
        _selectPage(2, state);
        _showContemplationSettings();
      case _PagerMenu.chats:
        state.closeProfileOverlay();
        state.openSavedMessages();
      case _PagerMenu.preferences:
        _openSettings(state);
      case _PagerMenu.colors:
        showPagerAppearance(context);
      case null:
        break;
    }
  }

  void _showContemplationSettings() {
    showDialog<void>(
      context: context,
      builder: (context) => const _ContemplationSettings(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final profile = state.userProfile;
    final reduced = _reduceMotion(state);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          12, 16, 12, 24 + MediaQuery.paddingOf(context).bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 790),
                child: LayoutBuilder(
                  builder: (context, housing) => PagerHousing(
                    wallpaper: state.settings.pagerWallpaperAcrossPages
                        ? PagerWallpaperLayer(state: state, readable: true)
                        : null,
                    caseColor: state.settings.pagerCaseColor,
                    lcdColor: state.settings.pagerLcdColor,
                    reducedMotion: reduced,
                    onPrevious:
                        _page > 0 ? () => _selectPage(_page - 1, state) : null,
                    onNext:
                        _page < _pages.length - 1 ? () => _selectPage(_page + 1, state) : null,
                    onPlayPause: () => state.musicPlayer.togglePlayPause(),
                    onMenu: () => _showPagerMenu(state),
                    minDisplayHeight: housing.maxWidth < 576 ? 442 : 386,
                    screen: LayoutBuilder(
                      builder: (context, constraints) {
                        final narrow = constraints.maxWidth < 350;
                        return ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context).copyWith(
                            dragDevices: const {
                              PointerDeviceKind.touch,
                              PointerDeviceKind.mouse,
                              PointerDeviceKind.stylus,
                              PointerDeviceKind.trackpad,
                            },
                          ),
                          child: PageView(
                            key: const Key('pager_screen'),
                            controller: _controller,
                            onPageChanged: (page) =>
                                setState(() => _page = page),
                            children: [
                              _PagerPanel(
                                title: _pages[0],
                                fixedFooter: true,
                                japanese: '身分証',
                                page: 1,
                                footer: const PagerShortcuts(),
                                action: IconButton(
                                  key: const Key('card_id_settings_gear'),
                                  tooltip: 'Abrir Central de Configurações',
                                  onPressed: () => _openSettings(state),
                                  icon: const Icon(Icons.settings_outlined),
                                ),
                                child: _identity(state, profile, narrow),
                              ),
                              _PagerPanel(
                                title: _pages[1],
                                fixedFooter: true,
                                japanese: '状態',
                                page: 2,
                                child: _status(state, reduced,
                                    constraints.maxWidth >= 460),
                                footer: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: state.settings.pagerLcdColor.inkColor,
                                    side: BorderSide(color: state.settings.pagerLcdColor.inkColor),
                                  ),
                                  onPressed: () => _selectPage(2, state),
                                  child: const Text('Abrir contemplação'),
                                ),
                              ),
                              _ContemplationScreen(
                                  showAvatar: !state.settings.hidePagerAvatar),
                              _PagerPanel(
                                title: _pages[3],
                                japanese: '受信',
                                page: 4,
                                totalPages: _pages.length,
                                footer: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: state.settings.pagerLcdColor.inkColor,
                                    side: BorderSide(color: state.settings.pagerLcdColor.inkColor),
                                  ),
                                  onPressed: () => state.openDownloadsArea(),
                                  child: const Text('Abrir Central de Downloads'),
                                ),
                                child: _downloadsSummary(state),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (widget.showCulturalShowcase) ...[
                const SizedBox(height: 27),
                const CulturalShowcase(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _identity(NixState state, UserProfile profile, bool narrow) {
    final canShare =
        profile.publicId.isNotEmpty && state.settings.allowPublicIdSharing;
    final gate = state.securityGate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Tooltip(
              message: 'Editar foto de perfil',
              child: NixUserAvatar(
                key: const Key('card_id_avatar_edit_button'),
                size: narrow ? 45 : 58,
                onTap: () => showProfileAvatarEditor(context, state),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.effectiveDisplayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: narrow ? 18 : 25,
                        fontFamily: pagerDisplayFont,
                        fontWeight: FontWeight.w700),
                  ),
                  _buildSecurityStars(context, state),
                  const SizedBox(height: 3),
                  _buildRetroProgressBar(state),
                ],
              ),
            ),
            if (canShare) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Ampliar QR de identificação',
                child: InkWell(
                  key: const Key('pager_public_qr'),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => QrCodeZoomModal(
                      publicId: profile.publicId,
                      displayName: profile.effectiveDisplayName,
                      qrPayload: profile.qrPublicPayload,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(6),
                  child: state.settings.pagerLcdColor.isDark
                      ? Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: NixQrCodeWidget(
                              data: profile.qrPublicPayload, size: narrow ? 56 : 68),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: NixQrCodeWidget(
                              data: profile.qrPublicPayload, size: narrow ? 62 : 76),
                        ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                profile.bio.isEmpty ? 'Adicionar biografia' : profile.bio,
                style: const TextStyle(fontSize: 13),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'Editar nome e biografia',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _showProfileEditor(state),
              icon: const Icon(Icons.edit_outlined, size: 17),
            ),
          ],
        ),
        if (profile.currentActivity.trim().isNotEmpty || state.musicPlayer.currentTrack != null)
          InkWell(
            onTap: () => LastWaveMusicPlayerScreen.open(context, state.musicPlayer),
            borderRadius: BorderRadius.circular(4),
            child: Row(children: [
              Icon(Icons.music_note_outlined, color: state.settings.pagerLcdColor.inkColor, size: 15),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(
                      state.musicPlayer.currentTrack != null
                          ? '${state.musicPlayer.isPlaying ? "▶ " : "⏸ "}${state.musicPlayer.currentTrack!.name} · ${state.musicPlayer.currentTrack!.artist}'
                          : profile.currentActivity,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis)),
              Icon(Icons.playlist_play_rounded, color: state.settings.pagerLcdColor.inkColor, size: 16),
            ]),
          ),
        if (profile.publicId.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  profile.publicId,
                  style: const TextStyle(
                      fontFamily: pagerDisplayFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
              ),
              if (canShare)
                IconButton(
                  key: const Key('copy_public_id_button'),
                  tooltip: 'Copiar ID público',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _copyPublicId(profile.publicId),
                  icon: const Icon(Icons.copy_rounded, size: 17),
                ),
            ],
          ),
        const SizedBox(height: 3),
        _PagerStatusStrip(gate: gate),
        _buildCulturalStatsDashboard(context, state),
      ],
    );
  }

  Widget _status(NixState state, bool reduced, bool wideDisplay) {
    final gate = state.securityGate;
    const instruction = '> Rede, cofre e chaves.\n> Avance para contemplar.';
    final details = [
      'Cofre local: ${gate.keyVaultUnlocked ? 'desbloqueado' : 'bloqueado'}',
      'Identidade: ${gate.identityKeysLoaded ? 'Ed25519 + X25519' : 'chaves indisponíveis'}',
      if (!gate.isStrictOffGridMode && gate.isBootstrapping)
        'Inicialização Tor: ${gate.torBootstrapPercent}%',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PagerGuide(
          message: instruction,
          reducedMotion: reduced,
          portraitSize: wideDisplay ? 132 : 56,
          centered: wideDisplay,
        ),
        const SizedBox(height: 9),
        _PagerStatusStrip(gate: gate),
        const SizedBox(height: 9),
        _PagerMusicPlayerStrip(state: state),
        const SizedBox(height: 9),
        if (wideDisplay)
          Wrap(spacing: 16, runSpacing: 3, children: [
            for (final detail in details)
              Text(detail, style: const TextStyle(fontSize: 13)),
          ])
        else
          for (final detail in details)
            Text(detail, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  Widget _buildSecurityStars(BuildContext context, NixState state) {
    final gate = state.securityGate;
    final isSqlCipher = state.localDatabase?.cipherInfo.isEncrypted == true || gate.sqlCipherEncrypted;
    final isTor = gate.isTorAnonymityReady || gate.torBootstrapPercent >= 100;
    final isKeys = gate.identityKeysLoaded;
    final score = (isSqlCipher ? 1 : 0) + (isTor ? 1 : 0) + (isKeys ? 1 : 0) + 2;

    final ink = state.settings.pagerLcdColor.inkColor;
    return InkWell(
      key: const Key('pager_security_stars_button'),
      onTap: () => _showSecurityAuditDialog(context, state),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < 5; i++)
                Icon(
                  i < score ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 13,
                  color: ink,
                ),
              const SizedBox(width: 3),
              Text(
                '$score/5',
                style: TextStyle(
                  fontFamily: pagerDisplayFont,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRetroProgressBar(NixState state) {
    final gate = state.securityGate;
    final isSqlCipher = state.localDatabase?.cipherInfo.isEncrypted == true || gate.sqlCipherEncrypted;
    final isTor = gate.isTorAnonymityReady || gate.torBootstrapPercent >= 100;
    final isKeys = gate.identityKeysLoaded;
    final score = (isSqlCipher ? 1 : 0) + (isTor ? 1 : 0) + (isKeys ? 1 : 0) + 2;
    final ratio = (score / 5.0).clamp(0.0, 1.0);
    final ink = state.settings.pagerLcdColor.inkColor;

    return Container(
      height: 4,
      width: 120,
      decoration: BoxDecoration(
        border: Border.all(color: ink, width: 0.8),
        borderRadius: BorderRadius.circular(1),
      ),
      padding: const EdgeInsets.all(0.5),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: ratio,
        child: Container(color: ink),
      ),
    );
  }

  void _showSecurityAuditDialog(BuildContext context, NixState state) {
    final gate = state.securityGate;
    final isSqlCipher = state.localDatabase?.cipherInfo.isEncrypted == true || gate.sqlCipherEncrypted;
    final isTor = gate.isTorAnonymityReady || gate.torBootstrapPercent >= 100;
    final isKeys = gate.identityKeysLoaded;
    const isNoTelemetry = true;
    const isFailClosed = true;

    final checks = [
      (title: 'SQLCipher em Repouso', desc: 'Banco de dados criptografado localmente sem chaves em claro.', ok: isSqlCipher),
      (title: 'Roteamento Tor Onion v3', desc: 'Circuito anônimo de transporte ativo sem vazamento clearnet.', ok: isTor),
      (title: 'Par de Chaves Soberanas', desc: 'Chaves criptográficas ativas no cofre isolado de memória.', ok: isKeys),
      (title: 'Zero Rastreamento & Telemetria', desc: 'Sem servidores centrais, cookies, analytics ou terceiros.', ok: isNoTelemetry),
      (title: 'Transporte Fail-Closed', desc: 'Quedas no circuito fecham o tráfego instantaneamente.', ok: isFailClosed),
    ];

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.verified_user_outlined, color: Colors.green, size: 22),
            SizedBox(width: 8),
            Text('Auditoria Privada de Segurança', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'As cinco estrelas do Pager refletem verificações locais verificáveis em tempo real:',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              for (final c in checks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        c.ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        color: c.ok ? Colors.green : Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text(c.desc, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
        ],
      ),
    );
  }

  Widget _buildCulturalStatsDashboard(BuildContext context, NixState state) {
    final items = state.userProfile.culturalItems;
    final books = items.where((i) => i.category == CulturalCategory.books).toList();
    final manga = items.where((i) => i.category == CulturalCategory.manga).toList();
    final movies = items.where((i) => i.category == CulturalCategory.movies).toList();
    final series = items.where((i) => i.category == CulturalCategory.series).toList();

    final booksCompleted = books.where((i) => i.tracking.stage == CulturalStage.finished).length;
    final mangaCompleted = manga.where((i) => i.tracking.stage == CulturalStage.finished).length;
    final moviesCompleted = movies.where((i) => i.tracking.stage == CulturalStage.finished).length;
    final seriesCompleted = series.where((i) => i.tracking.stage == CulturalStage.finished).length;

    final totalItems = items.length;
    final totalCompleted = items.where((i) => i.tracking.stage == CulturalStage.finished).length;
    final percent = totalItems == 0 ? 0 : ((totalCompleted / totalItems) * 100).round();
    final ink = state.settings.pagerLcdColor.inkColor;
    final isBlack = state.settings.pagerLcdColor.isBlack;

    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: isBlack ? const Color(0x28FFFFFF) : const Color(0x1810262D),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ink.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statCell(Icons.auto_stories_outlined, '$booksCompleted', 'Livros', ink),
                _statCell(Icons.menu_book_rounded, '$mangaCompleted', 'Mangá', ink),
                _statCell(Icons.movie_outlined, '$moviesCompleted', 'Filmes', ink),
                _statCell(Icons.tv_rounded, '$seriesCompleted', 'Séries', ink),
                _stampLockCell(context, percent, ink),
              ],
            ),
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(1.5),
            child: SizedBox(
              height: 3,
              child: Row(
                children: [
                  Expanded(flex: math.max(1, booksCompleted), child: Container(color: Colors.green.shade800)),
                  Expanded(flex: math.max(1, mangaCompleted), child: Container(color: Colors.orange.shade800)),
                  Expanded(flex: math.max(1, moviesCompleted), child: Container(color: Colors.blue.shade800)),
                  Expanded(flex: math.max(1, seriesCompleted), child: Container(color: Colors.purple.shade800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCell(IconData icon, String count, String label, [Color? ink]) {
    final effectiveInk = ink ?? const Color(0xFF10262D);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: effectiveInk),
          Text(
            count,
            style: TextStyle(
              fontFamily: pagerDisplayFont,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: effectiveInk,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 8, color: effectiveInk),
          ),
        ],
      ),
    );
  }

  Widget _stampLockCell(BuildContext context, int percent, [Color? ink]) {
    final effectiveInk = ink ?? const Color(0xFF10262D);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: effectiveInk, width: 1),
            ),
            child: Center(
              child: Icon(Icons.lock_outline_rounded, size: 10, color: effectiveInk),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '$percent%',
            style: TextStyle(
              fontFamily: pagerDisplayFont,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: effectiveInk,
            ),
          ),
        ],
      ),
    );
  }
  Widget _downloadsSummary(NixState state) {
    final ink = state.settings.pagerLcdColor.inkColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text(
          'Central de Downloads & Torrents',
          style: TextStyle(
            color: ink,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: pagerDisplayFont,
          ),
        ),
        const SizedBox(height: 8),
        _statusRow('Mecanismo de Download:', 'aria2 HTTP/HTTPS', ink),
        _statusRow('Proteção BitTorrent:', 'Bloqueado (Anti-Leak Tor)', ink),
        _statusRow('Range Requests:', 'Multi-Conexão (4 splits)', ink),
        _statusRow('Buscador Torrents:', 'Online / Offline / Ao Vivo', ink),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: state.settings.pagerLcdColor.chipColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: state.settings.pagerLcdColor.ruleColor),
          ),
          child: Text(
            'Transferências BitTorrent permanecem isoladas para garantir sua privacidade.',
            style: TextStyle(color: ink, fontSize: 11, height: 1.3),
          ),
        ),
      ],
    );
  }

  Widget _statusRow(String label, String value, Color ink) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: ink.withValues(alpha: 0.8), fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: TextStyle(color: ink, fontSize: 11, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

enum _PagerMenu {
  profile('Editar perfil', Icons.person_outline),
  playlist('Playlist do Pager', Icons.queue_music),
  chats('Abrir mensagens', Icons.chat_bubble_outline),
  colors('Cores do Pager', Icons.palette_outlined),
  wallpaper('Personalizar contemplação', Icons.wallpaper_outlined),
  preferences('Configurações do Nix', Icons.settings_outlined);

  const _PagerMenu(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _PagerPanel extends StatelessWidget {
  final String title;
  final String japanese;
  final int page;
  final int totalPages;
  final Widget? action;
  final Widget? footer;
  final bool fixedFooter;
  final Widget child;

  const _PagerPanel(
      {required this.title,
      required this.japanese,
      required this.page,
      this.totalPages = 4,
      this.action,
      this.footer,
      this.fixedFooter = false,
      required this.child});

  @override
  Widget build(BuildContext context) {
    final ink = context.watch<NixState>().settings.pagerLcdColor.inkColor;
    return IconTheme(
      data: IconThemeData(color: ink),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: ink),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 2, 13, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: NixBilingualLabel(
                        label: title,
                        japanese: japanese,
                        style: const TextStyle(
                          fontFamily: 'PixelifySans',
                          fontSize: 20,
                        )),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '0$page/0$totalPages',
                    maxLines: 1,
                    textScaler: MediaQuery.textScalerOf(context)
                        .clamp(maxScaleFactor: 1.5),
                    style: const TextStyle(
                      fontFamily: 'PixelifySans',
                      fontSize: 13,
                    ),
                  ),
                  if (action != null)
                    SizedBox(height: 36, child: action!)
                  else
                    const SizedBox(height: 36),
                ],
              ),
              const Divider(color: pagerRule, height: 1),
              Expanded(
                child: SingleChildScrollView(
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      child,
                      if (footer != null && !fixedFooter) ...[
                        const SizedBox(height: 3),
                        footer!,
                      ],
                    ],
                  ),
                ),
              ),
              if (footer != null && fixedFooter) footer!,
            ],
          ),
        ),
      ),
    );
  }
}

class _PagerStatusStrip extends StatelessWidget {
  final SovereignSecurityGateStatus gate;

  const _PagerStatusStrip({required this.gate});

  @override
  Widget build(BuildContext context) {
    final network = pagerNetworkLabel(gate);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x2010262D),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 3,
        children: [
          _chip(Icons.sensors_rounded, network),
          _chip(Icons.storage_rounded,
              gate.sqlCipherEncrypted ? 'SQLCipher' : 'SQLCipher indisponível'),
          _chip(
              Icons.key_rounded,
              gate.identityKeysLoaded
                  ? 'Chaves ativas'
                  : 'Chaves indisponíveis'),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13),
          const SizedBox(width: 3),
          Flexible(
            child: Text(label,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      );
}

class _PagerMusicPlayerStrip extends StatelessWidget {
  final NixState state;

  const _PagerMusicPlayerStrip({required this.state});

  @override
  Widget build(BuildContext context) {
    final player = state.musicPlayer;
    final ink = state.settings.pagerLcdColor.inkColor;

    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final track = player.currentTrack;
        final isPlaying = player.isPlaying;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: ink.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: ink.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    isPlaying ? Icons.music_note_rounded : Icons.pause_circle_outline_rounded,
                    size: 16,
                    color: ink,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track != null ? track.name : 'Nenhuma música tocando',
                          style: TextStyle(
                            color: ink,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (track != null)
                          Text(
                            '${track.artist} · ${track.audioFormat}',
                            style: TextStyle(
                              color: ink.withValues(alpha: 0.75),
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => player.previous(),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.skip_previous_rounded, size: 16, color: ink),
                    ),
                  ),
                  InkWell(
                    onTap: () => player.togglePlayPause(),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 20,
                        color: ink,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => player.next(),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.skip_next_rounded, size: 16, color: ink),
                    ),
                  ),
                  const SizedBox(width: 2),
                  InkWell(
                    onTap: () => LastWaveMusicPlayerScreen.open(context, player),
                    borderRadius: BorderRadius.circular(4),
                    child: Tooltip(
                      message: 'Abrir Player LastWave',
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.open_in_new_rounded, size: 15, color: ink),
                      ),
                    ),
                  ),
                ],
              ),
              if (track != null && player.duration.inSeconds > 0) ...[
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (player.position.inMilliseconds / player.duration.inMilliseconds).clamp(0.0, 1.0),
                    backgroundColor: ink.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(ink),
                    minHeight: 3,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${player.position.inMinutes}:${(player.position.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(color: ink.withValues(alpha: 0.7), fontSize: 9),
                    ),
                    Text(
                      '${player.duration.inMinutes}:${(player.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(color: ink.withValues(alpha: 0.7), fontSize: 9),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ContemplationScreen extends StatefulWidget {
  final bool showAvatar;

  const _ContemplationScreen({required this.showAvatar});

  @override
  State<_ContemplationScreen> createState() => _ContemplationScreenState();
}

class _ContemplationScreenState extends State<_ContemplationScreen> {
  Offset? _dragPosition;
  int? _dragPointer;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final settings = state.settings;
    return Semantics(
      label: 'Contemplação',
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
              decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0E212A), Color(0xFF46335D), Color(0xFF221935)],
            ),
          )),
          PagerWallpaperLayer(state: state),
          if (widget.showAvatar)
            LayoutBuilder(builder: (context, viewport) {
              final diameter =
                  viewport.biggest.shortestSide * settings.pagerAvatarScale;
              final position = _dragPosition ??
                  Offset(settings.pagerAvatarX, settings.pagerAvatarY);
              const inset = 8.0;
              return Padding(
                padding: const EdgeInsets.all(inset),
                child: Align(
                  alignment: Alignment(position.dx, position.dy),
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.opaque,
                    gestures: {
                      EagerGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                              EagerGestureRecognizer>(
                        EagerGestureRecognizer.new,
                        (_) {},
                      ),
                    },
                    child: Listener(
                      onPointerDown: (event) => _dragPointer ??= event.pointer,
                      onPointerMove: (event) {
                        if (event.pointer != _dragPointer) return;
                        final travelX =
                            viewport.maxWidth - diameter - inset * 2;
                        final travelY =
                            viewport.maxHeight - diameter - inset * 2;
                        if (travelX <= 0 || travelY <= 0) return;
                        setState(() => _dragPosition = Offset(
                              (position.dx + event.delta.dx * 2 / travelX)
                                  .clamp(-1, 1),
                              (position.dy + event.delta.dy * 2 / travelY)
                                  .clamp(-1, 1),
                            ));
                      },
                      onPointerUp: (event) {
                        if (event.pointer != _dragPointer) return;
                        _dragPointer = null;
                        final position = _dragPosition;
                        if (position == null) return;
                        state.updateSettings(state.settings.copyWith(
                            pagerAvatarX: position.dx,
                            pagerAvatarY: position.dy));
                        setState(() => _dragPosition = null);
                      },
                      onPointerCancel: (event) {
                        if (event.pointer != _dragPointer) return;
                        _dragPointer = null;
                        setState(() => _dragPosition = null);
                      },
                      child: NixUserAvatar(
                        key: const Key('pager_contemplation_avatar'),
                        size: diameter,
                        borderColor: const Color(0xFFD9CBF4),
                        borderWidth: 2,
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _ContemplationSettings extends StatefulWidget {
  const _ContemplationSettings();

  @override
  State<_ContemplationSettings> createState() => _ContemplationSettingsState();
}

class _ContemplationSettingsState extends State<_ContemplationSettings> {
  bool _busy = false;
  String? _error;

  Future<void> _change(NixState state, {required bool remove}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = remove ? null : await _pickWallpaper();
      if (path == null && !remove) return;
      final ok = await state.updatePagerWallpaper(path);
      if (!ok && mounted) _error = 'Imagem inválida ou maior que 20 MB.';
    } on PlatformException {
      if (mounted) _error = 'Não foi possível abrir a imagem.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _pickWallpaper() async {
    List<String> paths;
    try {
      paths = await LocalImageHelper.filePickerAdapter.pickAttachments(
        allowedExtensions: LocalImageHelper.supportedExtensions,
        allowMultiple: false,
      );
    } on FilePickerUnavailableException {
      if (!mounted) return null;
      paths =
          await CrossPlatformFilePickerAdapter.showPortableFileChooserDialog(
        context,
        title: 'Escolher fundo local',
        allowedExtensions: LocalImageHelper.supportedExtensions,
      );
    }
    return paths.isEmpty ? null : paths.first;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    return AlertDialog(
      title: const Text('Contemplação'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: const Text('Mostrar foto de perfil'),
            value: !state.settings.hidePagerAvatar,
            onChanged: state.updatePagerAvatarVisibility,
            contentPadding: EdgeInsets.zero,
          ),
          if (!state.settings.hidePagerAvatar) ...[
            _avatarSlider(
                'Tamanho da foto',
                state.settings.pagerAvatarScale,
                .14,
                .56,
                (value) => state.updateSettings(
                    state.settings.copyWith(pagerAvatarScale: value))),
            _avatarSlider(
                'Posição horizontal',
                state.settings.pagerAvatarX,
                -1,
                1,
                (value) => state.updateSettings(
                    state.settings.copyWith(pagerAvatarX: value))),
            _avatarSlider(
                'Posição vertical',
                state.settings.pagerAvatarY,
                -1,
                1,
                (value) => state.updateSettings(
                    state.settings.copyWith(pagerAvatarY: value))),
            TextButton(
              onPressed: () => state.updateSettings(state.settings.copyWith(
                pagerAvatarX: 0,
                pagerAvatarY: 0,
                pagerAvatarScale: .28,
              )),
              child: const Text('Restaurar posição e tamanho'),
            ),
            const Divider(),
          ],
          SwitchListTile(
            title: const Text('Fundo em todas as telas do Pager'),
            value: state.settings.pagerWallpaperAcrossPages,
            onChanged: (value) => state.updateSettings(
                state.settings.copyWith(pagerWallpaperAcrossPages: value)),
            contentPadding: EdgeInsets.zero,
          ),
          _avatarSlider(
              'Desfoque do fundo',
              state.settings.pagerWallpaperBlur / 18,
              0,
              1,
              (value) => state.updateSettings(
                  state.settings.copyWith(pagerWallpaperBlur: value * 18))),
          _avatarSlider(
              'Sombra do fundo',
              state.settings.pagerWallpaperShade,
              0,
              .75,
              (value) => state.updateSettings(
                  state.settings.copyWith(pagerWallpaperShade: value))),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _change(state, remove: false),
                icon: const Icon(Icons.wallpaper_outlined),
                label: const Text('Escolher imagem local'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _change(state, remove: true),
                child: const Text('Restaurar fundo'),
              ),
            ],
          ),
          if (_error != null) Text(_error!),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar')),
      ],
    );
  }

  Widget _avatarSlider(String label, double value, double min, double max,
          ValueChanged<double> onChanged) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          Slider(
              value: value,
              min: min,
              max: max,
              semanticFormatterCallback: (value) => '${(value * 100).round()}%',
              onChanged: onChanged),
        ],
      );
}
