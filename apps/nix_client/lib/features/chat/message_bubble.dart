import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/member.dart';
import '../../core/models/message.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import '../dialogs/forward_message_dialog.dart';
import '../profile/peer_card_id_dialog.dart';

class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  static const List<String> _quickEmojis = ['⚡', '🛡️', '🔥', '👁️', '✓', '💿', '❤️'];

  Member _resolveMember(NixState state) {
    return state.members.firstWhere(
      (m) => m.name == message.senderName,
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
        side: BorderSide(color: accent.withValues(alpha: 0.3)),
      ),
      items: [
        // Barra Rápida de Reações
        PopupMenuItem<String>(
          enabled: false,
          child: Wrap(
            spacing: 6,
            children: _quickEmojis.map((e) {
              return InkWell(
                onTap: () {
                  nixState.toggleMessageReaction(message.id, e);
                  Navigator.of(context).pop();
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(e, style: const TextStyle(fontSize: 18)),
                ),
              );
            }).toList(),
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 16, color: NixColors.textSecondary),
              SizedBox(width: 10),
              Text('Copiar Texto', style: TextStyle(color: NixColors.textPrimary, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'forward',
          child: Row(
            children: [
              Icon(Icons.forward_rounded, size: 16, color: NixColors.textSecondary),
              SizedBox(width: 10),
              Text('Encaminhar...', style: TextStyle(color: NixColors.textPrimary, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem<String>(
          value: 'delete_me',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 16, color: Colors.orangeAccent),
              SizedBox(width: 10),
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
      if (!context.mounted) return;
      if (value == 'copy') {
        Clipboard.setData(ClipboardData(text: message.text));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: NixColors.surfaceCard,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: accent.withValues(alpha: 0.5)),
            ),
            content: const Text('Texto copiado com sucesso!', style: TextStyle(color: NixColors.textPrimary)),
            duration: const Duration(seconds: 2),
          ),
        );
      } else if (value == 'forward') {
        ForwardMessageDialog.show(context, message);
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
    final isMe = message.isMe;

    final hour = message.timestamp.hour.toString().padLeft(2, '0');
    final minute = message.timestamp.minute.toString().padLeft(2, '0');

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: settings.compactChatMode ? 2 : 5,
        horizontal: 16,
      ),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            // Avatar com abertura do Card ID por clique
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Balão de Mensagem com Detector de Toque Longo / Botão Direito
                GestureDetector(
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
                    decoration: BoxDecoration(
                      color: isMe ? NixColors.messageSent : NixColors.messageReceived,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomLeft: Radius.circular(isMe ? 12 : 3),
                        bottomRight: Radius.circular(isMe ? 3 : 12),
                      ),
                      border: Border.all(
                        color: isMe
                            ? accent.withValues(alpha: 0.3)
                            : NixColors.surfaceBorder,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMe)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: InkWell(
                              onTap: () => PeerCardIdDialog.showForMember(
                                  context, _resolveMember(nixState)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    message.senderName,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12 * settings.fontScale,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.verified_outlined,
                                    size: 11,
                                    color: NixColors.textSecondary,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    message.senderFingerprint.length >= 9
                                        ? message.senderFingerprint.substring(0, 9)
                                        : message.senderFingerprint,
                                    style: const TextStyle(
                                      color: NixColors.textMuted,
                                      fontSize: 9.5,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Text(
                          message.text,
                          style: TextStyle(
                            color: NixColors.textPrimary,
                            fontSize: 13.8 * settings.fontScale,
                            height: 1.38,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (message.isEphemeral) ...[
                              const Icon(
                                Icons.timer_outlined,
                                size: 11,
                                color: NixColors.textSecondary,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${message.remainingSeconds}s',
                                style: const TextStyle(
                                  color: NixColors.textSecondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              '$hour:$minute',
                              style: const TextStyle(color: NixColors.textMuted, fontSize: 10),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.done_all_rounded, size: 13, color: accent),
                            ],
                            const SizedBox(width: 6),
                            // Botão rápido para reagir com Emoji
                            PopupMenuButton<String>(
                              tooltip: 'Reagir com Emoji',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              color: NixColors.surfaceCard,
                              onSelected: (emoji) =>
                                  nixState.toggleMessageReaction(message.id, emoji),
                              itemBuilder: (_) => [
                                PopupMenuItem<String>(
                                  enabled: false,
                                  child: Wrap(
                                    spacing: 8,
                                    children: _quickEmojis
                                        .map((e) => InkWell(
                                              onTap: () {
                                                nixState.toggleMessageReaction(message.id, e);
                                                Navigator.pop(context);
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.all(4),
                                                child: Text(e, style: const TextStyle(fontSize: 18)),
                                              ),
                                            ))
                                        .toList(),
                                  ),
                                ),
                              ],
                              child: const Icon(
                                Icons.add_reaction_outlined,
                                size: 13,
                                color: NixColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Pílulas de Reações de Emojis Reativas e Alternáveis
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
                                Text(
                                  entry.key,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${entry.value}',
                                  style: TextStyle(
                                    color: isMyReaction ? accent : Colors.white,
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
}
