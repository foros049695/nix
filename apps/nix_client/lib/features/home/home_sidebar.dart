import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/models/direct_message.dart';
import '../../core/models/member.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../navigation/interface_wallpaper_layer.dart';
import '../offline/share_app_offline_dialog.dart';
import '../profile/nix_user_avatar.dart';

/// Área 2 — Lista de Conversas Compacta (Mensagens Salvas, Privadas, Fixadas, Pesquisa e Módulos Externos).
class HomeSidebar extends StatelessWidget {
  final double? width;

  const HomeSidebar({super.key, this.width});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final activeTab = nixState.homeSubTab;
    final selectedDm = nixState.selectedDm;
    final filteredDms = nixState.filteredDirectMessages;
    final effectiveWidth = width ?? nixState.sidebarWidth;
    final wallpaperVisible = InterfaceWallpaperLayer.visibleOf(context);

    return Container(
      width: effectiveWidth,
      child: Column(
        children: [
          // Topo: Busca + Filtros compactos estilo Telegram
          Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Column(
              children: [
                TextField(
                  key: const Key('conversation_search_input'),
                  onChanged: (v) => nixState.setConversationSearchQuery(v),
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: 'Pesquisar conversas, amigos ou IDs...',
                    hintStyle: TextStyle(color: NixColors.textMuted, fontSize: 11.5),
                    prefixIcon: Icon(Icons.search_rounded, size: 16, color: NixColors.textMuted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    fillColor: wallpaperVisible ? NixColors.background.withValues(alpha: 0.45) : NixColors.background,
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
                  child: Row(
                    children: [
                      _filterChip(context, nixState, ConversationFilter.all, 'Todas'),
                      const SizedBox(width: 4),
                      _filterChip(context, nixState, ConversationFilter.unread, 'Não lidas'),
                      const SizedBox(width: 4),
                      _filterChip(context, nixState, ConversationFilter.pinned, 'Fixadas'),
                      const SizedBox(width: 4),
                      _filterChip(context, nixState, ConversationFilter.muted, 'Silenciadas'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Navegação principal + Lista de conversas (com Mensagens Salvas no topo)
          Expanded(
            child: ListView(
              key: const Key('home_sidebar_navigation'),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              children: [
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'CONVERSAS & MENSAGENS SALVAS',
                          style: NixTokens.labelUppercase(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        key: const Key('add_contact_sidebar_button'),
                        icon: Icon(Icons.person_add_alt_1_rounded, size: 16, color: NixColors.accentYellow),
                        tooltip: 'Adicionar Contato por ID',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _showAddContactDialog(context, nixState),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

                for (final dm in filteredDms.where((dm) => dm.isSavedMessages))
                  _DirectChatItemTile(
                    dm: dm,
                    isSelected: nixState.activeArea == NixActiveArea.homePrivate &&
                        activeTab == HomeSubTab.directChat && selectedDm?.id == dm.id,
                    onTap: () => nixState.selectDirectMessage(dm),
                  ),
                _navTile(
                  context,
                  icon: Icons.badge_outlined,
                  label: 'Pager (Identidade)',
                  isSelected: nixState.activeArea == NixActiveArea.homePrivate &&
                      activeTab == HomeSubTab.cardId,
                  onTap: () => nixState.selectHomeSubTab(HomeSubTab.cardId),
                ),
                _navTile(
                  context,
                  icon: Icons.people_outline_rounded,
                  label: 'Amigos',
                  isSelected: nixState.activeArea == NixActiveArea.homePrivate &&
                      activeTab == HomeSubTab.friends,
                  onTap: () => nixState.selectHomeSubTab(HomeSubTab.friends),
                ),
                _navTile(
                  context,
                  icon: Icons.mark_email_unread_outlined,
                  label: 'Solicitações',
                  badgeCount: nixState.contactRequests.length,
                  isSelected: nixState.activeArea == NixActiveArea.homePrivate &&
                      activeTab == HomeSubTab.requests,
                  onTap: () => nixState.selectHomeSubTab(HomeSubTab.requests),
                ),
                _navTile(
                  context,
                  key: const Key('home_nav_monero'),
                  icon: Icons.currency_exchange_rounded,
                  label: 'Mercado Cripto',
                  isSelected: nixState.activeArea == NixActiveArea.moneroP2p,
                  onTap: () => nixState.openMoneroP2pArea(),
                ),
                _navTile(
                  context,
                  key: const Key('home_nav_github'),
                  icon: Icons.code_rounded,
                  label: 'GitHub Discovery',
                  isSelected: nixState.activeArea == NixActiveArea.github,
                  onTap: () => nixState.openGithubDiscoveryArea(),
                ),
                _navTile(
                  context,
                  key: const Key('home_nav_media_index'),
                  icon: Icons.local_library_rounded,
                  label: 'Nix Media Index',
                  isSelected: nixState.activeArea == NixActiveArea.mediaIndex,
                  onTap: () => nixState.openMediaIndexArea(),
                ),
                _navTile(
                  context,
                  key: const Key('home_nav_archive'),
                  icon: Icons.auto_stories_rounded,
                  label: 'Nix Archive',
                  isSelected: nixState.activeArea == NixActiveArea.archive,
                  onTap: () => nixState.openArchiveArea(),
                ),
                _navTile(
                  context,
                  icon: Icons.bolt_outlined,
                  label: 'Atualizações',
                  isSelected: nixState.activeArea == NixActiveArea.homePrivate &&
                      activeTab == HomeSubTab.updates,
                  onTap: () => nixState.selectHomeSubTab(HomeSubTab.updates),
                ),
                _navTile(
                  context,
                  key: const Key('home_nav_share_offline'),
                  icon: Icons.wifi_tethering_rounded,
                  label: 'Compartilhar Offline',
                  isSelected: false,
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => const ShareAppOfflineDialog(),
                    );
                  },
                ),

                if (filteredDms.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'Nenhuma conversa corresponde ao filtro atual.',
                      style: TextStyle(color: NixColors.textMuted, fontSize: 11.5),
                    ),
                  )
                else
                  ...filteredDms.where((dm) => !dm.isSavedMessages).map((dm) {
                    final isSelected = nixState.activeArea == NixActiveArea.homePrivate &&
                        activeTab == HomeSubTab.directChat &&
                        selectedDm?.id == dm.id;
                    return _DirectChatItemTile(
                      dm: dm,
                      isSelected: isSelected,
                      onTap: () => nixState.selectDirectMessage(dm),
                    );
                  }),
              ],
            ),
          ),

          // Rodapé do Usuário
          _buildUserFooter(context, nixState),
        ],
      ),
    );
  }

  Widget _filterChip(
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

  Widget _navTile(
    BuildContext context, {
    Key? key,
    required IconData icon,
    required String label,
    required bool isSelected,
    int badgeCount = 0,
    required VoidCallback onTap,
  }) {
    final accent = context.accentColor;
    final accentText = context.accentTextColor;
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isSelected ? accent.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: NixTokens.borderSm,
        border: isSelected
            ? Border.all(color: accent.withValues(alpha: 0.5), width: 1.0)
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -3),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          onTap: onTap,
          leading: Icon(
            icon,
            size: 17,
            color: isSelected ? accentText : NixColors.iconSecondary,
          ),
          title: Text(
            label,
            style: TextStyle(
              color: isSelected ? NixColors.textPrimary : NixColors.textSecondary,
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          trailing: badgeCount > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: TextStyle(
                      color: context.onAccentColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildUserFooter(BuildContext context, NixState state) {
    final profile = state.userProfile;
    final effectiveName = profile.effectiveDisplayName;
    final wallpaperVisible = InterfaceWallpaperLayer.visibleOf(context);

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: wallpaperVisible ? Colors.transparent : NixColors.surfaceDock,
        border: Border(top: BorderSide(color: NixColors.surfaceBorder)),
      ),
      child: Row(
        children: [
          NixUserAvatar(
            size: 32,
            showBorder: true,
            onTap: () => state.openProfileOverlay(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => state.openProfileOverlay(),
              borderRadius: BorderRadius.circular(4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    effectiveName,
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    profile.publicId.length > 18
                        ? '${profile.publicId.substring(0, 18)}...'
                        : profile.publicId,
                    style: NixTokens.monoCode(size: 9.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          ListenableBuilder(
            listenable: state.calls,
            builder: (context, _) {
              final muted = state.calls.isMuted;
              return IconButton(
                icon: Icon(muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                  size: 18, color: muted ? NixColors.accentDanger : NixColors.textSecondary),
                tooltip: muted ? 'Desmutar microfone' : 'Mutar microfone',
                onPressed: state.toggleMute,
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined, size: 16, color: NixColors.textSecondary),
            tooltip: 'Configurações',
            onPressed: () => state.openProfileOverlay(startInSettings: true),
          ),
        ],
      ),
    );
  }

  void _showAddContactDialog(BuildContext context, NixState state) {
    showDialog<void>(
      context: context,
      builder: (_) => _ContactInvitationDialog(state: state),
    );
  }

}

class _ContactInvitationDialog extends StatefulWidget {
  final NixState state;

  const _ContactInvitationDialog({required this.state});

  @override
  State<_ContactInvitationDialog> createState() => _ContactInvitationDialogState();
}

class _ContactInvitationDialogState extends State<_ContactInvitationDialog> {
  final _invitation = TextEditingController();
  final _alias = TextEditingController();
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    _invitation.dispose();
    _alias.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() { _busy = true; _status = null; });
    try {
      await action();
    } on FormatException catch (error) {
      if (mounted) setState(() => _status = error.message);
    } on StateError catch (error) {
      if (mounted) setState(() => _status = error.message);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _status = error.message ?? 'Falha ao acessar a câmera.');
    } catch (_) {
      if (mounted) setState(() => _status = 'Falha ao processar o convite.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanInvitation() async {
    final raw = await const MethodChannel('com.projetonix.nix/invitation_qr')
        .invokeMethod<String>('scan');
    if (!mounted || raw == null) return;
    final text = raw.trim();
    if (text.length > 8192 || !text.startsWith('{')) {
      throw const FormatException('O QR precisa conter um convite assinado do Nix.');
    }
    _invitation.text = text;
    setState(() => _status = 'Confira o convite e confirme a importação.');
  }

  Future<void> _showInvitationQr() async {
    final invitation = await widget.state.exportContactInvitation();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Meu convite'),
        content: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 270),
            child: QrImageView(
              data: invitation,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Adicionar Contato Soberano'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Troque convites por um canal confiável. Cada pessoa deve '
            'importar o convite da outra antes de sincronizar pelo relay.'),
        TextButton.icon(
          onPressed: _busy ? null : () => _run(() async {
            final invitation = await widget.state.exportContactInvitation();
            if (!mounted) return;
            await Clipboard.setData(ClipboardData(text: invitation));
            if (mounted) setState(() => _status = 'Convite assinado copiado.');
          }),
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copiar meu convite'),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _busy ? null : () => _run(_showInvitationQr),
              icon: const Icon(Icons.qr_code_rounded),
              label: const Text('Mostrar meu QR'),
            ),
            if (defaultTargetPlatform == TargetPlatform.android)
              TextButton.icon(
                onPressed: _busy ? null : () => _run(_scanInvitation),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Ler QR pela câmera'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('add_contact_id_field'),
          controller: _invitation,
          minLines: 2,
          maxLines: 4,
          maxLength: 8192,
          decoration: const InputDecoration(
            labelText: 'Convite assinado',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('add_contact_name_field'),
          controller: _alias,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Apelido local (opcional)',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_status!),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('add_contact_confirm_button'),
        onPressed: _busy ? null : () => _run(() async {
          await widget.state.addNewContact(
            publicId: _invitation.text,
            nickname: _alias.text,
          );
          if (context.mounted) Navigator.of(context).pop();
        }),
        child: const Text('Importar e abrir conversa'),
      ),
    ],
  );
}

class _DirectChatItemTile extends StatelessWidget {
  final DirectMessageThread dm;
  final bool isSelected;
  final VoidCallback onTap;

  const _DirectChatItemTile({
    required this.dm,
    required this.isSelected,
    required this.onTap,
  });

  Color _getTrustColor(NixTrustLevel level) {
    switch (level) {
      case NixTrustLevel.level1Red:
        return NixColors.trustLevel1Red;
      case NixTrustLevel.level2Yellow:
        return NixColors.trustLevel2Yellow;
      case NixTrustLevel.level3Green:
        return NixColors.trustLevel3Green;
    }
  }

  void _showContextMenu(BuildContext context, NixState state, Offset pos) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        PopupMenuItem(
          value: 'pin',
          child: Text(dm.isPinned ? 'Desafixar conversa' : 'Fixar conversa no topo'),
        ),
        PopupMenuItem(
          value: 'mute',
          child: Text(dm.isMuted ? 'Ativar notificações' : 'Silenciar conversa'),
        ),
        ...state.folders.map((f) => PopupMenuItem(
              value: 'folder:${f.id}',
              child: Text('Mover para pasta "${f.name}"'),
            )),
      ],
    );
    if (selected == null) return;
    if (selected == 'pin') state.togglePinDirectMessage(dm.id);
    if (selected == 'mute') state.toggleMuteDirectMessage(dm.id);
    if (selected.startsWith('folder:')) {
      state.assignItemToFolder(dm.id, selected.substring(7));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<NixState>();
    final accent = context.accentColor;
    final lastTime = dm.lastActivityAt;
    final timeStr = lastTime != null
        ? '${lastTime.hour.toString().padLeft(2, '0')}:${lastTime.minute.toString().padLeft(2, '0')}'
        : '';

    final tile = GestureDetector(
      key: Key('dm_item_${dm.id}'),
      onSecondaryTapDown: (d) => _showContextMenu(context, state, d.globalPosition),
      onLongPressStart: (d) => _showContextMenu(context, state, d.globalPosition),
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: NixTokens.borderSm,
          border: isSelected ? Border.all(color: accent.withValues(alpha: 0.5)) : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            onTap: onTap,
            leading: dm.isSavedMessages
                ? Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.bookmark_rounded, size: 20, color: context.onAccentColor),
                  )
                : Stack(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: NixColors.surfaceCard,
                          shape: BoxShape.circle,
                          border: Border.all(color: NixColors.surfaceBorderStrong),
                        ),
                        child: Center(
                          child: Text(
                            dm.peerName.isNotEmpty ? dm.peerName[0].toUpperCase() : '?',
                            style: TextStyle(
                              color: NixColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _getTrustColor(dm.trustLevel),
                            shape: BoxShape.circle,
                            border: Border.all(color: NixColors.surfaceSidebar, width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    dm.peerName,
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 13,
                      fontWeight: isSelected || dm.isSavedMessages ? FontWeight.w700 : FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (dm.isMuted)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.volume_off_rounded, size: 12, color: NixColors.textMuted),
                  ),
                if (timeStr.isNotEmpty)
                  Text(
                    timeStr,
                    style: TextStyle(color: NixColors.textMuted, fontSize: 10),
                  ),
              ],
            ),
            subtitle: Row(
              children: [
                Expanded(
                  child: Text(
                    dm.lastMessagePreview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: NixColors.textSecondary, fontSize: 11),
                  ),
                ),
                if (dm.isPinned && dm.unreadCount == 0)
                  Icon(Icons.push_pin_rounded, size: 12, color: NixColors.textMuted),
                if (dm.unreadCount > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: dm.isMuted ? NixColors.surfaceElevatedHigh : accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${dm.unreadCount}',
                      style: TextStyle(
                        color: dm.isMuted ? NixColors.textSecondary : context.onAccentColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (dm.isSavedMessages) return tile;

    return Draggable<String>(
      data: dm.id,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: NixTokens.borderSm,
          ),
          child: Text(
            dm.peerName,
            style: TextStyle(color: context.onAccentColor, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
      ),
      child: tile,
    );
  }
}
