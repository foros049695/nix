import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/models/channel.dart';
import '../../state/nix_state.dart';

class MessageHeader extends StatelessWidget {
  final Channel channel;

  const MessageHeader({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: NixColors.surfaceSidebar,
        border: Border(bottom: BorderSide(color: NixColors.surfaceBorder, width: 1)),
      ),
      child: Row(
        children: [
          Icon(channel.icon, color: channel.iconColor, size: 20),
          const SizedBox(width: 8),
          Text(
            channel.name,
            style: const TextStyle(
              color: NixColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          if (channel.topic.isNotEmpty) ...[
            const SizedBox(width: 12),
            Container(width: 1, height: 16, color: NixColors.surfaceBorder),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                channel.topic,
                style: const TextStyle(color: NixColors.textMuted, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else ...[
            const Spacer(),
          ],
          // Badges de Criptografia & Rota
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: NixColors.accentGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: NixColors.accentGreen.withOpacity(0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock, size: 11, color: NixColors.accentGreen),
                SizedBox(width: 4),
                Text(
                  'E2EE DOUBLE RATCHET',
                  style: TextStyle(color: NixColors.accentGreen, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Botão Alternar Painel de Membros
          IconButton(
            icon: Icon(
              Icons.people_alt_rounded,
              size: 20,
              color: nixState.isMembersPanelOpen ? NixColors.accentGreen : NixColors.textSecondary,
            ),
            tooltip: 'Lista de Membros e Chaves',
            onPressed: () => nixState.toggleMembersPanel(),
          ),
        ],
      ),
    );
  }
}
