import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/channel.dart';
import '../../core/models/direct_message.dart';
import '../../core/security/key_vault.dart';
import '../../core/security/platform_runtime.dart';
import '../../core/security/sovereign_security_gate.dart';
import '../../core/security/window_privacy_guard.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../onboarding/sovereign_onboarding_flow.dart';
import '../design/nix_surfaces.dart';
import '../design/nix_glass.dart';
import '../design/nix_bilingual_label.dart';
import '../dialogs/channel_settings_dialog.dart';
import '../profile/pager_housing.dart';
import '../profile/pager_wallpaper_layer.dart';
import '../calls/call_room_view.dart';
import '../chat/chat_view.dart';
import '../chat/conversation_info_panel.dart';
import '../discovery/github_discovery_view.dart';
import '../explore/explore_spaces_view.dart';
import '../forum/forum_channel_view.dart';
import '../home/home_private_view.dart';
import '../home/home_sidebar.dart';
import '../members/members_panel.dart';
import '../monero_p2p/monero_p2p_view.dart';
import '../profile/profile_overlay.dart';
import '../publications/publication_room_view.dart';
import '../media/media_index_view.dart';
import '../archive/archive_environment_view.dart';
import 'channels_sidebar.dart';
import 'floating_workspace_bar.dart';
import 'spaces_dock.dart';
import 'workspace_frame.dart';
import 'workspace_image.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final settings = nixState.settings;
    final currentChannel = nixState.currentChannel;
    final activeArea = nixState.activeArea;

    final rawMq = MediaQuery.of(context);
    final sanitizedMq = WindowPrivacyGuard.sanitizedMediaQuery(
      rawMq,
      quantizeDimensions: settings.quantizeViewportDimensions,
      reducedMotion: settings.reducedMotion,
    );

    final showInfoPanel = nixState.isConversationInfoOpen &&
        ((activeArea == NixActiveArea.spaces) ||
            (activeArea == NixActiveArea.homePrivate &&
                nixState.homeSubTab == HomeSubTab.directChat &&
                nixState.selectedDm != null));

    final gate = nixState.securityGate;

    // GATE 1 (FAIL-CLOSED ESTRITO): Em modo real, NUNCA permite entrar pela rede
    // doméstica. Exige Tor Onion v3 100% operacional OU Modo Off-Grid Estrito (BLE/LoRa · Zero Internet).
    if (nixState.enforceStartupGate && !gate.isTransportGateSatisfied) {
      return MediaQuery(
        data: sanitizedMq,
        child: Scaffold(
          backgroundColor: NixColors.background,
          body: SafeArea(
            child: Center(
              child: _SovereignSecurityGateView(nixState: nixState, gate: gate),
            ),
          ),
        ),
      );
    }

    // GATE 2: Desbloqueio do KeyVault (Argon2id + SQLCipher) quando requer frase-passe.
    if (nixState.requiresPassphraseUnlock) {
      return MediaQuery(
        data: sanitizedMq,
        child: Scaffold(
          backgroundColor: NixColors.background,
          body: SafeArea(
            child: Center(
              child: _VaultUnlockPrompt(nixState: nixState),
            ),
          ),
        ),
      );
    }

    // GATE 3: Onboarding Soberano obrigatório (sem botão para pular e entrar sem criptografia).
    if (!nixState.isOnboarded) {
      return MediaQuery(
        data: sanitizedMq,
        child: Scaffold(
          backgroundColor: NixColors.background,
          body: SafeArea(
            child: Center(
              child: SovereignOnboardingFlow(
                nixState: nixState,
                onComplete: () {},
                onDismiss: () {
                  if (Platform.isAndroid) {
                    SystemNavigator.pop();
                  } else if (!Platform.environment.containsKey('FLUTTER_TEST')) {
                    exit(0);
                  }
                },
              ),
            ),
          ),
        ),
      );
    }

    // GATE 4: Auditoria completa dos parâmetros criptográficos antes de montar o shell principal.
    if (nixState.enforceStartupGate && !gate.canEnterApplication) {
      return MediaQuery(
        data: sanitizedMq,
        child: Scaffold(
          backgroundColor: NixColors.background,
          body: SafeArea(
            child: Center(
              child: _SovereignSecurityGateView(nixState: nixState, gate: gate),
            ),
          ),
        ),
      );
    }

    return MediaQuery(
      data: sanitizedMq,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= nixDesktopBreakpoint;

          final Widget shellScaffold = isDesktop
              ? NixDesktopWorkspace(
                  state: nixState,
                  stage: _buildActiveStage(activeArea, currentChannel),
                  showInfoPanel: showInfoPanel,
                  offGridBanner: nixState.isStrictOffGridMode ? _buildStrictOffGridBanner(nixState) : null,
                )
              : Scaffold(
                  backgroundColor: NixColors.background,
                  extendBody: rawMq.viewInsets.bottom == 0,
                  drawerScrimColor: Colors.transparent,
                  appBar: AppBar(
                    systemOverlayStyle: SystemUiOverlayStyle(
                      statusBarColor: Colors.transparent,
                      systemNavigationBarColor: Colors.transparent,
                      systemNavigationBarDividerColor: Colors.transparent,
                      systemNavigationBarContrastEnforced: false,
                      systemStatusBarContrastEnforced: false,
                      statusBarIconBrightness: Theme.of(context).brightness == Brightness.dark ? Brightness.light : Brightness.dark,
                      systemNavigationBarIconBrightness: Theme.of(context).brightness == Brightness.dark ? Brightness.light : Brightness.dark,
                    ),
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    scrolledUnderElevation: 0,
                    flexibleSpace: const SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(8, 1, 8, 3),
                        child: NixGlass(key: Key('floating_mobile_header'), child: SizedBox.expand()),
                      ),
                    ),
                    titleSpacing: 0,
                    title: NixPanelTitle(
                      icon: _getAreaIcon(activeArea, currentChannel),
                      leading: activeArea == NixActiveArea.spaces && currentChannel.customImagePath != null
                          ? WorkspaceImage(
                              path: currentChannel.customImagePath, size: 36,
                              fallback: Icon(currentChannel.icon, color: context.accentTextColor),
                            )
                          : null,
                      title: _getAreaTitle(activeArea, currentChannel),
                      subtitle: pagerNetworkLabel(gate),
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.badge_outlined),
                        tooltip: 'Abrir Pager e perfil',
                        onPressed: () => nixState.openProfileOverlay(),
                      ),
                      if (activeArea == NixActiveArea.spaces)
                        _MobileChannelMenu(channel: currentChannel),
                    ],
                  ),
                  drawer: Drawer(
                    width: constraints.maxWidth < 390 ? constraints.maxWidth - 24 : 366,
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    elevation: 0,
                    child: SafeArea(
                      minimum: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                      child: NixGlass(child: Row(
                        children: [
                          const SpacesDock(),
                          Expanded(
                            child: (activeArea == NixActiveArea.homePrivate ||
                                    activeArea == NixActiveArea.github ||
                                    activeArea == NixActiveArea.moneroP2p ||
                                    activeArea == NixActiveArea.mediaIndex ||
                                    activeArea == NixActiveArea.archive)
                                ? const HomeSidebar()
                                : const ChannelsSidebar(),
                          ),
                        ],
                      )),
                    ),
                  ),
                  body: Builder(builder: (context) => Padding(
                    padding: EdgeInsets.only(
                      bottom: activeArea == NixActiveArea.homePrivate &&
                              nixState.homeSubTab == HomeSubTab.cardId
                          ? 0 : MediaQuery.paddingOf(context).bottom,
                    ),
                    child: Column(
                      children: [
                        if (nixState.isStrictOffGridMode)
                          _buildStrictOffGridBanner(nixState),
                        Expanded(child: _buildActiveStage(activeArea, currentChannel)),
                      ],
                    ),
                  )),
                  bottomNavigationBar: rawMq.viewInsets.bottom > 0 ? null : FloatingWorkspaceBar(state: nixState),
                );

          return Stack(
            children: [
              shellScaffold,
              if (nixState.isProfileOverlayOpen) const ProfileOverlay(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStrictOffGridBanner(NixState nixState) {
    return Container(
      key: const Key('strict_offgrid_active_banner'),
      width: double.infinity,
      color: Colors.teal.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bluetooth_searching_rounded,
                  size: 16, color: Colors.tealAccent),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'MODO OFF-GRID ESTRITO · ZERO WI-FI/INTERNET · APENAS BLE & RÁDIO LORA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.tealAccent,
                  side: const BorderSide(color: Colors.tealAccent),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => nixState.openHardwareRadioSettings(),
                child: const Text(
                  'BLE / LoRa',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: NixColors.accentYellow,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => nixState.exitOffGridModeAndConnectTor(),
                child: const Text(
                  'Conectar Tor',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getAreaIcon(NixActiveArea activeArea, Channel channel) {
    switch (activeArea) {
      case NixActiveArea.homePrivate:
        return Icons.badge_outlined;
      case NixActiveArea.explore:
        return Icons.explore_outlined;
      case NixActiveArea.github:
        return Icons.code_rounded;
      case NixActiveArea.moneroP2p:
        return Icons.currency_exchange_rounded;
      case NixActiveArea.mediaIndex:
        return Icons.local_library_rounded;
      case NixActiveArea.archive:
        return Icons.auto_stories_rounded;
      case NixActiveArea.spaces:
        return channel.icon;
    }
  }

  String _getAreaTitle(NixActiveArea activeArea, Channel channel) {
    switch (activeArea) {
      case NixActiveArea.homePrivate:
        return 'Conversas';
      case NixActiveArea.explore:
        return 'Explorar Comunidades';
      case NixActiveArea.github:
        return 'GitHub Discovery';
      case NixActiveArea.moneroP2p:
        return 'Mercado Monero P2P';
      case NixActiveArea.mediaIndex:
        return 'Nix Media Index (Offline-First)';
      case NixActiveArea.archive:
        return 'Nix Archive';
      case NixActiveArea.spaces:
        return channel.name;
    }
  }

  Widget _buildActiveStage(NixActiveArea activeArea, Channel channel) {
    if (activeArea == NixActiveArea.homePrivate) {
      return const HomePrivateView();
    }
    if (activeArea == NixActiveArea.explore) {
      return const ExploreSpacesView();
    }
    if (activeArea == NixActiveArea.github) {
      return const GithubDiscoveryView();
    }
    if (activeArea == NixActiveArea.moneroP2p) {
      return const MoneroP2pView();
    }
    if (activeArea == NixActiveArea.mediaIndex) {
      return const NixMediaIndexView();
    }
    if (activeArea == NixActiveArea.archive) {
      return const NixArchiveEnvironmentView();
    }

    switch (channel.type) {
      case ChannelType.text:
      case ChannelType.announcement:
        return ChatView(key: ValueKey(channel.id), channel: channel);
      case ChannelType.forum:
        return ForumChannelView(key: ValueKey(channel.id), channel: channel);
      case ChannelType.voice:
        return CallRoomView(key: ValueKey(channel.id), channel: channel);
      case ChannelType.publication:
        return PublicationRoomView(key: ValueKey(channel.id), channel: channel);
    }
  }
}

enum _ChannelAction { info, settings, members }

class _MobileChannelMenu extends StatelessWidget {
  const _MobileChannelMenu({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) => PopupMenuButton<_ChannelAction>(
        tooltip: 'Opções do canal',
        onSelected: (action) {
          switch (action) {
            case _ChannelAction.info:
              ConversationInfoPanel.open(context, channel: channel);
            case _ChannelAction.settings:
              ChannelSettingsDialog.show(context, channel);
            case _ChannelAction.members:
              MembersPanel.show(context);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: _ChannelAction.info, child: Text('Informações da conversa')),
          PopupMenuItem(value: _ChannelAction.settings, child: Text('Configurações do canal')),
          PopupMenuItem(value: _ChannelAction.members, child: Text('Participantes')),
        ],
      );
}

class _VaultUnlockPrompt extends StatefulWidget {
  final NixState nixState;
  const _VaultUnlockPrompt({required this.nixState});

  @override
  State<_VaultUnlockPrompt> createState() => _VaultUnlockPromptState();
}

class _VaultUnlockPromptState extends State<_VaultUnlockPrompt> {
  final TextEditingController _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final pass = _ctrl.text;
    if (pass.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.nixState.unlockWithPassphrase(pass);
      if (!mounted) return;
      if (res.status == VaultUnlockStatus.duressTriggered) {
        // Panic wipe silencioso já ocorreu no State
        _ctrl.clear();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Frase-passe incorreta para desbloquear o cofre.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: PagerHousing(
          wallpaper: widget.nixState.settings.pagerWallpaperAcrossPages
              ? PagerWallpaperLayer(state: widget.nixState, readable: true)
              : null,
          caseColor: widget.nixState.settings.pagerCaseColor,
          lcdColor: widget.nixState.settings.pagerLcdColor,
          reducedMotion: widget.nixState.settings.reducedMotion,
          minDisplayHeight: 330,
          nextLabel: 'Desbloquear o cofre',
          onNext: _busy ? null : _unlock,
          screen: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const NixBilingualLabel(label: 'Desbloquear cofre', japanese: '金庫', style: TextStyle(
                  fontFamily: pagerDisplayFont, fontSize: 18, color: pagerInk,
                )),
                const Divider(color: pagerRule),
                PagerGuide(message: '> Digite sua frase-passe.', reducedMotion: widget.nixState.settings.reducedMotion),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            obscureText: true,
            onSubmitted: (_) => _unlock(),
            style: const TextStyle(color: pagerInk, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Frase-passe mestra ou PIN de coação',
              errorText: _error,
              filled: true,
              fillColor: Colors.white.withValues(alpha: .38),
              labelStyle: const TextStyle(color: pagerInk),
              errorStyle: const TextStyle(color: Color(0xFF792438)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _busy ? null : _unlock,
            style: ElevatedButton.styleFrom(backgroundColor: pagerInk, foregroundColor: Color(widget.nixState.settings.pagerLcdColor.rgb)),
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.vpn_key_outlined, size: 17),
            label: const Text('Desbloquear & Montar SQLCipher'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: NixColors.surfaceCard,
                        title: Text(
                          'Resetar cofre local e reiniciar onboarding?',
                          style: TextStyle(color: NixColors.textPrimary, fontSize: 15),
                        ),
                        content: Text(
                          'Isso apagará o cofre bloqueado deste dispositivo para que você possa criar uma nova identidade ou restaurar uma conta existente usando suas 24 palavras (Seed A).',
                          style: TextStyle(color: NixColors.textSecondary, fontSize: 12.5),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancelar'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Resetar Cofre'),
                          ),
                        ],
                      ),
                    );
                    if (mounted && confirmed == true) {
                      setState(() => _busy = true);
                      await widget.nixState.panicWipeAllData();
                    }
                  },
            child: Text(
              'Esqueceu a frase-passe? Resetar perfil ou recuperar via Seed A',
              style: const TextStyle(color: pagerInk, fontSize: 11.5),
              textAlign: TextAlign.center,
            ),
          ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tela de Bloqueio Fail-Closed de Inicialização (Tor Onion v3 + Parâmetros Criptográficos).
/// Impede qualquer entrada no aplicativo ou contato direto com a rede doméstica
/// enquanto o circuito Tor Onion v3 e as camadas de criptografia não estiverem 100% operacionais.
class _SovereignSecurityGateView extends StatefulWidget {
  final NixState nixState;
  final SovereignSecurityGateStatus gate;

  const _SovereignSecurityGateView({
    required this.nixState,
    required this.gate,
  });

  @override
  State<_SovereignSecurityGateView> createState() =>
      _SovereignSecurityGateViewState();
}

class _SovereignSecurityGateViewState
    extends State<_SovereignSecurityGateView> {
  bool _showLogs = false;

  @override
  Widget build(BuildContext context) {
    final gate = widget.gate;
    final rt = NixPlatformPaths.runtimeInfo;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          key: const Key('sovereign_security_gate_view'),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: gate.isBootstrapping
                  ? NixColors.accentYellow
                  : Colors.redAccent.withValues(alpha: 0.7),
              width: 1.3,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    gate.isBootstrapping
                        ? Icons.shield_outlined
                        : Icons.gpp_maybe_outlined,
                    color: gate.isBootstrapping
                        ? NixColors.accentYellow
                        : Colors.redAccent,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ESCUDO FAIL-CLOSED · TOR ONION V3 OBRIGATÓRIO',
                          style: TextStyle(
                            color: NixColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          gate.isBootstrapping
                              ? 'Estabelecendo circuitos Onion v3 e auditando criptografia...'
                              : 'Acesso bloqueado para proteger seu anonimato.',
                          style: TextStyle(
                            color: NixColors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: NixColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: NixColors.surfaceBorder),
                ),
                child: Text(
                  'Política Zero-Rastro ativa: nenhuma conexão é permitida pela sua rede doméstica. '
                  'O Projeto Nix só libera a entrada após 100% de bootstrap do Tor Onion v3 e validação de todos os parâmetros criptográficos.',
                  style: TextStyle(
                    color: NixColors.textSecondary,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      gate.torStatusMessage,
                      style: TextStyle(
                        color: NixColors.textPrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${gate.torBootstrapPercent}%',
                    style: NixTokens.monoCode(
                      size: 12,
                      color: NixColors.accentYellow,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: gate.isBootstrapping && gate.torBootstrapPercent == 0
                    ? null
                    : (gate.torBootstrapPercent / 100.0).clamp(0.0, 1.0),
                backgroundColor: NixColors.background,
                valueColor: AlwaysStoppedAnimation<Color>(
                  gate.isTorAnonymityReady
                      ? Colors.greenAccent
                      : NixColors.accentYellow,
                ),
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 16),
              Text(
                'AUDITORIA DE ANONIMATO E CRIPTOGRAFIA',
                style: TextStyle(
                  color: NixColors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              _buildCheckRow(
                'Firewall HTTP Fail-Closed (Zero Rede Doméstica)',
                gate.clearnetFirewallActive,
              ),
              _buildCheckRow(
                'Proxy Tor SOCKS5 (127.0.0.1:${widget.nixState.embeddedTor.socksPort})',
                gate.torSocksActive,
              ),
              _buildCheckRow(
                'Circuito Tor 100% Operacional (ControlPort)',
                gate.torBootstrapped100,
              ),
              _buildCheckRow(
                gate.liveOnionV3Address != null
                    ? 'Tor Onion v3 Ativo (${gate.liveOnionV3Address!.substring(0, 14)}...onion)'
                    : 'Serviço / Circuito Tor Onion v3 (56 chars)',
                gate.torOnionV3Ready,
              ),
              _buildCheckRow(
                'Política Fail-Closed Clearnet Bloqueada',
                gate.failClosedPolicyVerified,
              ),
              _buildCheckRow(
                'KeyVault (Argon2id + XChaCha20-Poly1305 · ${gate.osKeyringBackend})',
                gate.keyVaultUnlocked,
                pendingAllowed: !widget.nixState.isOnboarded,
              ),
              _buildCheckRow(
                gate.sqlCipherVersion != null
                    ? 'SQLCipher Cifrado em Repouso (v${gate.sqlCipherVersion})'
                    : 'Banco Local SQLCipher Cifrado em Repouso',
                gate.sqlCipherEncrypted,
                pendingAllowed: !widget.nixState.isOnboarded,
              ),
              _buildCheckRow(
                'Identidade Seed A (Ed25519 + X25519 + Double Ratchet)',
                gate.identityKeysLoaded,
                pendingAllowed: !widget.nixState.isOnboarded,
              ),
              if (rt != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Ambiente: ${rt.deviceAbi} · Keystore: ${rt.keystoreSecurityLevel}'
                  '${rt.androidSdkInt != null ? " · Android API ${rt.androidSdkInt}" : ""}',
                  style: NixTokens.monoCode(size: 10, color: NixColors.textMuted),
                ),
              ],
              if (gate.blockingReason != null &&
                  gate.blockingReason!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    gate.blockingReason!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
              if (_showLogs) ...[
                const SizedBox(height: 10),
                Container(
                  height: 120,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: NixColors.surfaceBorder),
                  ),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: Text(
                      widget.nixState.torBootstrapLogs.isEmpty
                          ? 'Aguardando telemetria local do daemon Tor...'
                          : widget.nixState.torBootstrapLogs.join('\n'),
                      style: NixTokens.monoCode(
                        size: 10,
                        color: Colors.greenAccent,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.tealAccent.withValues(alpha: 0.45)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('enter_strict_offgrid_button'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.tealAccent,
                        side: const BorderSide(color: Colors.tealAccent),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                      onPressed: () =>
                          widget.nixState.enterStrictOffGridMode(),
                      icon: const Icon(Icons.bluetooth_searching_rounded,
                          size: 17),
                      label: const Text(
                        'Entrar via Bluetooth / LoRa (Modo Off-Grid · Zero Internet)',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sem Wi-Fi ou rede móvel? Este modo bloqueia 100% das funções de internet/Wi-Fi, '
                      'mantém o cofre SQLCipher + Seed A obrigatórios e libera apenas comunicação física via Bluetooth BLE e Rádio LoRa.',
                      style: TextStyle(
                        color: NixColors.textSecondary,
                        fontSize: 10.8,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _showLogs = !_showLogs),
                    icon: Icon(
                      _showLogs
                          ? Icons.terminal
                          : Icons.terminal_outlined,
                      size: 16,
                    ),
                    label: Text(
                      _showLogs ? 'Ocultar Logs' : 'Ver Logs Tor',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          if (Platform.isAndroid) {
                            SystemNavigator.pop();
                          } else if (!Platform.environment
                              .containsKey('FLUTTER_TEST')) {
                            exit(0);
                          }
                        },
                        child: const Text(
                          'Encerrar',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NixColors.accentYellow,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: gate.isBootstrapping
                            ? null
                            : () => widget.nixState
                                .bootstrapSovereignEnvironment(),
                        icon: gate.isBootstrapping
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(
                          gate.isBootstrapping
                              ? 'Conectando...'
                              : 'Reconectar Tor',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckRow(String label, bool ok, {bool pendingAllowed = false}) {
    final IconData icon;
    final Color color;
    if (ok) {
      icon = Icons.check_circle_rounded;
      color = Colors.greenAccent;
    } else if (pendingAllowed) {
      icon = Icons.schedule_rounded;
      color = NixColors.accentYellow;
    } else {
      icon = Icons.cancel_outlined;
      color = Colors.redAccent;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: ok ? NixColors.textPrimary : NixColors.textSecondary,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
