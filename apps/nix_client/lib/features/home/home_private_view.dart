import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../monero_p2p/monero_finance_view.dart';
import '../../core/models/direct_message.dart';
import '../../core/models/member.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../chat/chat_input_bar.dart';
import '../chat/conversation_info_panel.dart';
import '../chat/conversation_surface.dart';
import '../design/nix_surfaces.dart';
import '../chat/message_timeline.dart';
import '../profile/pager_profile.dart';
import '../profile/peer_card_id_dialog.dart';

/// Área Principal de Conversas Privadas (Home).
/// Quando vazia (sem conversa/aba secundária selecionada), é preenchida pelo CARD ID.
/// Ao selecionar um chat ou aba, o Card ID sai de cena.
/// Suporta pré-visualização flutuante animada do Card ID em solicitações.
class HomePrivateView extends StatefulWidget {
  const HomePrivateView({super.key});

  @override
  State<HomePrivateView> createState() => _HomePrivateViewState();
}

class _HomePrivateViewState extends State<HomePrivateView> {
  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final activeTab = nixState.homeSubTab;

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              if (nixState.hoveredContactRequest != null) {
                nixState.dismissHoveredPeerCard();
              }
              return null;
            },
          ),
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Faixa central-direita livre: nunca cobre o nome/avatar (esquerda) nem Recusar/Aceitar (direita)
            final double maxSafeLeft = (constraints.maxWidth - 295 - 260).clamp(200.0, 560.0);
            final double safeLeft = (constraints.maxWidth * 0.32).clamp(200.0, maxSafeLeft);

            return Container(
              color: NixColors.background,
              child: Stack(
                children: [
                  AnimatedSwitcher(
                    duration: NixTokens.motionMedium,
                    switchInCurve: NixTokens.curveStandard,
                    switchOutCurve: NixTokens.curveStandard,
                    child: _buildStageContent(nixState, activeTab),
                  ),
                  if (activeTab == HomeSubTab.requests)
                    ListenableBuilder(
                      listenable: nixState.peerHover,
                      builder: (context, _) {
                        final hover = nixState.peerHover;
                        if (hover.hoveredContactRequest == null ||
                            hover.peerHoverState == PeerCardHoverState.closingRequested ||
                            nixState.settings.cardIdVisibility == 'Oculto') {
                          return const SizedBox.shrink();
                        }
                        return Positioned(
                          top: 74,
                          left: safeLeft,
                          child: MouseRegion(
                            onEnter: (_) => hover.setHoverOverPreviewCard(true),
                            onExit: (_) => hover.setHoverOverPreviewCard(false),
                            child: _FloatingPeerCardIdPreview(
                              request: hover.hoveredContactRequest!,
                              onDismiss: () => hover.dismissHoveredPeerCard(),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStageContent(NixState state, HomeSubTab tab) {
    switch (tab) {
      case HomeSubTab.cardId:
        return PagerProfile(
          key: const ValueKey('home_stage_card_id'),
          onOpenSettings: () => state.openProfileOverlay(startInSettings: true),
        );

      case HomeSubTab.directChat:
        final dm = state.selectedDm;
        if (dm == null) {
          return PagerProfile(
            key: const ValueKey('home_stage_fallback_card'),
            onOpenSettings: () => state.openProfileOverlay(startInSettings: true),
          );
        }
        return _buildDirectChatStage(state, dm);

      case HomeSubTab.friends:
        return _buildFriendsStage(state);

      case HomeSubTab.requests:
        return _buildRequestsStage(state);

      case HomeSubTab.transactions:
        return const MoneroWalletView();

      case HomeSubTab.updates:
        return _buildUpdatesStage(state);

      case HomeSubTab.moneroP2p:
      case HomeSubTab.githubDiscovery:
        return PagerProfile(
          key: const ValueKey('home_stage_default_card'),
          onOpenSettings: () => state.openProfileOverlay(startInSettings: true),
        );
    }
  }

  Widget _buildTopHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required NixState state,
  }) {
    final compact = MediaQuery.sizeOf(context).width < 520;
    final transport = state.isStrictOffGridMode
        ? 'Bluetooth off-grid'
        : state.securityGate.isTorAnonymityReady
            ? 'Tor Onion v3'
            : 'Tor indisponível';
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20, vertical: 6),
      decoration: BoxDecoration(
        color: NixColors.surfaceElevated,
        border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: NixColors.textPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  style: TextStyle(color: NixColors.textMuted, fontSize: 10.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: transport,
            child: Icon(
              state.isStrictOffGridMode ? Icons.bluetooth : Icons.lock_outline_rounded,
              semanticLabel: transport,
              size: 18,
              color: NixColors.textSecondary,
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 5),
            Text(transport, style: TextStyle(color: NixColors.textSecondary, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  // ================= ABA AMIGOS =================
  Widget _buildFriendsStage(NixState state) {
    final friends = state.directMessages.where((d) => !d.isSavedMessages).toList();
    return Column(
      key: const ValueKey('home_stage_friends'),
      children: [
        _buildTopHeader(
          icon: Icons.people_outline_rounded,
          title: 'Amigos & Pares Verificados',
          subtitle: '${friends.length} contatos com fingerprint validado · Clique no nome/avatar para Card ID',
          state: state,
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: friends.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, idx) {
              final dm = friends[idx];
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: NixColors.surfaceCard,
                  borderRadius: NixTokens.borderMd,
                  border: Border.all(color: NixColors.surfaceBorder),
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => PeerCardIdDialog.showForDirectMessage(context, dm),
                      borderRadius: BorderRadius.circular(24),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: NixColors.surfaceActive,
                              shape: BoxShape.circle,
                              border: Border.all(color: NixColors.surfaceBorderStrong),
                            ),
                            child: Center(
                              child: Text(
                                dm.peerName[0],
                                style: TextStyle(
                                    color: NixColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(dm.peerName,
                                      style: TextStyle(
                                          color: NixColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  _TrustLevelIndicator(level: dm.trustLevel),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(dm.peerPublicId, style: NixTokens.monoCode()),
                              const SizedBox(height: 2),
                              Text(dm.statusText,
                                  style: TextStyle(color: NixColors.textMuted, fontSize: 11.5)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () => state.selectDirectMessage(dm),
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                      label: const Text('Abrir Conversa', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ================= ABA SOLICITAÇÕES =================
  Widget _buildRequestsStage(NixState state) {
    return Column(
      key: const ValueKey('home_stage_requests'),
      children: [
        _buildTopHeader(
          icon: Icons.mark_email_unread_outlined,
          title: 'Solicitações de Contato',
          subtitle: 'Handshakes X3DH pendentes de aprovação local · Passe o mouse para inspecionar Card ID',
          state: state,
        ),
        Expanded(
          child: state.contactRequests.isEmpty
              ? Center(
                  child: Text(
                    'Nenhuma solicitação de contato pendente.',
                    style: TextStyle(color: NixColors.textMuted, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: state.contactRequests.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    final req = state.contactRequests[idx];
                    final isHovered = state.hoveredContactRequest?.id == req.id;
                    final accent = context.accentColor;
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: NixColors.surfaceCard,
                        borderRadius: NixTokens.borderMd,
                        border: Border.all(
                          color: isHovered
                              ? accent.withValues(alpha: 0.6)
                              : NixColors.surfaceBorder,
                          width: isHovered ? 1.2 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          // 1. ZONA EXCLUSIVA DE HOVER E CLIQUE: Avatar + Nome
                          MouseRegion(
                            onEnter: (_) => state.onRequestPeerHoverEnter(req),
                            onExit: (_) => state.onRequestPeerHoverExit(req),
                            child: InkWell(
                              onTap: () => PeerCardIdDialog.showForRequest(context, req),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: NixColors.surfaceElevated,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: accent.withValues(alpha: 0.5)),
                                      ),
                                      child: Center(
                                        child: Text(
                                          req.peerName.isNotEmpty ? req.peerName[0].toUpperCase() : '?',
                                          style: TextStyle(
                                            color: accent,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              req.peerName,
                                              style: TextStyle(
                                                color: NixColors.textPrimary,
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Icon(Icons.badge_outlined, size: 12, color: accent),
                                          ],
                                        ),
                                        const SizedBox(width: 4),
                                        _TrustLevelIndicator(level: req.trustLevel),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),

                          // 2. Informações Públicas (Sem ativar hover do Card ID)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(req.peerPublicId, style: NixTokens.monoCode(size: 11)),
                                const SizedBox(height: 4),
                                Text(
                                  req.note,
                                  style: TextStyle(
                                    color: NixColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),

                          // 3. Botões de Ação (100% Desobstruídos, sem ativar hover)
                          TextButton(
                            onPressed: () => state.declineContactRequest(req.id),
                            child: Text('Recusar',
                                style: TextStyle(color: NixColors.textMuted, fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: context.onAccentColor,
                            ),
                            onPressed: () => state.acceptContactRequest(req.id),
                            child: const Text('Aceitar Chave',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ================= ABA CONVERSA PRIVADA SELECIONADA =================
  Widget _buildDirectChatStage(NixState state, DirectMessageThread dm) {
    final pinnedMsgs = dm.messages.where((m) => m.isPinned).toList();

    return Column(
      key: ValueKey('stage_dm_${dm.id}'),
      children: [
        // Cabeçalho clicável (abre Painel de Informações da Conversa ou Card ID no nome)
        InkWell(
          key: const Key('dm_chat_header'),
          onTap: () => ConversationInfoPanel.open(context, directMessage: dm),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: NixColors.surfaceElevated,
              border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Row(
              children: [
                Icon(
                  dm.isSavedMessages
                      ? Icons.bookmark_rounded
                      : dm.hasActiveSession ? Icons.lock_rounded : Icons.lock_open_rounded,
                  size: 16,
                  color: dm.isSavedMessages ? context.accentTextColor
                      : dm.hasActiveSession ? NixColors.accentGreen : NixColors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: dm.isSavedMessages
                        ? () => ConversationInfoPanel.open(context, directMessage: dm)
                        : () => PeerCardIdDialog.showForDirectMessage(context, dm),
                    borderRadius: NixTokens.borderButtonCompact,
                    child: NixPanelTitle(
                      icon: dm.isSavedMessages ? Icons.bookmark_outline : Icons.person_outline,
                      title: dm.peerName,
                      subtitle: dm.hasActiveSession && state.isStrictOffGridMode
                          ? 'Sessão E2EE · Bluetooth direto' : dm.statusText,
                    ),
                  ),
                ),
                if (!dm.isSavedMessages && MediaQuery.sizeOf(context).width >= 700)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _TrustLevelIndicator(level: dm.trustLevel),
                  ),
                if (!dm.isSavedMessages)
                  IconButton(
                    key: const Key('dm_sync_relay_button'),
                    icon: Icon(
                      Icons.sync_rounded,
                      size: 17,
                      color: NixColors.textSecondary,
                    ),
                    tooltip: state.isStrictOffGridMode
                        ? 'Retentar envio por Bluetooth'
                        : 'Sincronizar Outbox / Inbox via Relay',
                    onPressed: () async {
                      if (state.isStrictOffGridMode) {
                        await state.retryNearbyMessages();
                      } else {
                        await state.syncWithRelay();
                      }
                    },
                  ),
                IconButton(
                  key: const Key('dm_info_panel_button'),
                  icon: Icon(
                    Icons.view_sidebar_outlined,
                    size: 18,
                    color: state.isConversationInfoOpen
                        ? context.accentTextColor
                        : NixColors.textSecondary,
                  ),
                  tooltip: 'Informações & Mídia da Conversa',
                  onPressed: () => ConversationInfoPanel.open(context, directMessage: dm),
                ),
              ],
            ),
          ),
        ),

        // Banner de erro de envio / transporte E2EE
        if (state.lastMessagingError != null)
          Container(
            key: const Key('dm_messaging_error_banner'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.14),
              border: Border(
                bottom: BorderSide(color: Colors.redAccent.withValues(alpha: 0.45)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, size: 16, color: Colors.redAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.lastMessagingError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 11.5),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    if (state.isStrictOffGridMode) {
                      await state.retryNearbyMessages();
                    } else {
                      await state.syncWithRelay();
                    }
                  },
                  child: const Text('Retentar Outbox', style: TextStyle(fontSize: 11)),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 14, color: NixColors.textMuted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: state.clearLastMessagingError,
                ),
              ],
            ),
          ),

        // Faixa compacta de Mensagem Fixada (estilo Telegram)
        if (pinnedMsgs.isNotEmpty)
          InkWell(
            onTap: () => state.highlightMessage(pinnedMsgs.last.id),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: NixColors.surfaceCard,
                border: Border(
                  bottom: BorderSide(color: NixColors.surfaceBorder),
                  left: BorderSide(color: context.accentColor, width: 3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.push_pin_rounded, size: 14, color: context.accentTextColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mensagem Fixada',
                          style: TextStyle(
                            color: context.accentTextColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          pinnedMsgs.last.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 14, color: NixColors.textMuted),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Desafixar',
                    onPressed: () => state.togglePinMessage(pinnedMsgs.last.id),
                  ),
                ],
              ),
            ),
          ),

        // Lista de Mensagens Cifradas
        Expanded(
          child: ConversationSurface(child: dm.messages.isEmpty
              ? Center(
                  child: Text(
                    dm.isSavedMessages
                        ? 'Salve notas, arquivos, links ou mensagens encaminhadas aqui.'
                        : 'Sessão iniciada. Envie a primeira mensagem privada cifrada.',
                    style: TextStyle(color: NixColors.textMuted, fontSize: 12.5),
                  ),
                )
              : MessageTimeline(
                  key: ValueKey(dm.id),
                  messages: dm.messages,
                  highlightedMessageId: state.highlightedMessageId,
                ),
          ),
        ),

        // Compositor Completo para DMs e Mensagens Salvas (Anexos, Emojis, Áudio, Temporizador)
        ChatInputBar(
          key: ValueKey(dm.id),
          scheduledConversationId: dm.hasActiveSession && !dm.isSavedMessages ? dm.id : null,
          channelName: dm.isSavedMessages ? 'Mensagens Salvas' : dm.peerName,
          isDirectMessage: true,
          onSendCustom: (text, attachments) => state.sendDirectMessage(text, attachments: attachments),
        ),
      ],
    );
  }

  // ================= ABA ATUALIZAÇÕES =================
  Widget _buildUpdatesStage(NixState state) {
    return Column(
      key: const ValueKey('home_stage_updates'),
      children: [
        _buildTopHeader(
          icon: Icons.bolt_outlined,
          title: 'Atualizações e Notas de Engenharia',
          subtitle: 'Registro auditável de releases do ecossistema Nix',
          state: state,
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: state.systemUpdates.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, idx) {
              final upd = state.systemUpdates[idx];
              return Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: NixColors.surfaceCard,
                  borderRadius: NixTokens.borderMd,
                  border: Border.all(color: NixColors.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(upd.version,
                            style: TextStyle(
                                color: NixColors.textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold)),
                        Text(upd.dateLabel,
                            style: TextStyle(color: NixColors.textMuted, fontSize: 11.5)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(upd.title,
                        style: TextStyle(
                            color: NixColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(upd.summary,
                        style: TextStyle(color: NixColors.textMuted, fontSize: 12)),
                    const SizedBox(height: 10),
                    ...upd.highlights.map((h) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('• ', style: TextStyle(color: NixColors.textPrimary)),
                              Expanded(
                                child: Text(h,
                                    style: TextStyle(
                                        color: NixColors.textSecondary, fontSize: 12)),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Indicador de Nível de Confiança Nix (3 Níveis Semânticos)
class _TrustLevelIndicator extends StatelessWidget {
  final NixTrustLevel level;

  const _TrustLevelIndicator({required this.level});

  @override
  Widget build(BuildContext context) {
    Color dotColor;
    int dotCount;
    String tooltip;

    switch (level) {
      case NixTrustLevel.level1Red:
        dotColor = NixColors.trustLevel1Red;
        dotCount = 1;
        tooltip = 'Nível 1: Não verificado diretamente / contato externo';
        break;
      case NixTrustLevel.level2Yellow:
        dotColor = NixColors.trustLevel2Yellow;
        dotCount = 2;
        tooltip = 'Nível 2: Conhecido por contexto de espaço privado compartilhado';
        break;
      case NixTrustLevel.level3Green:
        dotColor = NixColors.trustLevel3Green;
        dotCount = 3;
        tooltip = 'Nível 3: Verificado diretamente por troca de chave / QR Code presencial';
        break;
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...List.generate(
              dotCount,
              (i) => Container(
                width: 6,
                height: 6,
                margin: EdgeInsets.only(left: i > 0 ? 3 : 0),
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.shield, size: 10, color: dotColor),
          ],
        ),
      ),
    );
  }
}

/// Pré-visualização Flutuante Animada do Card ID em Solicitações
class _FloatingPeerCardIdPreview extends StatelessWidget {
  final ContactRequest request;
  final VoidCallback onDismiss;

  const _FloatingPeerCardIdPreview({
    required this.request,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final auth = nixState.getAuthorizedPeerCardData(
      peerName: request.peerName,
      peerPublicId: request.peerPublicId,
      trustLevel: request.trustLevel,
      hasCryptographicShield: true,
      rawBio: request.bio,
      rawHighlights: request.culturalHighlights,
      ownerVisibility: request.cardIdVisibility,
      isVerifiedContact: request.trustLevel == NixTrustLevel.level3Green,
    );

    return Material(
      key: const Key('floating_peer_card_id_preview'),
      color: Colors.transparent,
      elevation: 24,
      child: Container(
        width: 290,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: NixTokens.amoledMetalGradient,
          borderRadius: NixTokens.borderLg,
          border: Border.all(color: context.accentColor.withValues(alpha: 0.6), width: 1.3),
          boxShadow: [
            BoxShadow(
              color: context.accentColor.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            const BoxShadow(
              color: Colors.black,
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1F2229),
                    border: Border.all(color: Colors.white38),
                  ),
                  child: Center(
                    child: Text(
                      request.peerName[0],
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              request.peerName,
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _TrustLevelIndicator(level: request.trustLevel),
                        ],
                      ),
                      Text(
                        request.peerPublicId,
                        style: const TextStyle(
                          color: Color(0xFFB7BAC4),
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('floating_card_id_close_button'),
                  icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFB7BAC4)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Fechar (Esc)',
                  onPressed: onDismiss,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                auth.bio,
                style: const TextStyle(color: Color(0xFFB7BAC4), fontSize: 11.5, height: 1.3),
              ),
            ),
            if (auth.culturalHighlights.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'DESTAQUES CULTURAIS PÚBLICOS',
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: auth.culturalHighlights.map((h) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      h,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
