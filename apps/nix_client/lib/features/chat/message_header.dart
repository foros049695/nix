import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/channel.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import '../dialogs/channel_settings_dialog.dart';

class MessageHeader extends StatelessWidget {
  final Channel channel;

  const MessageHeader({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final accent = context.accentColor;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: NixColors.surfaceSidebar,
        border: Border(bottom: BorderSide(color: NixColors.surfaceBorder, width: 1)),
      ),
      child: Row(
        children: [
          Icon(channel.icon, color: accent, size: 20),
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
          // Badges de Criptografia & Rota (Living AMOLED dinâmico)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock, size: 11, color: accent),
                const SizedBox(width: 4),
                Text(
                  'E2EE DOUBLE RATCHET',
                  style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Botão Configurações Avançadas do Canal / Grupo
          IconButton(
            icon: const Icon(
              Icons.tune_rounded,
              size: 19,
              color: NixColors.textSecondary,
            ),
            tooltip: 'Configurações do Canal & Permissões',
            onPressed: () => ChannelSettingsDialog.show(context, channel),
          ),
          const SizedBox(width: 2),
          // Botão Alternar Painel de Membros
          IconButton(
            icon: Icon(
              Icons.people_alt_rounded,
              size: 20,
              color: nixState.isMembersPanelOpen ? accent : NixColors.textSecondary,
            ),
            tooltip: 'Lista de Membros e Chaves',
            onPressed: () => nixState.toggleMembersPanel(),
          ),
        ],
      ),
    );
  }
}
