import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/channel.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../calls/active_call_bar.dart';
import '../dialogs/create_channel_dialog.dart';
import '../profile/nix_user_avatar.dart';

/// Área 2 (Conversas / Grupos / Canais estilo Telegram Desktop).
class ChannelsSidebar extends StatelessWidget {
  final double? width;

  const ChannelsSidebar({super.key, this.width});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final space = nixState.currentSpace;
    final visibleSpaces = nixState.visibleSpacesForFolder;
    final query = nixState.conversationSearchQuery.trim().toLowerCase();
    final effectiveWidth = width ?? nixState.sidebarWidth;

    final Map<String, List<Channel>> categorized = {};
    for (final ch in space.channels) {
      if (query.isNotEmpty && !ch.name.toLowerCase().contains(query)) continue;
      if (nixState.conversationFilter == ConversationFilter.unread && ch.unreadCount == 0) {
        continue;
      }
      if (nixState.conversationFilter == ConversationFilter.pinned && !ch.isPinned) {
        continue;
      }
      if (nixState.conversationFilter == ConversationFilter.muted && !ch.isMuted) {
        continue;
      }
      if (nixState.conversationFilter == ConversationFilter.channels &&
          ch.type != ChannelType.announcement &&
          ch.type != ChannelType.publication) {
        continue;
      }
      categorized.putIfAbsent(ch.category, () => []).add(ch);
    }

    return Container(
      width: effectiveWidth,
      decoration: BoxDecoration(
        color: NixColors.surfaceSidebar,
        border: Border(
          right: BorderSide(color: NixColors.surfaceBorder, width: 1),
        ),
      ),
      child: Column(
        children: [
          _SpaceHeader(spaceName: space.name, initials: space.initials),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Column(
              children: [
                TextField(
                  onChanged: (v) => nixState.setConversationSearchQuery(v),
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: 'Pesquisar grupos, canais e chats...',
                    hintStyle: TextStyle(color: NixColors.textMuted, fontSize: 11.5),
                    prefixIcon: Icon(Icons.search_rounded, size: 16, color: NixColors.textMuted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    fillColor: NixColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: NixColors.surfaceBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: NixColors.surfaceBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _chip(context, nixState, ConversationFilter.all, 'Todos'),
                      const SizedBox(width: 4),
                      _chip(context, nixState, ConversationFilter.unread, 'Não lidos'),
                      const SizedBox(width: 4),
                      _chip(context, nixState, ConversationFilter.pinned, 'Fixados'),
                      const SizedBox(width: 4),
                      _chip(context, nixState, ConversationFilter.channels, 'Canais'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Seletor rápido de espaços da pasta ativa + atalho para Mensagens Salvas
          if (visibleSpaces.length > 1)
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                children: visibleSpaces.map((sp) {
                  final active = sp.id == space.id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () => nixState.selectSpace(sp),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: active ? context.accentColor.withValues(alpha: 0.2) : NixColors.surfaceCard,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: active ? context.accentColor : NixColors.surfaceBorder,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            sp.name,
                            style: TextStyle(
                              color: active ? context.accentTextColor : NixColors.textSecondary,
                              fontSize: 11,
                              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

          Divider(height: 1, color: NixColors.surfaceBorder),

          // Atalho rápido para Mensagens Salvas & Ferramentas Principais
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
            child: InkWell(
              key: const Key('channels_sidebar_saved_messages'),
              onTap: () => nixState.openSavedMessages(),
              borderRadius: NixTokens.borderSm,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: NixColors.surfaceCard,
                  borderRadius: NixTokens.borderSm,
                  border: Border.all(color: NixColors.surfaceBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: context.accentColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.bookmark_rounded, size: 14, color: context.onAccentColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Mensagens Salvas',
                        style: TextStyle(
                          color: NixColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${nixState.savedMessagesThread.messages.length}',
                      style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
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

  Widget _chip(
    BuildContext context,
    NixState state,
    ConversationFilter filter,
    String label,
  ) {
    final active = state.conversationFilter == filter;
    final accent = context.accentColor;
    return InkWell(
      onTap: () => state.setConversationFilter(filter),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: active ? accent : NixColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? accent : NixColors.surfaceBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? context.onAccentColor : NixColors.textSecondary,
            fontSize: 10.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
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
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: context.accentColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: context.onAccentColor,
                  fontSize: 10.5,
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
                  style: TextStyle(
                    color: NixColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 10, color: NixColors.textSecondary),
                    const SizedBox(width: 4),
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
            icon: Icon(Icons.add_rounded, size: 20, color: NixColors.textSecondary),
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
      padding: const EdgeInsets.only(bottom: 10),
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
                  child: Padding(
                    padding: const EdgeInsets.all(2),
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

  void _showMenu(BuildContext context, NixState state, Offset pos) async {
    final sel = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        PopupMenuItem(
          value: 'pin',
          child: Text(channel.isPinned ? 'Desafixar canal' : 'Fixar canal'),
        ),
        PopupMenuItem(
          value: 'mute',
          child: Text(channel.isMuted ? 'Ativar som' : 'Silenciar canal'),
        ),
        ...state.folders.map((f) => PopupMenuItem(
              value: 'folder:${f.id}',
              child: Text('Mover espaço para "${f.name}"'),
            )),
      ],
    );
    if (sel == null) return;
    if (sel == 'pin') state.togglePinChannel(channel.id);
    if (sel == 'mute') state.toggleMuteChannel(channel.id);
    if (sel.startsWith('folder:')) {
      state.addSpaceToFolder(channel.spaceId, sel.substring(7));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<NixState>();
    final accent = context.accentColor;
    final accentText = context.accentTextColor;

    final child = GestureDetector(
      onSecondaryTapDown: (d) => _showMenu(context, state, d.globalPosition),
      onLongPressStart: (d) => _showMenu(context, state, d.globalPosition),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: accent.withValues(alpha: 0.45), width: 1)
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -2, horizontal: -4),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            onTap: onTap,
            leading: Icon(
              channel.icon,
              size: 17,
              color: isSelected ? accentText : NixColors.iconMuted,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    channel.name,
                    style: TextStyle(
                      color: isSelected ? NixColors.textPrimary : NixColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (channel.isMuted)
                  Icon(Icons.volume_off_rounded, size: 12, color: NixColors.textMuted),
                if (channel.isPinned)
                  Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: Icon(Icons.push_pin_rounded, size: 12, color: NixColors.textMuted),
                  ),
              ],
            ),
            trailing: channel.unreadCount > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: channel.isMuted ? NixColors.surfaceElevatedHigh : accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${channel.unreadCount}',
                      style: TextStyle(
                        color: channel.isMuted ? NixColors.textSecondary : context.onAccentColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );

    return Draggable<String>(
      data: channel.spaceId,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: accent, borderRadius: NixTokens.borderSm),
          child: Text(
            '# ${channel.name}',
            style: TextStyle(color: context.onAccentColor, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
      ),
      child: child,
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
      decoration: BoxDecoration(
        color: NixColors.surfaceDock,
        border: Border(top: BorderSide(color: NixColors.surfaceBorder, width: 1)),
      ),
      child: Row(
        children: [
          NixUserAvatar(
            size: 32,
            showBorder: true,
            onTap: () => nixState.openProfileOverlay(),
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
                    profile.effectiveDisplayName,
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    profile.publicId.replaceFirst('NIX-', ''),
                    style: TextStyle(
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
              color: nixState.callState.isMuted ? NixColors.accentDanger : NixColors.textSecondary,
            ),
            tooltip: nixState.callState.isMuted ? 'Desmutar Microfone' : 'Mutar Microfone',
            onPressed: () => nixState.toggleMute(),
          ),
          IconButton(
            icon: Icon(
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
