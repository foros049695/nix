import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/models/channel.dart';
import '../../state/nix_state.dart';
import '../dialogs/create_channel_dialog.dart';
import '../calls/active_call_bar.dart';

class ChannelsSidebar extends StatelessWidget {
  const ChannelsSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final space = nixState.currentSpace;

    // Agrupar canais por categoria
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
          // Cabeçalho do Espaço
          _SpaceHeader(spaceName: space.name, emoji: space.iconEmoji),
          const Divider(height: 1, color: NixColors.surfaceBorder),

          // Lista de Categorias e Canais
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
                      builder: (ctx) => CreateChannelDialog(defaultCategory: entry.key),
                    );
                  },
                );
              }).toList(),
            ),
          ),

          // Barra Persistente de Call Ativa (se conectado)
          if (nixState.callState.isConnected)
            const ActiveCallBar(),

          // Painel Inferior de Identidade do Usuário
          const _UserProfileBar(),
        ],
      ),
    );
  }
}

class _SpaceHeader extends StatelessWidget {
  final String spaceName;
  final String? emoji;

  const _SpaceHeader({required this.spaceName, this.emoji});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          if (emoji != null) ...[
            Text(emoji!, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spaceName,
                  style: const TextStyle(
                    color: NixColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const Row(
                  children: [
                    Icon(Icons.lock_rounded, size: 10, color: NixColors.accentGreen),
                    SizedBox(width: 4),
                    Text(
                      'Tor Onion · E2EE',
                      style: TextStyle(color: NixColors.textMuted, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
            tooltip: 'Adicionar Sala / Tópico',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => const CreateChannelDialog(),
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
          // Título da Categoria com botão '+'
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    categoryName,
                    style: const TextStyle(
                      color: NixColors.textDim,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
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
          // Itens dos Canais
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
        color: isSelected ? NixColors.surfaceCardHover : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: isSelected
            ? Border.all(color: NixColors.surfaceBorder, width: 1)
            : null,
      ),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2, horizontal: -4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        onTap: onTap,
        leading: Icon(
          channel.icon,
          size: 18,
          color: isSelected ? Colors.white : channel.iconColor,
        ),
        title: Text(
          channel.name,
          style: TextStyle(
            color: isSelected ? Colors.white : NixColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: channel.unreadCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: NixColors.accentGreen,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${channel.unreadCount}',
                  style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
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
    final sec = nixState.securityContext;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: NixColors.surfaceDock,
        border: Border(top: BorderSide(color: NixColors.surfaceBorder, width: 1)),
      ),
      child: Row(
        children: [
          // Avatar / Identicon determinístico
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: NixColors.surfaceCard,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: NixColors.accentGreen, width: 1.5),
            ),
            child: const Center(
              child: Icon(Icons.person_rounded, size: 18, color: NixColors.accentGreen),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sec.myPersona,
                  style: const TextStyle(
                    color: NixColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  sec.myFingerprint,
                  style: const TextStyle(
                    color: NixColors.textMuted,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Botão Mudo
          IconButton(
            icon: Icon(
              nixState.callState.isMuted ? Icons.mic_off : Icons.mic,
              size: 18,
              color: nixState.callState.isMuted ? NixColors.accentDanger : NixColors.textSecondary,
            ),
            tooltip: nixState.callState.isMuted ? 'Desmutar Microfone' : 'Mutar Microfone',
            onPressed: () => nixState.toggleMute(),
          ),
          // Botão Ensordecer
          IconButton(
            icon: Icon(
              nixState.callState.isDeafened ? Icons.headset_off : Icons.headset,
              size: 18,
              color: nixState.callState.isDeafened ? NixColors.accentDanger : NixColors.textSecondary,
            ),
            tooltip: nixState.callState.isDeafened ? 'Ativar Áudio' : 'Desativar Áudio',
            onPressed: () => nixState.toggleDeafen(),
          ),
        ],
      ),
    );
  }
}
