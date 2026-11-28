import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/channel.dart';
import '../../core/models/message.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import '../dialogs/forward_message_dialog.dart';
import '../design/nix_surfaces.dart';
import 'chat_input_bar.dart';
import 'conversation_surface.dart';
import 'message_timeline.dart';
import 'message_header.dart';
import 'local_group_poll_sheet.dart';
import '../navigation/workspace_image.dart';

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
    final allMessages = nixState.messagesFor(widget.channel.id);
    final isAnnouncement = widget.channel.type == ChannelType.announcement;
    // Em canais de transmissão estilo Telegram, a timeline principal foca nas postagens oficiais;
    // comentários ficam agrupados na discussão de cada postagem.
    final messages = isAnnouncement
        ? allMessages.where((m) => m.replyToMessageId == null).toList()
        : allMessages;
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
                    if (selectedIds.isEmpty) return;
                    Message? target;
                    for (final m in messages) {
                      if (selectedIds.contains(m.id)) {
                        target = m;
                        break;
                      }
                    }
                    if (target == null) {
                      final allMsgs = nixState.messagesFor(widget.channel.id);
                      for (final m in allMsgs) {
                        if (selectedIds.contains(m.id)) {
                          target = m;
                          break;
                        }
                      }
                    }
                    if (target != null) {
                      ForwardMessageDialog.show(context, target);
                    }
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

        if (nixState.canUseLocalGroupPolls(widget.channel.id) ||
            nixState.localGroupPollsFor(widget.channel.id).isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.poll_outlined, size: 18),
              label: const Text('Enquetes'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => LocalGroupPollSheet(channelId: widget.channel.id),
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
    final nixState = context.read<NixState>();
    final currentSpace = nixState.currentSpace;
    final isAnnouncement = widget.channel.type == ChannelType.announcement;
    String displayName = widget.channel.name;
    if (isAnnouncement && (displayName == 'comunicados' || displayName == 'geral') && currentSpace.name.isNotEmpty) {
      displayName = currentSpace.name;
    }
    final imagePath = widget.channel.customImagePath ?? currentSpace.customImagePath;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (imagePath != null && imagePath.isNotEmpty)
            ClipOval(
              child: SizedBox(
                width: 64,
                height: 64,
                child: WorkspaceImage(
                  path: imagePath,
                  size: 64,
                  fallback: Icon(widget.channel.icon, size: 48, color: NixColors.textMuted),
                ),
              ),
            )
          else
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.accentColor.withValues(alpha: 0.16),
                border: Border.all(color: context.accentColor.withValues(alpha: 0.35), width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'NX',
                style: TextStyle(
                  color: context.accentTextColor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            isAnnouncement ? displayName : 'Início de #${widget.channel.name}',
            style: TextStyle(
              color: NixColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              isAnnouncement
                  ? (widget.channel.topic.isNotEmpty
                      ? widget.channel.topic
                      : (currentSpace.description.isNotEmpty
                          ? currentSpace.description
                          : 'Canal de transmissão seguro com criptografia de ponta a ponta.'))
                  : 'Este canal utiliza envelopes XChaCha20-Poly1305 e roteamento Tor Onion v3.',
              style: TextStyle(color: NixColors.textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
