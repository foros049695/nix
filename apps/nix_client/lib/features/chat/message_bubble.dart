import 'package:flutter/material.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/models/message.dart';

class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;

    final hour = message.timestamp.hour.toString().padLeft(2, '0');
    final minute = message.timestamp.minute.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            // Avatar / Identicon determinístico
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(top: 2, right: 10),
              decoration: BoxDecoration(
                color: NixColors.surfaceCardHover,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NixColors.surfaceBorder),
              ),
              child: Center(
                child: Text(
                  message.senderName.isNotEmpty ? message.senderName[0] : '?',
                  style: const TextStyle(color: NixColors.accentCyan, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 580),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? NixColors.messageSent : NixColors.messageReceived,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(isMe ? 12 : 2),
                  bottomRight: Radius.circular(isMe ? 2 : 12),
                ),
                border: Border.all(
                  color: isMe ? NixColors.accentGreen.withOpacity(0.25) : NixColors.surfaceBorder,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.senderName,
                          style: const TextStyle(
                            color: NixColors.accentCyan,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.shield_outlined, size: 11, color: NixColors.accentGreen),
                        const SizedBox(width: 2),
                        Text(
                          message.senderFingerprint.substring(0, 9),
                          style: const TextStyle(
                            color: NixColors.textMuted,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  if (!isMe) const SizedBox(height: 4),
                  // Texto da Mensagem
                  Text(
                    message.text,
                    style: const TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Rodapé: Timer efêmero + Hora + Verificação
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (message.isEphemeral) ...[
                        const Icon(Icons.local_fire_department, size: 12, color: NixColors.accentWarning),
                        const SizedBox(width: 2),
                        Text(
                          '${message.remainingSeconds}s',
                          style: const TextStyle(color: NixColors.accentWarning, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        '$hour:$minute',
                        style: const TextStyle(color: NixColors.textMuted, fontSize: 10),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.done_all_rounded, size: 14, color: NixColors.accentGreen),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
