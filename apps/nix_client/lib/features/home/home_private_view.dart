import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/direct_message.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../chat/message_bubble.dart';
import '../profile/card_id_widget.dart';

/// Área Principal de Conversas Privadas (Home).
/// Quando vazia (sem conversa/aba secundária selecionada), é preenchida pelo CARD ID.
/// Ao selecionar um chat ou aba (Friends, Requests, Transações, Updates), o Card ID sai de cena.
class HomePrivateView extends StatefulWidget {
  const HomePrivateView({super.key});

  @override
  State<HomePrivateView> createState() => _HomePrivateViewState();
}

class _HomePrivateViewState extends State<HomePrivateView> {
  final TextEditingController _dmInputController = TextEditingController();

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

    return Container(
      color: NixColors.background,
      child: AnimatedSwitcher(
        duration: NixTokens.motionMedium,
        switchInCurve: NixTokens.curveStandard,
        switchOutCurve: NixTokens.curveStandard,
        child: _buildStageContent(nixState, activeTab),
      ),
    );
  }

  Widget _buildStageContent(NixState state, HomeSubTab tab) {
    switch (tab) {
      case HomeSubTab.cardId:
        // Estado vazio inicial da Home -> preenchido pelo CARD ID de metal AMOLED black reluzente
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
    }
  }

  Widget _buildTopHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required NixState state,
    Widget? trailing,
  }) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: NixColors.surfaceSidebar,
        border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
      ),
      child: Row(
        children: [
          Icon(icon, color: NixColors.textPrimary, size: 19),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: NixColors.textPrimary,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 14, color: NixColors.surfaceBorderStrong),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              subtitle,
              style: const TextStyle(color: NixColors.textMuted, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // ================= CONVERSA PRIVADA (DM CHAT) =================
  Widget _buildDirectChatStage(NixState state, DirectMessageThread dm) {
    return Column(
      key: ValueKey('home_dm_${dm.id}'),
      children: [
        _buildTopHeader(
          icon: Icons.lock_outline_rounded,
          title: dm.peerName,
          subtitle: '${dm.peerPublicId} · ${dm.statusText}',
          state: state,
          trailing: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: NixColors.textSecondary),
            onPressed: () => state.selectHomeSubTab(HomeSubTab.cardId),
            icon: const Icon(Icons.badge_outlined, size: 15),
            label: const Text('Ver Card ID', style: TextStyle(fontSize: 11.5)),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: dm.messages.length,
            itemBuilder: (context, idx) => MessageBubble(message: dm.messages[idx]),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: NixColors.surfaceSidebar,
            border: Border(top: BorderSide(color: NixColors.surfaceBorder)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dmInputController,
                  onSubmitted: (_) => _sendDm(state),
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Mensagem direta cifrada para @${dm.peerName}...',
                    fillColor: NixColors.surfaceCard,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => _sendDm(state),
                icon: const Icon(Icons.send_rounded, size: 18),
              ),
            ],
          ),
        ),
      ],
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
                          Text(dm.peerName,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
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
          subtitle: 'Handshakes X3DH pendentes de aprovação local',
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
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: NixColors.surfaceCard,
                        borderRadius: NixTokens.borderMd,
                        border: Border.all(color: NixColors.surfaceBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(req.peerName,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(req.peerPublicId, style: NixTokens.monoCode()),
                                const SizedBox(height: 6),
                                Text(req.note,
                                    style: const TextStyle(
                                        color: NixColors.textSecondary, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: () => state.declineContactRequest(req.id),
                            child: const Text('Recusar',
                                style: TextStyle(color: NixColors.textMuted, fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
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
