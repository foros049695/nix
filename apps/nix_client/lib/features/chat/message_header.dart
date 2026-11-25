import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/channel.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import '../dialogs/channel_settings_dialog.dart';
import '../design/nix_surfaces.dart';
import '../navigation/workspace_image.dart';
import '../members/members_panel.dart';
import 'conversation_info_panel.dart';

class MessageHeader extends StatelessWidget {
  final Channel channel;

  const MessageHeader({super.key, required this.channel});

  Widget _buildInitialAvatar(String name, Color accent, Color accentText) {
    final clean = name.trim();
    final words = clean
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final initials = words.isEmpty
        ? 'NX'
        : (words.length == 1
            ? (words[0].length >= 2 ? words[0].substring(0, 2).toUpperCase() : words[0].toUpperCase())
            : '${words[0][0]}${words[1][0]}'.toUpperCase());

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.28),
            accent.withValues(alpha: 0.12),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.2),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: accentText,
          fontWeight: FontWeight.bold,
          fontSize: 12.5,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final currentSpace = nixState.currentSpace;
    final accent = context.accentColor;
    final accentText = context.accentTextColor;
    final isAnnouncement = channel.type == ChannelType.announcement;

    // Nome real do canal (com fallback gracioso para espaços legados que vieram com comunicados)
    String displayName = channel.name;
    if (isAnnouncement && (displayName == 'comunicados' || displayName == 'geral') && currentSpace.name.isNotEmpty) {
      displayName = currentSpace.name;
    }

    // Descrição real do canal
    String? displaySubtitle = channel.topic.isNotEmpty ? channel.topic : null;
    if (isAnnouncement && (displaySubtitle == null || displaySubtitle.isEmpty || displaySubtitle == 'Canal oficial de transmissão e comunicados.')) {
      if (currentSpace.description.isNotEmpty) {
        displaySubtitle = currentSpace.description;
      }
    }

    // Avatar do canal (imagem circular ou iniciais no lugar de ícones genéricos de megafone)
    final imagePath = channel.customImagePath ?? currentSpace.customImagePath;
    final Widget leadingAvatar;
    if (imagePath != null && imagePath.isNotEmpty) {
      leadingAvatar = ClipOval(
        child: SizedBox(
          width: 36,
          height: 36,
          child: WorkspaceImage(
            path: imagePath,
            size: 36,
            fallback: _buildInitialAvatar(displayName, accent, accentText),
          ),
        ),
      );
    } else {
      leadingAvatar = _buildInitialAvatar(displayName, accent, accentText);
    }

    void openInfo() => ConversationInfoPanel.open(context, channel: channel);

    void openMembers() {
      if (MediaQuery.sizeOf(context).width < nixDesktopBreakpoint) {
        MembersPanel.show(context);
      } else {
        nixState.toggleMembersPanel();
      }
    }

    return InkWell(
      key: const Key('message_header_bar'),
      onTap: openInfo,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: NixColors.surfaceSidebar,
          border: Border(bottom: BorderSide(color: NixColors.surfaceBorder, width: 1)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            return Row(
              children: [
                Expanded(
                  child: NixPanelTitle(
                    icon: channel.icon,
                    leading: leadingAvatar,
                    title: displayName,
                    subtitle: compact || (displaySubtitle == null || displaySubtitle.isEmpty) ? null : displaySubtitle,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
                        compact ? 'E2EE' : 'E2EE DOUBLE RATCHET',
                        style: TextStyle(color: accentText, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const Key('channel_info_panel_button'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  icon: Icon(
                    Icons.view_sidebar_outlined,
                    size: 18,
                    color: nixState.isConversationInfoOpen ? accentText : NixColors.textSecondary,
                  ),
                  tooltip: 'Informações & Mídia Compartilhada',
                  onPressed: openInfo,
                ),
                IconButton(
                  key: const Key('channel_settings_button'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  icon: Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: NixColors.textSecondary,
                  ),
                  tooltip: 'Configurações do Canal & Permissões',
                  onPressed: () => ChannelSettingsDialog.show(context, channel),
                ),
                IconButton(
                  key: const Key('channel_members_button'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  icon: Icon(
                    Icons.people_alt_rounded,
                    size: 19,
                    color: nixState.isMembersPanelOpen ? accentText : NixColors.textSecondary,
                  ),
                  tooltip: 'Lista de Membros e Chaves',
                  onPressed: openMembers,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
