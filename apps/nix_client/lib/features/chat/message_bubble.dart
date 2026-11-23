import 'package:flutter/material.dart';
import 'conversation_surface.dart';
import 'message_attachment_tile.dart';
import 'chat_inline_format.dart';
import 'reaction_picker.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/member.dart';
import '../../core/models/message.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import '../dialogs/forward_message_dialog.dart';
import '../profile/peer_card_id_dialog.dart';
import 'article_share_card.dart';
import 'offline_location_card.dart';
import 'offline_location_picker_dialog.dart';
import 'work_share_card.dart';

class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  Future<void> _react(BuildContext context, NixState state) async {
    final emoji = await showReactionPicker(context);
    if (context.mounted && emoji != null) state.toggleMessageReaction(message.id, emoji);
  }

  Member _resolveMember(NixState state) {
    return state.members.firstWhere(
      (m) => m.name.contains(message.senderName) || m.fingerprint == message.senderFingerprint,
      orElse: () => Member(
        id: message.senderFingerprint,
        name: message.senderName,
        roleName: 'Membro Soberano',
        role: MemberRole.member,
        fingerprint: message.senderFingerprint,
        trustLevel: NixTrustLevel.level3Green,
        isOnline: true,
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position, NixState nixState) {
    final accent = context.accentColor;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: NixColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
      ),
      items: [
        const PopupMenuItem<String>(value: 'react', child: Text('Reagir com emoji')),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'reply',
          child: Row(
            children: [
              Icon(Icons.reply_rounded, size: 16, color: NixColors.textSecondary),
              const SizedBox(width: 10),
              Text('Responder', style: TextStyle(color: NixColors.textPrimary, fontSize: 13)),
            ],
          ),
        ),
        if (message.isMe)
          PopupMenuItem<String>(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 16, color: NixColors.textSecondary),
                const SizedBox(width: 10),
                Text('Editar Mensagem', style: TextStyle(color: NixColors.textPrimary, fontSize: 13)),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'pin',
          child: Row(
            children: [
              Icon(Icons.push_pin_outlined, size: 16, color: NixColors.textSecondary),
              const SizedBox(width: 10),
              Text(
                message.isPinned ? 'Desafixar' : 'Fixar Mensagem',
                style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 16, color: NixColors.textSecondary),
              const SizedBox(width: 10),
              Text('Copiar Texto', style: TextStyle(color: NixColors.textPrimary, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'forward',
          child: Row(
            children: [
              Icon(Icons.forward_rounded, size: 16, color: NixColors.textSecondary),
              const SizedBox(width: 10),
              Text('Encaminhar...', style: TextStyle(color: NixColors.textPrimary, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'save_to_saved',
          child: Row(
            children: [
              Icon(Icons.bookmark_outline_rounded, size: 16, color: context.accentTextColor),
              const SizedBox(width: 10),
              Text('Salvar em Mensagens Salvas',
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'select',
          child: Row(
            children: [
              Icon(Icons.check_box_outlined, size: 16, color: NixColors.textSecondary),
              const SizedBox(width: 10),
              Text('Selecionar Mensagem', style: TextStyle(color: NixColors.textPrimary, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'delete_me',
          child: Row(
            children: [
              const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.orangeAccent),
              const SizedBox(width: 10),
              Text('Apagar para mim', style: TextStyle(color: NixColors.textPrimary, fontSize: 13)),
            ],
          ),
        ),
        if (message.isMe)
          const PopupMenuItem<String>(
            value: 'delete_all',
            child: Row(
              children: [
                Icon(Icons.delete_forever_rounded, size: 16, color: Colors.redAccent),
                SizedBox(width: 10),
                Text('Apagar para todos', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (!context.mounted || value == null) return;
      if (value == 'react') {
        _react(context, nixState);
      } else if (value == 'reply') {
        nixState.startReplyTo(message);
      } else if (value == 'edit') {
        nixState.startEditMessage(message);
      } else if (value == 'pin') {
        nixState.togglePinMessage(message.id);
      } else if (value == 'copy') {
        Clipboard.setData(ClipboardData(text: message.text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Texto copiado com sucesso!'),
            duration: Duration(seconds: 2),
          ),
        );
      } else if (value == 'forward') {
        ForwardMessageDialog.show(context, message);
      } else if (value == 'save_to_saved') {
        nixState.saveToSavedMessages(
          message.text,
          attachments: message.attachments,
          forwardedFrom: message.senderName,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Salvo em Mensagens Salvas.')),
        );
      } else if (value == 'select') {
        nixState.toggleMessageSelection(message.id);
      } else if (value == 'delete_me') {
        nixState.deleteMessage(message.id, forEveryone: false);
      } else if (value == 'delete_all') {
        nixState.deleteMessage(message.id, forEveryone: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final settings = nixState.settings;
    final accent = context.accentColor;
    final accentText = context.accentTextColor;
    final isMe = message.isMe;
    final isSelected = nixState.selectedMessageIds.contains(message.id);
    final isHighlighted = nixState.highlightedMessageId == message.id;

    final hour = message.timestamp.hour.toString().padLeft(2, '0');
    final minute = message.timestamp.minute.toString().padLeft(2, '0');

    return Padding(
      key: Key('message_bubble_${message.id}'),
      padding: EdgeInsets.symmetric(
        vertical: settings.compactChatMode ? 2 : 5,
        horizontal: 16,
      ),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (nixState.selectedMessageIds.isNotEmpty)
            Checkbox(
              value: isSelected,
              onChanged: (_) => nixState.toggleMessageSelection(message.id),
            ),
          if (!isMe)
            InkWell(
              onTap: () => PeerCardIdDialog.showForMember(context, _resolveMember(nixState)),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(top: 2, right: 10),
                decoration: BoxDecoration(
                  color: NixColors.surfaceCard,
                  shape: BoxShape.circle,
                  border: Border.all(color: NixColors.surfaceBorderStrong),
                ),
                child: Center(
                  child: Text(
                    message.senderName.isNotEmpty ? message.senderName[0] : '?',
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: nixState.selectedMessageIds.isNotEmpty
                      ? () => nixState.toggleMessageSelection(message.id)
                      : null,
                  onSecondaryTapDown: (details) =>
                      _showContextMenu(context, details.globalPosition, nixState),
                  onLongPressStart: (details) =>
                      _showContextMenu(context, details.globalPosition, nixState),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 580),
                    padding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: settings.compactChatMode ? 7 : 10,
                    ),
                    decoration: messageDecoration(
                      context, outgoing: isMe, selected: isHighlighted || isSelected,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.forwardedFrom != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.forward_rounded, size: 12, color: accentText),
                                const SizedBox(width: 4),
                                Text(
                                  'Encaminhada de ${message.forwardedFrom}',
                                  style: TextStyle(
                                    color: accentText,
                                    fontSize: 10.5,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (message.replyToMessageId != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: NixColors.background.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(6),
                              border: Border(left: BorderSide(color: accent, width: 2.5)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message.replyToSenderName ?? 'Resposta',
                                  style: TextStyle(
                                    color: accentText,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  message.replyToExcerpt ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        if (!isMe)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: InkWell(
                              onTap: () => PeerCardIdDialog.showForMember(
                                  context, _resolveMember(nixState)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      message.senderName,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: NixColors.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12 * settings.fontScale,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    message.isVerified
                                        ? Icons.verified_outlined
                                        : Icons.gpp_maybe_outlined,
                                    size: 11,
                                    color: message.isVerified
                                        ? NixColors.textSecondary
                                        : Colors.amber,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    message.senderFingerprint.length >= 9
                                        ? message.senderFingerprint.substring(0, 9)
                                        : message.senderFingerprint,
                                    style: TextStyle(
                                      color: NixColors.textMuted,
                                      fontSize: 9.5,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (message.text.isNotEmpty) ...[
                          if (WorkShareData.tryParse(message.text) case final workData?)
                            WorkShareCard(data: workData)
                          else if (ArticleShareData.tryParse(message.text) case final articleData?)
                            ArticleShareCard(data: articleData)
                          else if (OfflineLocationData.tryParse(message.text) case final locData?)
                            OfflineLocationCard(data: locData)
                          else
                            ChatInlineText(
                              message.text,
                              style: TextStyle(
                                color: NixColors.textPrimary,
                                fontSize: 13.8 * settings.fontScale,
                                height: 1.38,
                              ),
                            ),
                        ],
                        if (message.attachments.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (var i = 0; i < message.attachments.length; i++)
                                MessageAttachmentTile(key: ValueKey('${message.id}:$i'), message: message, index: i),
                            ],
                          ),
                        ],
                        if (message.deliveryError != null &&
                            message.deliveryError!.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            message.deliveryError!,
                            key: Key('msg_delivery_error_${message.id}'),
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 5),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (message.isPinned) ...[
                              Icon(Icons.push_pin_rounded, size: 11, color: accentText),
                              const SizedBox(width: 4),
                            ],
                            if (message.isEphemeral) ...[
                              Icon(Icons.timer_outlined, size: 11, color: NixColors.textSecondary),
                              const SizedBox(width: 3),
                              Text(
                                '${message.remainingSeconds}s',
                                style: TextStyle(
                                  color: NixColors.textSecondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (message.isEdited) ...[
                              Text(
                                'editada · ',
                                style: TextStyle(
                                  color: NixColors.textMuted,
                                  fontSize: 9.5,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                            Text(
                              '$hour:$minute',
                              style: TextStyle(color: NixColors.textMuted, fontSize: 10),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              _buildDeliveryStateIcon(accentText),
                            ],
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Adicionar reação',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minHeight: 28, minWidth: 28),
                              onPressed: () => _react(context, nixState),
                              icon: Icon(Icons.add_reaction_outlined, size: 15, color: NixColors.textMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (message.reactions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: message.reactions.entries.map((entry) {
                        final isMyReaction = message.myReactions.contains(entry.key);
                        return InkWell(
                          onTap: () => nixState.toggleMessageReaction(message.id, entry.key),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: isMyReaction
                                  ? accent.withValues(alpha: 0.18)
                                  : NixColors.surfaceCard,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isMyReaction
                                    ? accent.withValues(alpha: 0.5)
                                    : NixColors.surfaceBorderStrong,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(entry.key, style: const TextStyle(fontSize: 11, fontFamilyFallback: ['NixEmoji'])),
                                const SizedBox(width: 4),
                                Text(
                                  '${entry.value}',
                                  style: TextStyle(
                                    color: isMyReaction ? accentText : NixColors.textPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryStateIcon(Color accentText) {
    final (icon, label, keyState, color) = switch (message.deliveryState) {
      'failed' => (Icons.error_outline_rounded, 'Falhou', 'failed', Colors.redAccent),
      'queued' => (Icons.schedule_rounded, 'Na fila', 'queued', NixColors.textMuted),
      'draft' => (Icons.edit_outlined, 'Rascunho', 'draft', NixColors.textMuted),
      'sending' => (Icons.schedule_rounded, 'Enviando', 'sending', NixColors.textMuted),
      'accepted' => (Icons.done_rounded, 'Aceita pelo relay', 'accepted', accentText),
      'delivered' => (Icons.done_all_rounded, 'Entregue', 'delivered', accentText),
      'received' => (Icons.done_all_rounded, 'Recebida', 'received', accentText),
      'read' => (Icons.done_all_rounded, 'Lida', 'read', accentText),
      'saved' => (Icons.bookmark_outline_rounded, 'Salva no aparelho', 'saved', accentText),
      _ => (Icons.help_outline_rounded, 'Estado desconhecido', 'unknown', NixColors.textMuted),
    };
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Icon(
        icon,
        key: Key('msg_state_${keyState}_${message.id}'),
        semanticLabel: label,
        size: 13,
        color: color,
      ),
    );
  }
}
