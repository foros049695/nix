import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/message.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';

class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  static const List<String> _quickEmojis = ['⚡', '🛡️', '🔥', '👁️', '✓', '💿'];

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final settings = nixState.settings;
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
            Container(
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
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
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
                      color: isMe ? NixColors.surfaceBorderStrong : NixColors.surfaceBorder,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isMe)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
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
                            const Icon(Icons.done_all_rounded, size: 13, color: Colors.white),
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

                // Pílulas de Reações de Emojis
                if (message.reactions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: message.reactions.entries.map((entry) {
                        return InkWell(
                          onTap: () => nixState.toggleMessageReaction(message.id, entry.key),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: NixColors.surfaceCard,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: NixColors.surfaceBorderStrong),
                            ),
                            child: Text(
                              '${entry.key} ${entry.value}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
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
