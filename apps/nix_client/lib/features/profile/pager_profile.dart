import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
import 'pager_appearance_dialog.dart';
import 'pager_shortcuts.dart';
import 'profile_avatar_editor.dart';
import 'qr_code_painter.dart';

class PagerProfile extends StatefulWidget {
  final VoidCallback? onOpenSettings;
  final bool showCulturalPassport;

  const PagerProfile({
    super.key,
    this.onOpenSettings,
    this.showCulturalPassport = true,
  });

  @override
  State<PagerProfile> createState() => _PagerProfileState();
}

class _PagerProfileState extends State<PagerProfile> {
  static const _pages = ['Identidade', 'Status', 'Contemplação'];
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
      builder: (context) => AlertDialog(
        title: const Text('Editar perfil do Pager'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
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
            TextFormField(
              initialValue: music,
              onChanged: (value) => music = value,
              maxLength: 60,
              decoration: const InputDecoration(
                  labelText: 'Música no Pager (opcional)'),
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
    );
  }

  Future<void> _showPagerMenu(NixState state) async {
    final action = await showDialog<_PagerMenu>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Menu do Pager'),
        children: [
          for (final action in _PagerMenu.values)
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
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 790),
                child: PagerHousing(
                  caseColor: state.settings.pagerCaseColor,
                  lcdColor: state.settings.pagerLcdColor,
                  reducedMotion: reduced,
                  onPrevious:
                      _page > 0 ? () => _selectPage(_page - 1, state) : null,
                  onNext:
                      _page < 2 ? () => _selectPage(_page + 1, state) : null,
                  onMenu: () => _showPagerMenu(state),
                  minDisplayHeight: 365,
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
                          onPageChanged: (page) => setState(() => _page = page),
                          children: [
                            _PagerPanel(
                              title: _pages[0],
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
                              japanese: '状態',
                              page: 2,
                              child: _status(state, reduced),
                              footer: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: pagerInk,
                                  side: const BorderSide(color: pagerInk),
                                ),
                                onPressed: () => _selectPage(2, state),
                                child: const Text('Abrir contemplação'),
                              ),
                            ),
                            _ContemplationScreen(
                                showAvatar: !state.settings.hidePagerAvatar),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (widget.showCulturalPassport) ...[
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
                borderColor: pagerInk,
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
                  Text('Desde ${profile.memberSinceYear}',
                      style: const TextStyle(fontSize: 12)),
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: NixQrCodeWidget(
                        data: profile.qrPublicPayload, size: narrow ? 62 : 76),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
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
              onPressed: () => _showProfileEditor(state),
              icon: const Icon(Icons.edit_outlined, size: 17),
            ),
          ],
        ),
        if (profile.currentActivity.trim().isNotEmpty)
          Row(children: [
            const Icon(Icons.music_note_outlined, color: pagerInk, size: 15),
            const SizedBox(width: 6),
            Expanded(
                child: Text(profile.currentActivity,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis)),
          ]),
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
                  onPressed: () => _copyPublicId(profile.publicId),
                  icon: const Icon(Icons.copy_rounded, size: 17),
                ),
            ],
          ),
        const SizedBox(height: 3),
        _PagerStatusStrip(gate: gate),
      ],
    );
  }

  Widget _status(NixState state, bool reduced) {
    final gate = state.securityGate;
    const instruction = '> Rede, cofre e chaves.\n> Avance para contemplar.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PagerGuide(
          message: instruction,
          reducedMotion: reduced,
          portraitSize: 56,
        ),
        const SizedBox(height: 9),
        _PagerStatusStrip(gate: gate),
        const SizedBox(height: 9),
        Text(
            'Cofre local: ${gate.keyVaultUnlocked ? 'desbloqueado' : 'bloqueado'}',
            style: const TextStyle(fontSize: 13)),
        Text(
            'Identidade: ${gate.identityKeysLoaded ? 'Ed25519 + X25519' : 'chaves indisponíveis'}',
            style: const TextStyle(fontSize: 13)),
        if (!gate.isStrictOffGridMode && gate.isBootstrapping)
          Text('Inicialização Tor: ${gate.torBootstrapPercent}%',
              style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

enum _PagerMenu {
  profile('Editar perfil', Icons.person_outline),
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
  final Widget? action;
  final Widget? footer;
  final Widget child;

  const _PagerPanel(
      {required this.title,
      required this.japanese,
      required this.page,
      this.action,
      this.footer,
      required this.child});

  @override
  Widget build(BuildContext context) {
    return IconTheme(
      data: const IconThemeData(color: pagerInk),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: pagerInk),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 4, 13, 5),
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
                    '0$page/03',
                    maxLines: 1,
                    textScaler: MediaQuery.textScalerOf(context)
                        .clamp(maxScaleFactor: 1.5),
                    style: const TextStyle(
                      fontFamily: 'PixelifySans',
                      fontSize: 13,
                    ),
                  ),
                  if (action != null) action! else const SizedBox(height: 48),
                ],
              ),
              const Divider(color: pagerRule, height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: child,
                ),
              ),
              if (footer != null) footer!,
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

class _ContemplationScreen extends StatelessWidget {
  final bool showAvatar;

  const _ContemplationScreen({required this.showAvatar});

  @override
  Widget build(BuildContext context) {
    final revision =
        context.select<NixState, int>((state) => state.pagerWallpaperRevision);
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
          Image(
            key: ValueKey(revision),
            image: NixState.pagerWallpaperImage,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
          if (showAvatar)
            const Center(
                child: NixUserAvatar(
              key: Key('pager_contemplation_avatar'),
              size: 80,
              borderColor: Color(0xFFD9CBF4),
              borderWidth: 2,
            )),
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
}
