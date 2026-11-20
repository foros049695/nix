import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/channel.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import '../dialogs/forward_message_dialog.dart';
import '../design/nix_surfaces.dart';
import 'chat_input_bar.dart';
import 'conversation_surface.dart';
import 'message_timeline.dart';
import 'message_header.dart';

class ChatView extends StatefulWidget {
  final Channel channel;

  const ChatView({super.key, required this.channel});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final messages = nixState.currentMessages;
    final pinnedMsgs = messages.where((m) => m.isPinned).toList();
    final selectedIds = nixState.selectedMessageIds;

    return Column(
      children: [
        // Cabeçalho clicável do Canal / Grupo
        if (MediaQuery.sizeOf(context).width >= nixDesktopBreakpoint)
          MessageHeader(channel: widget.channel),

        // Barra de Seleção Múltipla de Mensagens
        if (selectedIds.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: context.accentColor.withValues(alpha: 0.15),
              border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Row(
              children: [
                Text(
                  '${selectedIds.length} selecionada(s)',
                  style: TextStyle(
                    color: NixColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    final firstSelected = messages.firstWhere(
                      (m) => selectedIds.contains(m.id),
                      orElse: () => messages.first,
                    );
                    ForwardMessageDialog.show(context, firstSelected);
                  },
                  icon: const Icon(Icons.forward_rounded, size: 16),
                  label: const Text('Encaminhar', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: () => nixState.deleteSelectedMessages(forEveryone: false),
                  icon: Icon(Icons.delete_outline_rounded, size: 16, color: NixColors.accentDanger),
                  label: Text(
                    'Excluir',
                    style: TextStyle(fontSize: 12, color: NixColors.accentDanger),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 17, color: NixColors.textSecondary),
                  tooltip: 'Cancelar seleção',
                  onPressed: () => nixState.clearMessageSelection(),
                ),
              ],
            ),
          ),

        // Faixa Compacta de Mensagem Fixada no Topo da Conversa (Seção 9)
        if (pinnedMsgs.isNotEmpty)
          InkWell(
            key: const Key('pinned_message_banner'),
            onTap: () => nixState.highlightMessage(pinnedMsgs.last.id),
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
                          'Mensagem Fixada · ${pinnedMsgs.last.senderName}',
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
                    key: const Key('unpin_message_banner_button'),
                    icon: Icon(Icons.close, size: 14, color: NixColors.textMuted),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Desafixar mensagem',
                    onPressed: () => nixState.togglePinMessage(pinnedMsgs.last.id),
                  ),
                ],
              ),
            ),
          ),

        // Lista de Mensagens
        Expanded(
          child: ConversationSurface(
            child: messages.isEmpty
                ? _buildEmptyChat()
                : MessageTimeline(
                    key: ValueKey(widget.channel.id),
                    messages: messages,
                    highlightedMessageId: nixState.highlightedMessageId,
                  ),
          ),
        ),

        // Barra Inferior de Entrada
        ChatInputBar(channelName: widget.channel.name),
      ],
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.channel.icon, size: 48, color: NixColors.textMuted),
          const SizedBox(height: 12),
          Text(
            'Início de #${widget.channel.name}',
            style: TextStyle(
              color: NixColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Este tópico utiliza envelopes XChaCha20-Poly1305 e roteamento Tor Onion v3.',
            style: TextStyle(color: NixColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
