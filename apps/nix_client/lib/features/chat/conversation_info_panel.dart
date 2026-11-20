import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/channel.dart';
import '../../core/models/direct_message.dart';
import '../../core/models/message.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../design/nix_surfaces.dart';
import '../profile/peer_card_id_dialog.dart';

enum _InfoMediaTab { overview, photos, videos, files, audio, links, pinned }

/// Painel Lateral de Informações da Conversa (Seção 10, inspirado no Telegram Desktop).
/// Indexa mídia, arquivos, áudios, links e mensagens fixadas localmente sem envio externo.
class ConversationInfoPanel extends StatefulWidget {
  final DirectMessageThread? directMessage;
  final Channel? channel;
  final bool fullScreen;

  const ConversationInfoPanel({
    super.key,
    this.directMessage,
    this.channel,
    this.fullScreen = false,
  });

  static void open(BuildContext context, {DirectMessageThread? directMessage, Channel? channel}) {
    if (MediaQuery.sizeOf(context).width >= nixDesktopBreakpoint) {
      context.read<NixState>().toggleConversationInfoPanel();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(
      body: SafeArea(child: ConversationInfoPanel(
        directMessage: directMessage, channel: channel, fullScreen: true,
      )),
    )));
  }

  @override
  State<ConversationInfoPanel> createState() => _ConversationInfoPanelState();
}

class _ConversationInfoPanelState extends State<ConversationInfoPanel> {
  _InfoMediaTab _tab = _InfoMediaTab.overview;
  String _historyQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static final RegExp _urlRegex = RegExp(r'https?://[^\s]+', caseSensitive: false);

  bool _isPhoto(String name) =>
      name.endsWith('.png') ||
      name.endsWith('.jpg') ||
      name.endsWith('.jpeg') ||
      name.endsWith('.webp');

  bool _isVideo(String name) =>
      name.endsWith('.mp4') || name.endsWith('.mkv') || name.endsWith('.webm');

  bool _isAudio(String name) =>
      name.endsWith('.ogg') ||
      name.endsWith('.opus') ||
      name.endsWith('.mp3') ||
      name.endsWith('.wav');

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final original = widget.directMessage;
    final dm = original == null ? null : nixState.directMessages.firstWhere(
      (thread) => thread.id == original.id,
      orElse: () => original,
    );
    final ch = widget.channel;
    final msgs = dm != null ? dm.messages : nixState.currentMessages;
    final accent = context.accentColor;
    final accentText = context.accentTextColor;

    void jumpToMessage(Message message) {
      nixState.highlightMessage(message.id);
      if (widget.fullScreen) Navigator.of(context).pop();
    }

    // Indexação estritamente local
    final photos = <String>[];
    final videos = <String>[];
    final files = <String>[];
    final audios = <String>[];
    final links = <String>[];
    final pinned = <Message>[];

    for (final m in msgs) {
      if (m.isPinned) pinned.add(m);
      for (final att in m.attachments) {
        final lower = att.toLowerCase();
        if (_isPhoto(lower)) {
          photos.add(att);
        } else if (_isVideo(lower)) {
          videos.add(att);
        } else if (_isAudio(lower)) {
          audios.add(att);
        } else {
          files.add(att);
        }
      }
      for (final match in _urlRegex.allMatches(m.text)) {
        final url = match.group(0);
        if (url != null) links.add(url);
      }
    }

    final filteredHistory = _historyQuery.trim().isEmpty
        ? <Message>[]
        : msgs
            .where((m) => m.text.toLowerCase().contains(_historyQuery.trim().toLowerCase()))
            .toList();

    return Container(
      key: const Key('conversation_info_panel'),
      width: widget.fullScreen ? double.infinity : 310,
      decoration: BoxDecoration(
        color: NixColors.surfaceSidebar,
        border: Border(left: BorderSide(color: NixColors.surfaceBorder, width: 1)),
      ),
      child: Column(
        children: [
          // Cabeçalho do Painel
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: NixColors.surfaceElevated,
              border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 17, color: accentText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dm != null
                        ? (dm.isSavedMessages ? 'Mensagens Salvas' : 'Dados da Conversa')
                        : 'Informações do Canal',
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(widget.fullScreen ? Icons.arrow_back_rounded : Icons.close_rounded, size: 18, color: NixColors.textSecondary),
                  tooltip: widget.fullScreen ? 'Voltar à conversa' : 'Fechar Painel',
                  onPressed: widget.fullScreen
                      ? () => Navigator.of(context).pop()
                      : () => nixState.toggleConversationInfoPanel(false),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                // 1. Cartão resumo da conversa / Card ID autorizado
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NixColors.surfaceCard,
                    borderRadius: NixTokens.borderMd,
                    border: Border.all(color: NixColors.surfaceBorderStrong),
                  ),
                  child: dm != null
                      ? _buildDmProfileSummary(context, nixState, dm)
                      : _buildChannelSummary(context, nixState, ch!),
                ),
                const SizedBox(height: 12),

                // 2. Pesquisa local no histórico da conversa
                TextField(
                  key: const Key('info_panel_history_search'),
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _historyQuery = v),
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Pesquisar no histórico local...',
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, size: 16, color: NixColors.textMuted),
                    suffixIcon: _historyQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded, size: 15, color: NixColors.textMuted),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _historyQuery = '');
                            },
                          )
                        : null,
                  ),
                ),

                if (_historyQuery.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'RESULTADOS LOCAIS (${filteredHistory.length})',
                    style: NixTokens.labelUppercase(),
                  ),
                  const SizedBox(height: 6),
                  ...filteredHistory.map((m) => InkWell(
                        onTap: () => jumpToMessage(m),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: NixColors.surfaceElevated,
                            borderRadius: NixTokens.borderSm,
                            border: Border.all(color: NixColors.surfaceBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.senderName,
                                style: TextStyle(
                                  color: accentText,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                m.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: NixColors.textPrimary, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                      )),
                ] else ...[
                  const SizedBox(height: 14),
                  Text('MÍDIA & ARQUIVOS INDEXADOS LOCALMENTE', style: NixTokens.labelUppercase()),
                  const SizedBox(height: 8),

                  // 3. Contadores clicáveis (estilo Telegram Saved Messages / Shared Media)
                  _counterRow(
                    icon: Icons.photo_outlined,
                    label: '${photos.length} fotos',
                    active: _tab == _InfoMediaTab.photos,
                    onTap: () => setState(() =>
                        _tab = _tab == _InfoMediaTab.photos ? _InfoMediaTab.overview : _InfoMediaTab.photos),
                  ),
                  _counterRow(
                    icon: Icons.videocam_outlined,
                    label: '${videos.length} vídeos',
                    active: _tab == _InfoMediaTab.videos,
                    onTap: () => setState(() =>
                        _tab = _tab == _InfoMediaTab.videos ? _InfoMediaTab.overview : _InfoMediaTab.videos),
                  ),
                  _counterRow(
                    icon: Icons.insert_drive_file_outlined,
                    label: '${files.length} arquivos',
                    active: _tab == _InfoMediaTab.files,
                    onTap: () => setState(() =>
                        _tab = _tab == _InfoMediaTab.files ? _InfoMediaTab.overview : _InfoMediaTab.files),
                  ),
                  _counterRow(
                    icon: Icons.headphones_outlined,
                    label: '${audios.length} áudios',
                    active: _tab == _InfoMediaTab.audio,
                    onTap: () => setState(() =>
                        _tab = _tab == _InfoMediaTab.audio ? _InfoMediaTab.overview : _InfoMediaTab.audio),
                  ),
                  _counterRow(
                    icon: Icons.link_rounded,
                    label: '${links.length} links compartilhados',
                    active: _tab == _InfoMediaTab.links,
                    onTap: () => setState(() =>
                        _tab = _tab == _InfoMediaTab.links ? _InfoMediaTab.overview : _InfoMediaTab.links),
                  ),
                  _counterRow(
                    icon: Icons.push_pin_outlined,
                    label: '${pinned.length} mensagens fixadas',
                    active: _tab == _InfoMediaTab.pinned,
                    onTap: () => setState(() =>
                        _tab = _tab == _InfoMediaTab.pinned ? _InfoMediaTab.overview : _InfoMediaTab.pinned),
                  ),

                  const SizedBox(height: 10),

                  // Conteúdo da aba selecionada
                  if (_tab == _InfoMediaTab.photos)
                    _buildSimpleList('FOTOS COMPARTILHADAS', photos, Icons.image_outlined),
                  if (_tab == _InfoMediaTab.videos)
                    _buildSimpleList('VÍDEOS COMPARTILHADOS', videos, Icons.movie_outlined),
                  if (_tab == _InfoMediaTab.files)
                    _buildSimpleList('ARQUIVOS', files, Icons.description_outlined),
                  if (_tab == _InfoMediaTab.audio)
                    _buildSimpleList('MENSAGENS DE VOZ & ÁUDIOS', audios, Icons.graphic_eq_rounded),
                  if (_tab == _InfoMediaTab.links)
                    _buildSimpleList('LINKS EXTRAÍDOS', links, Icons.link_rounded),
                  if (_tab == _InfoMediaTab.pinned) ...[
                    Text('MENSAGENS FIXADAS', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    if (pinned.isEmpty)
                      Text('Nenhuma mensagem fixada.', style: TextStyle(color: NixColors.textMuted, fontSize: 11.5))
                    else
                      ...pinned.map((m) => InkWell(
                            onTap: () => jumpToMessage(m),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: NixColors.surfaceElevated,
                                borderRadius: NixTokens.borderSm,
                                border: Border.all(color: accent.withValues(alpha: 0.4)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.senderName,
                                    style: TextStyle(
                                      color: accentText,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    m.text,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: NixColors.textPrimary, fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ),
                          )),
                  ],

                  // Em Grupos/Canais: lista de participantes e permissões no overview
                  if (_tab == _InfoMediaTab.overview && dm == null && ch != null) ...[
                    const SizedBox(height: 10),
                    Text('TÓPICO & PERMISSÕES ATIVAS', style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    Text(
                      ch.topic,
                      style: TextStyle(color: NixColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _permPill(ch.permissions.allowMessages ? 'Mensagens: ON' : 'Somente Leitura'),
                        _permPill(ch.permissions.allowEditing ? 'Edição: ON' : 'Edição: OFF'),
                        _permPill(ch.permissions.allowForwarding ? 'Encaminhar: ON' : 'Encaminhar: OFF'),
                        if (ch.permissions.requestScreenshotProtection)
                          _permPill('FLAG_SECURE Ativo'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('PARTICIPANTES & ADMINS (${nixState.members.length})',
                        style: NixTokens.labelUppercase()),
                    const SizedBox(height: 6),
                    ...nixState.members.map((mem) => InkWell(
                          onTap: () => PeerCardIdDialog.showForMember(context, mem),
                          borderRadius: NixTokens.borderSm,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 13,
                                  backgroundColor: NixColors.surfaceElevated,
                                  child: Text(
                                    mem.name[0],
                                    style: TextStyle(color: NixColors.textPrimary, fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    mem.name,
                                    style: TextStyle(
                                      color: NixColors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  mem.roleName,
                                  style: TextStyle(color: NixColors.textMuted, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        )),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDmProfileSummary(BuildContext context, NixState state, DirectMessageThread dm) {
    final accentText = context.accentTextColor;
    final auth = dm.isSavedMessages
        ? null
        : state.getAuthorizedPeerCardData(
            peerName: dm.peerName,
            peerPublicId: dm.peerPublicId,
            trustLevel: dm.trustLevel,
            hasCryptographicShield: dm.isVerified,
            rawBio: dm.statusText,
            rawHighlights: const ['Double Ratchet', 'Tor Onion v3'],
            ownerVisibility: state.settings.cardIdVisibility,
            isVerifiedContact: dm.isVerified,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: dm.isSavedMessages
              ? () => state.openProfileOverlay()
              : () => PeerCardIdDialog.showForDirectMessage(context, dm),
          borderRadius: NixTokens.borderSm,
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: context.accentColor,
                child: Icon(
                  dm.isSavedMessages ? Icons.bookmark_rounded : Icons.person_outline_rounded,
                  color: context.onAccentColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dm.peerName,
                      style: TextStyle(
                        color: NixColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dm.peerPublicId,
                      style: NixTokens.monoCode(size: 10, color: accentText),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (auth != null)
          Text(
            auth.bio,
            style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
          )
        else
          Text(
            'Armazenamento criptografado pessoal para notas, arquivos, links e mensagens encaminhadas.',
            style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
          ),
      ],
    );
  }

  Widget _buildChannelSummary(BuildContext context, NixState state, Channel ch) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '# ${ch.name}',
          style: TextStyle(
            color: NixColors.textPrimary,
            fontSize: 14.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          ch.description.isNotEmpty ? ch.description : ch.topic,
          style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
        ),
        const SizedBox(height: 8),
        Text(
          'Admins: ${ch.admins.length + 1} · Moderadores: ${ch.moderators.length}',
          style: NixTokens.monoCode(size: 10.5, color: context.accentTextColor),
        ),
      ],
    );
  }

  Widget _counterRow({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final accent = context.accentColor;
    final accentText = context.accentTextColor;
    return InkWell(
      onTap: onTap,
      borderRadius: NixTokens.borderSm,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.16) : NixColors.surfaceCard,
          borderRadius: NixTokens.borderSm,
          border: Border.all(
            color: active ? accent.withValues(alpha: 0.45) : NixColors.surfaceBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: active ? accentText : NixColors.iconSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: NixColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: NixColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleList(String heading, List<String> items, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: NixTokens.labelUppercase()),
        const SizedBox(height: 6),
        if (items.isEmpty)
          Text('Nenhum item indexado nesta conversa.',
              style: TextStyle(color: NixColors.textMuted, fontSize: 11.5))
        else
          ...items.map((item) => Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: NixColors.surfaceElevated,
                  borderRadius: NixTokens.borderSm,
                  border: Border.all(color: NixColors.surfaceBorder),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 15, color: context.accentTextColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: TextStyle(color: NixColors.textPrimary, fontSize: 11.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _permPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: NixColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NixColors.surfaceBorder),
      ),
      child: Text(
        text,
        style: TextStyle(color: NixColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}
