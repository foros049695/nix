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
    final accentText = context.accentTextColor;

    return InkWell(
      key: const Key('message_header_bar'),
      onTap: () => nixState.toggleConversationInfoPanel(),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: NixColors.surfaceSidebar,
          border: Border(bottom: BorderSide(color: NixColors.surfaceBorder, width: 1)),
        ),
        child: Row(
          children: [
            Icon(channel.icon, color: accentText, size: 20),
            const SizedBox(width: 8),
            Text(
              channel.name,
              style: TextStyle(
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
                  style: TextStyle(color: NixColors.textMuted, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else ...[
              const Spacer(),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 11, color: accentText),
                  const SizedBox(width: 4),
                  Text(
                    'E2EE DOUBLE RATCHET',
                    style: TextStyle(color: accentText, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              key: const Key('channel_info_panel_button'),
              icon: Icon(
                Icons.view_sidebar_outlined,
                size: 19,
                color: nixState.isConversationInfoOpen ? accentText : NixColors.textSecondary,
              ),
              tooltip: 'Informações & Mídia Compartilhada',
              onPressed: () => nixState.toggleConversationInfoPanel(),
            ),
            IconButton(
              key: const Key('channel_settings_button'),
              icon: Icon(
                Icons.tune_rounded,
                size: 19,
                color: NixColors.textSecondary,
              ),
              tooltip: 'Configurações do Canal & Permissões',
              onPressed: () => ChannelSettingsDialog.show(context, channel),
            ),
            IconButton(
              key: const Key('channel_members_button'),
              icon: Icon(
                Icons.people_alt_rounded,
                size: 20,
                color: nixState.isMembersPanelOpen ? accentText : NixColors.textSecondary,
              ),
              tooltip: 'Lista de Membros e Chaves',
              onPressed: () => nixState.toggleMembersPanel(),
            ),
          ],
        ),
      ),
    );
  }
}
