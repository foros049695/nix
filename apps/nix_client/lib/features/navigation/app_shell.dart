import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/channel.dart';
import '../../core/models/direct_message.dart';
import '../../core/security/key_vault.dart';
import '../../core/security/window_privacy_guard.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import '../dialogs/sovereign_onboarding_dialog.dart';
import '../onboarding/sovereign_onboarding_flow.dart';
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
import 'channels_sidebar.dart';
import 'panel_resize_divider.dart';
import 'resizable_window_frame.dart';
import 'spaces_dock.dart';
import 'window_title_bar.dart';

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

    if (nixState.requiresPassphraseUnlock) {
      return MediaQuery(
        data: sanitizedMq,
        child: Scaffold(
          backgroundColor: NixColors.background,
          body: Center(
            child: _VaultUnlockPrompt(nixState: nixState),
          ),
        ),
      );
    }

    if (!nixState.isOnboarded && !nixState.onboardingNoticeDismissed) {
      return MediaQuery(
        data: sanitizedMq,
        child: Scaffold(
          backgroundColor: NixColors.background,
          body: Center(
            child: SovereignOnboardingFlow(
              nixState: nixState,
              onComplete: () {},
              onDismiss: () => nixState.dismissOnboardingToIncompleteNotice(),
            ),
          ),
        ),
      );
    }

    return MediaQuery(
      data: sanitizedMq,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 820;

          final Widget shellScaffold = isDesktop
              ? Scaffold(
                  backgroundColor: NixColors.background,
                  body: ResizableWindowFrame(
                    isFloating: settings.floatingWindowMode,
                    child: Column(
                      children: [
                        const WindowTitleBar(),
                        if (!nixState.isOnboarded)
                          Container(
                            color: Colors.amber.shade900,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.white),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'CONFIGURAÇÃO SOBERANA INCOMPLETA · Roteamento Tor e Identidade Privada pendentes.',
                                    style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: NixColors.accentYellow,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  ),
                                  onPressed: () => SovereignOnboardingDialog.show(context, nixState),
                                  child: const Text('Retomar Configuração', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: Row(
                            children: [
                              // Área 1: Barra vertical compacta de Pastas & Organização (redimensionável)
                              SpacesDock(width: nixState.dockWidth),

                              // Divisor Redimensionável 1: Entre Dock e Sidebar
                              PanelResizeDivider(
                                key: const Key('dock_resize_divider'),
                                onDeltaDrag: (delta) => nixState.updateDockWidth(nixState.dockWidth + delta),
                                onDoubleTapReset: () => nixState.resetDockWidth(),
                                tooltip: 'Redimensionar Pastas (Duplo clique para 78px)',
                              ),

                              // Área 2: Lista de Conversas & Navegação Principal (redimensionável)
                              if (activeArea == NixActiveArea.homePrivate ||
                                  activeArea == NixActiveArea.github ||
                                  activeArea == NixActiveArea.moneroP2p)
                                HomeSidebar(width: nixState.sidebarWidth)
                              else if (activeArea == NixActiveArea.spaces)
                                ChannelsSidebar(width: nixState.sidebarWidth),

                              // Divisor Redimensionável 2: Entre Sidebar e Conversa Ativa
                              if (activeArea == NixActiveArea.homePrivate ||
                                  activeArea == NixActiveArea.github ||
                                  activeArea == NixActiveArea.moneroP2p ||
                                  activeArea == NixActiveArea.spaces)
                                PanelResizeDivider(
                                  key: const Key('sidebar_resize_divider'),
                                  onDeltaDrag: (delta) => nixState.updateSidebarWidth(nixState.sidebarWidth + delta),
                                  onDoubleTapReset: () => nixState.resetSidebarWidth(),
                                  tooltip: 'Redimensionar Conversas (Duplo clique para 288px)',
                                ),

                              // Área 3: Conversa Ativa / Palco Principal
                              Expanded(
                                child: _buildActiveStage(activeArea, currentChannel),
                              ),

                              // Painel Lateral de Informações da Conversa (Seção 10)
                              if (showInfoPanel)
                                ConversationInfoPanel(
                                  directMessage: activeArea == NixActiveArea.homePrivate
                                      ? nixState.selectedDm
                                      : null,
                                  channel: activeArea == NixActiveArea.spaces
                                      ? currentChannel
                                      : null,
                                )
                              else if (activeArea == NixActiveArea.spaces &&
                                  nixState.isMembersPanelOpen)
                                const MembersPanel(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Scaffold(
                  backgroundColor: NixColors.background,
                  appBar: AppBar(
                    title: Row(
                      children: [
                        Icon(
                          _getAreaIcon(activeArea, currentChannel),
                          size: 18,
                          color: NixColors.textPrimary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _getAreaTitle(activeArea, nixState.selectedDm, currentChannel),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: NixColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.info_outline_rounded),
                        tooltip: 'Informações da Conversa',
                        onPressed: () => nixState.toggleConversationInfoPanel(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.badge_outlined),
                        tooltip: 'Abrir Card ID & Perfil',
                        onPressed: () => nixState.openProfileOverlay(),
                      ),
                      if (activeArea == NixActiveArea.spaces)
                        IconButton(
                          icon: const Icon(Icons.people_outline_rounded),
                          tooltip: 'Participantes',
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: NixColors.surfaceSidebar,
                              builder: (_) => const SizedBox(
                                height: 400,
                                child: MembersPanel(),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  drawer: Drawer(
                    width: 366,
                    backgroundColor: NixColors.surfaceSidebar,
                    child: SafeArea(
                      child: Row(
                        children: [
                          const SpacesDock(),
                          Expanded(
                            child: (activeArea == NixActiveArea.homePrivate ||
                                    activeArea == NixActiveArea.github ||
                                    activeArea == NixActiveArea.moneroP2p)
                                ? const HomeSidebar()
                                : const ChannelsSidebar(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  body: Stack(
                    children: [
                      _buildActiveStage(activeArea, currentChannel),
                      if (showInfoPanel)
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: ConversationInfoPanel(
                            directMessage:
                                activeArea == NixActiveArea.homePrivate ? nixState.selectedDm : null,
                            channel: activeArea == NixActiveArea.spaces ? currentChannel : null,
                          ),
                        ),
                    ],
                  ),
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
      case NixActiveArea.spaces:
        return channel.icon;
    }
  }

  String _getAreaTitle(NixActiveArea activeArea, DirectMessageThread? dm, Channel channel) {
    switch (activeArea) {
      case NixActiveArea.homePrivate:
        return dm != null ? dm.peerName : 'Conversas Privadas & Card ID';
      case NixActiveArea.explore:
        return 'Explorar Comunidades';
      case NixActiveArea.github:
        return 'GitHub Discovery';
      case NixActiveArea.moneroP2p:
        return 'Mercado Monero P2P';
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
    return Container(
      width: 420,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: NixColors.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NixColors.surfaceBorderStrong),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, color: NixColors.accentYellow, size: 22),
              const SizedBox(width: 10),
              Text(
                'DESBLOQUEAR COFRE SOBERANO',
                style: TextStyle(
                  color: NixColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Seu banco SQLCipher local está cifrado em repouso. Informe sua frase-passe mestra para descriptografar a sessão e carregar sua identidade.',
            style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            obscureText: true,
            onSubmitted: (_) => _unlock(),
            style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Frase-passe mestra ou PIN de coação',
              errorText: _error,
              filled: true,
              fillColor: NixColors.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _busy ? null : _unlock,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.vpn_key_outlined, size: 17),
            label: const Text('Desbloquear & Montar SQLCipher'),
          ),
        ],
      ),
    );
  }
}
