import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/channel.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../calls/active_call_bar.dart';
import '../dialogs/create_channel_dialog.dart';

class ChannelsSidebar extends StatelessWidget {
  const ChannelsSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final space = nixState.currentSpace;

    final Map<String, List<Channel>> categorized = {};
    for (final ch in space.channels) {
      if (!categorized.containsKey(ch.category)) {
        categorized[ch.category] = [];
      }
      categorized[ch.category]!.add(ch);
    }

    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: NixColors.surfaceSidebar,
        border: Border(
          right: BorderSide(color: NixColors.surfaceBorder, width: 1),
        ),
      ),
      child: Column(
        children: [
          _SpaceHeader(spaceName: space.name, initials: space.initials),
          const Divider(height: 1, color: NixColors.surfaceBorder),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: categorized.entries.map((entry) {
                return _CategoryGroup(
                  categoryName: entry.key,
                  channels: entry.value,
                  currentChannelId: nixState.currentChannel.id,
                  onSelectChannel: (ch) {
                    nixState.selectChannel(ch);
                    if (ch.type == ChannelType.voice) {
                      nixState.joinCall(ch);
                    }
                  },
                  onAddChannel: () {
                    showDialog(
                      context: context,
                      builder: (_) => CreateChannelDialog(defaultCategory: entry.key),
                    );
                  },
                );
              }).toList(),
            ),
          ),
          if (nixState.callState.isConnected) const ActiveCallBar(),
          const _UserProfileBar(),
        ],
      ),
    );
  }
}

class _SpaceHeader extends StatelessWidget {
  final String spaceName;
  final String initials;

  const _SpaceHeader({required this.spaceName, required this.initials});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: NixColors.surfaceCard,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: NixColors.surfaceBorderStrong),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spaceName,
                  style: const TextStyle(
                    color: NixColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 10, color: NixColors.textSecondary),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Tor Onion · E2EE',
                        style: TextStyle(color: NixColors.textMuted, fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 20, color: NixColors.textSecondary),
            tooltip: 'Adicionar Sala / Tópico',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const CreateChannelDialog(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CategoryGroup extends StatelessWidget {
  final String categoryName;
  final List<Channel> channels;
  final String currentChannelId;
  final Function(Channel) onSelectChannel;
  final VoidCallback onAddChannel;

  const _CategoryGroup({
    required this.categoryName,
    required this.channels,
    required this.currentChannelId,
    required this.onSelectChannel,
    required this.onAddChannel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    categoryName,
                    style: NixTokens.labelUppercase(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: onAddChannel,
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.add, size: 14, color: NixColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          ...channels.map((ch) {
            final isSelected = ch.id == currentChannelId;
            return _ChannelItem(
              channel: ch,
              isSelected: isSelected,
              onTap: () => onSelectChannel(ch),
            );
          }),
        ],
      ),
    );
  }
}

class _ChannelItem extends StatelessWidget {
  final Channel channel;
  final bool isSelected;
  final VoidCallback onTap;

  const _ChannelItem({
    required this.channel,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
      decoration: BoxDecoration(
        color: isSelected ? NixColors.surfaceActive : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: isSelected ? Border.all(color: NixColors.surfaceBorderStrong, width: 1) : null,
      ),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2, horizontal: -4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        onTap: onTap,
        leading: Icon(
          channel.icon,
          size: 17,
          color: isSelected ? Colors.white : NixColors.iconMuted,
        ),
        title: Text(
          channel.name,
          style: TextStyle(
            color: isSelected ? Colors.white : NixColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: channel.unreadCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${channel.unreadCount}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _UserProfileBar extends StatelessWidget {
  const _UserProfileBar();

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final profile = nixState.userProfile;

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: NixColors.surfaceDock,
        border: Border(top: BorderSide(color: NixColors.surfaceBorder, width: 1)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => nixState.openProfileOverlay(),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: NixColors.surfaceCard,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white38, width: 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/images/nix_logo_128.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.person_outline, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => nixState.openProfileOverlay(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.displayName,
                    style: const TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    profile.publicId.replaceFirst('NIX-', ''),
                    style: const TextStyle(
                      color: NixColors.textMuted,
                      fontSize: 9.5,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              nixState.callState.isMuted ? Icons.mic_off_outlined : Icons.mic_none_rounded,
              size: 17,
              color: nixState.callState.isMuted ? Colors.white : NixColors.textSecondary,
            ),
            tooltip: nixState.callState.isMuted ? 'Desmutar Microfone' : 'Mutar Microfone',
            onPressed: () => nixState.toggleMute(),
          ),
          IconButton(
            icon: const Icon(
              Icons.settings_outlined,
              size: 17,
              color: NixColors.textSecondary,
            ),
            tooltip: 'Abrir Central de Configurações',
            onPressed: () => nixState.openProfileOverlay(startInSettings: true),
          ),
        ],
      ),
    );
  }
}
