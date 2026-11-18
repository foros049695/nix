import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/direct_message.dart';
import '../../core/models/member.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../chat/message_bubble.dart';
import '../profile/card_id_widget.dart';
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
  final TextEditingController _dmInputController = TextEditingController();
  String? _hoverLockoutRequestId;

  @override
  void dispose() {
    _dmInputController.dispose();
    super.dispose();
  }

  void _sendDm(NixState state) {
    final text = _dmInputController.text;
    if (text.trim().isNotEmpty) {
      state.sendDirectMessage(text);
      _dmInputController.clear();
    }
  }

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
                setState(() => _hoverLockoutRequestId = nixState.hoveredContactRequest?.id);
                nixState.setHoveredContactRequest(null);
              }
              return null;
            },
          ),
        },
        child: Container(
          color: NixColors.background,
          child: Stack(
            children: [
              AnimatedSwitcher(
                duration: NixTokens.motionMedium,
                switchInCurve: NixTokens.curveStandard,
                switchOutCurve: NixTokens.curveStandard,
                child: _buildStageContent(nixState, activeTab),
              ),
              // Painel Flutuante Animado de Card ID (Hover Preview em Solicitações)
              // Posicionado de forma inteligente para NUNCA cobrir os botões de ação na direita
              if (activeTab == HomeSubTab.requests &&
                  nixState.hoveredContactRequest != null &&
                  nixState.settings.cardIdVisibility != 'Oculto')
                Positioned(
                  top: 76,
                  left: 24,
                  child: _FloatingPeerCardIdPreview(
                    request: nixState.hoveredContactRequest!,
                    onDismiss: () {
                      setState(() {
                        _hoverLockoutRequestId = nixState.hoveredContactRequest?.id;
                      });
                      nixState.setHoveredContactRequest(null);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageContent(NixState state, HomeSubTab tab) {
    switch (tab) {
      case HomeSubTab.cardId:
        return Column(
          key: const ValueKey('home_stage_card_id'),
          children: [
            _buildTopHeader(
              icon: Icons.badge_outlined,
              title: 'Identidade Pública & Passaporte Cultural',
              subtitle: 'Selecione uma conversa privada à esquerda ou gerencie seu Card ID',
              state: state,
            ),
            Expanded(
              child: CardIdWidget(
                onOpenSettings: () => state.openProfileOverlay(startInSettings: true),
                showCulturalPassport: true,
              ),
            ),
          ],
        );

      case HomeSubTab.directChat:
        final dm = state.selectedDm;
        if (dm == null) {
          return CardIdWidget(
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
        return _buildTransactionsStage(state);

      case HomeSubTab.updates:
        return _buildUpdatesStage(state);

      case HomeSubTab.moneroP2p:
      case HomeSubTab.githubDiscovery:
        return CardIdWidget(
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
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
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
                  style: const TextStyle(color: NixColors.textMuted, fontSize: 10.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Status Tor Onion
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: NixColors.surfaceActive,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white24, width: 0.5),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, size: 11, color: NixColors.accentGreen),
                SizedBox(width: 5),
                Text(
                  'TOR ONION V3 E2EE',
                  style: TextStyle(
                    color: NixColors.textSecondary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= ABA AMIGOS =================
  Widget _buildFriendsStage(NixState state) {
    return Column(
      key: const ValueKey('home_stage_friends'),
      children: [
        _buildTopHeader(
          icon: Icons.people_outline_rounded,
          title: 'Amigos & Pares Verificados',
          subtitle: '${state.directMessages.length} contatos com fingerprint validado',
          state: state,
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: state.directMessages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, idx) {
              final dm = state.directMessages[idx];
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: NixColors.surfaceCard,
                  borderRadius: NixTokens.borderMd,
                  border: Border.all(color: NixColors.surfaceBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: NixColors.surfaceActive,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white38),
                      ),
                      child: Center(
                        child: Text(
                          dm.peerName[0],
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(dm.peerName,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              _TrustLevelIndicator(level: dm.trustLevel),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(dm.peerPublicId, style: NixTokens.monoCode()),
                          const SizedBox(height: 2),
                          Text(dm.statusText,
                              style: const TextStyle(color: NixColors.textMuted, fontSize: 11.5)),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: NixColors.surfaceBorderStrong),
                      ),
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
              ? const Center(
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
                            onEnter: (_) {
                              if (_hoverLockoutRequestId != req.id) {
                                state.setHoveredContactRequest(req);
                              }
                            },
                            onExit: (_) {
                              if (state.hoveredContactRequest?.id == req.id) {
                                state.setHoveredContactRequest(null);
                              }
                              if (_hoverLockoutRequestId == req.id) {
                                _hoverLockoutRequestId = null;
                              }
                            },
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
                                              style: const TextStyle(
                                                color: Colors.white,
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
                                  style: const TextStyle(
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
                            child: const Text('Recusar',
                                style: TextStyle(color: NixColors.textMuted, fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.black,
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
    return Column(
      key: ValueKey('stage_dm_${dm.id}'),
      children: [
        // Cabeçalho da Conversa Privada com Nível de Confiança
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: const BoxDecoration(
            color: NixColors.surfaceElevated,
            border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_rounded, size: 16, color: NixColors.accentGreen),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => PeerCardIdDialog.showForDirectMessage(context, dm),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dm.peerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.badge_outlined, size: 12, color: context.accentColor),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _TrustLevelIndicator(level: dm.trustLevel),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  dm.statusText,
                  style: const TextStyle(color: NixColors.textMuted, fontSize: 11.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: NixColors.surfaceActive,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'DOUBLE RATCHET',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Lista de Mensagens Cifradas
        Expanded(
          child: dm.messages.isEmpty
              ? const Center(
                  child: Text(
                    'Sessão iniciada. Envie a primeira mensagem privada cifrada.',
                    style: TextStyle(color: NixColors.textMuted, fontSize: 12.5),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: dm.messages.length,
                  itemBuilder: (context, idx) {
                    final msg = dm.messages[idx];
                    return MessageBubble(
                      message: msg,
                    );
                  },
                ),
        ),

        // Barra de Input DM
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: NixColors.surfaceElevated,
            border: Border(top: BorderSide(color: NixColors.surfaceBorder)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dmInputController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Mensagem cifrada para ${dm.peerName}...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onSubmitted: (_) => _sendDm(state),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                onPressed: () => _sendDm(state),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ================= ABA TRANSAÇÕES (XMR) =================
  Widget _buildTransactionsStage(NixState state) {
    return Column(
      key: const ValueKey('home_stage_transactions'),
      children: [
        _buildTopHeader(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Nix Wallet · Transações Monero (XMR)',
          subtitle: 'Processo isolado Seed B · Zero vinculação com a identidade de mensageria',
          state: state,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: NixTokens.amoledMetalGradient,
                  borderRadius: NixTokens.borderMd,
                  border: Border.all(color: NixColors.surfaceBorderStrong),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SALDO DESBLOQUEADO (SEED B ISOLADA)',
                            style: TextStyle(
                                color: NixColors.textMuted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0)),
                        SizedBox(height: 6),
                        Text('4.825000000000 XMR',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'monospace')),
                      ],
                    ),
                    Chip(
                      label: Text('Nó Remoto .onion Ativo', style: TextStyle(fontSize: 11)),
                      backgroundColor: NixColors.surfaceCard,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('HISTÓRICO DE LIQUIDAÇÕES LOCAL', style: NixTokens.labelUppercase()),
              const SizedBox(height: 10),
              ...state.transactions.map((tx) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: NixColors.surfaceCard,
                      borderRadius: NixTokens.borderSm,
                      border: Border.all(color: NixColors.surfaceBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          tx.isIncoming
                              ? Icons.call_received_rounded
                              : Icons.call_made_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tx.title,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text('${tx.subaddressPreview} · ${tx.confirmations} confirmações',
                                  style: const TextStyle(
                                      color: NixColors.textMuted, fontSize: 11)),
                            ],
                          ),
                        ),
                        Text(
                          tx.amountXmr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
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
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold)),
                        Text(upd.dateLabel,
                            style: const TextStyle(color: NixColors.textMuted, fontSize: 11.5)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(upd.title,
                        style: const TextStyle(
                            color: NixColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(upd.summary,
                        style: const TextStyle(color: NixColors.textMuted, fontSize: 12)),
                    const SizedBox(height: 10),
                    ...upd.highlights.map((h) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• ', style: TextStyle(color: Colors.white)),
                              Expanded(
                                child: Text(h,
                                    style: const TextStyle(
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
    return Material(
      color: Colors.transparent,
      elevation: 24,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: NixTokens.amoledMetalGradient,
          borderRadius: NixTokens.borderLg,
          border: Border.all(color: context.accentColor.withValues(alpha: 0.5), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: context.accentColor.withValues(alpha: 0.15),
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
                    color: NixColors.surfaceActive,
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
                      Text(request.peerPublicId, style: NixTokens.monoCode(size: 10)),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('floating_card_id_close_button'),
                  icon: const Icon(Icons.close_rounded, size: 16, color: NixColors.textMuted),
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
                request.bio,
                style: const TextStyle(color: NixColors.textSecondary, fontSize: 11.5, height: 1.3),
              ),
            ),
            const SizedBox(height: 10),
            Text('DESTAQUES CULTURAIS PÚBLICOS', style: NixTokens.labelUppercase()),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: request.culturalHighlights.map((h) {
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
        ),
      ),
    );
  }
}
