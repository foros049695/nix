import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/media/voice_note.dart';
import '../../core/models/channel.dart';
import '../../core/models/direct_message.dart';
import '../../core/models/message.dart';
import '../../core/security/local_image_helper.dart';
import '../../core/security/platform_runtime.dart';
import '../../core/security/secure_file_download_helper.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../design/nix_surfaces.dart';
import '../profile/peer_card_id_dialog.dart';
import 'external_link_dialog.dart';
import 'voice_note_dialog.dart';

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
                    _buildPhotosSection(context, nixState, msgs, photos),
                  if (_tab == _InfoMediaTab.videos)
                    _buildVideosSection(context, nixState, msgs, videos),
                  if (_tab == _InfoMediaTab.files)
                    _buildFilesSection(context, nixState, msgs, files),
                  if (_tab == _InfoMediaTab.audio)
                    _buildAudioSection(context, nixState, msgs, audios),
                  if (_tab == _InfoMediaTab.links)
                    _buildLinksSection(context, links),
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

  Future<Uint8List?> _resolveImageBytes(NixState state, List<Message> msgs, String ref) async {
    for (final m in msgs) {
      final idx = m.attachments.indexOf(ref);
      if (idx != -1) {
        final bytes = await state.readMessageImage(m, idx);
        if (bytes != null) return bytes;
      }
    }
    if (File(ref).isAbsolute) {
      final f = File(ref);
      if (await f.exists()) return LocalImageHelper.stripMetadataBytes(await f.readAsBytes());
    }
    final relative = File(NixPlatformPaths.resolveDataFile(ref));
    if (await relative.exists()) return LocalImageHelper.stripMetadataBytes(await relative.readAsBytes());
    final sanitized = File(NixPlatformPaths.resolveDataFile('sanitized_media/$ref'));
    if (await sanitized.exists()) return LocalImageHelper.stripMetadataBytes(await sanitized.readAsBytes());
    if (ref.startsWith('assets/')) {
      final data = await rootBundle.load(ref);
      return data.buffer.asUint8List();
    }
    return null;
  }

  Future<Uint8List?> _resolveAttachmentBytes(NixState state, List<Message> msgs, String ref) async {
    for (final m in msgs) {
      final idx = m.attachments.indexOf(ref);
      if (idx != -1) {
        final bytes = await state.readMessageAttachmentBytes(m, idx);
        if (bytes != null) return bytes;
      }
    }
    if (File(ref).isAbsolute) {
      final f = File(ref);
      if (await f.exists()) return await f.readAsBytes();
    }
    final relative = File(NixPlatformPaths.resolveDataFile(ref));
    if (await relative.exists()) return await relative.readAsBytes();
    final sanitized = File(NixPlatformPaths.resolveDataFile('sanitized_media/$ref'));
    if (await sanitized.exists()) return await sanitized.readAsBytes();
    if (ref.startsWith('assets/')) {
      final data = await rootBundle.load(ref);
      return data.buffer.asUint8List();
    }
    return null;
  }

  Future<void> _openPhotoViewer(BuildContext context, Uint8List bytes, String name) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black.withValues(alpha: 0.94),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.image_outlined, size: 18, color: Colors.white70),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_rounded, color: Colors.white70),
                    tooltip: 'Salvar imagem',
                    onPressed: () async {
                      final confirmed = await SecureFileDownloadHelper.confirmDownload(
                        dialogContext,
                        fileName: name,
                        byteSize: bytes.length,
                      );
                      if (confirmed && dialogContext.mounted) {
                        try {
                          final file = await SecureFileDownloadHelper.saveFileSafely(
                            bytes: bytes,
                            rawFileName: name,
                          );
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Foto salva com segurança em: ${file.path}')),
                            );
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Erro ao salvar foto: $e')),
                            );
                          }
                        }
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotosSection(BuildContext context, NixState state, List<Message> msgs, List<String> photos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('FOTOS COMPARTILHADAS (${photos.length})', style: NixTokens.labelUppercase()),
        const SizedBox(height: 8),
        if (photos.isEmpty)
          Text('Nenhuma foto indexada nesta conversa.',
              style: TextStyle(color: NixColors.textMuted, fontSize: 11.5))
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 1.0,
            ),
            itemCount: photos.length,
            itemBuilder: (context, idx) {
              final ref = photos[idx];
              final name = LocalImageHelper.getFileName(ref);
              return FutureBuilder<Uint8List?>(
                future: _resolveImageBytes(state, msgs, ref),
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes == null) {
                    return Container(
                      decoration: BoxDecoration(
                        color: NixColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: NixColors.surfaceBorder),
                      ),
                      child: const Center(
                        child: Icon(Icons.image_outlined, size: 20, color: Colors.white24),
                      ),
                    );
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      onTap: () => _openPhotoViewer(context, bytes, name),
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: NixColors.surfaceElevated,
                          child: const Icon(Icons.broken_image_outlined, size: 20),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
      ],
    );
  }

  Widget _buildVideosSection(BuildContext context, NixState state, List<Message> msgs, List<String> videos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('VÍDEOS COMPARTILHADOS (${videos.length})', style: NixTokens.labelUppercase()),
        const SizedBox(height: 8),
        if (videos.isEmpty)
          Text('Nenhum vídeo indexado nesta conversa.',
              style: TextStyle(color: NixColors.textMuted, fontSize: 11.5))
        else
          ...videos.map((vid) {
            final name = LocalImageHelper.getFileName(vid);
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: NixColors.surfaceElevated,
                borderRadius: NixTokens.borderSm,
                border: Border.all(color: NixColors.surfaceBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.videocam_rounded, size: 18, color: Colors.purpleAccent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(color: NixColors.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_rounded, size: 18),
                    color: NixColors.textSecondary,
                    tooltip: 'Baixar vídeo',
                    onPressed: () async {
                      final bytes = await _resolveAttachmentBytes(state, msgs, vid);
                      if (bytes != null && context.mounted) {
                        final confirmed = await SecureFileDownloadHelper.confirmDownload(
                          context,
                          fileName: name,
                          byteSize: bytes.length,
                        );
                        if (confirmed && context.mounted) {
                          final saved = await SecureFileDownloadHelper.saveFileSafely(
                            bytes: bytes,
                            rawFileName: name,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Vídeo salvo em: ${saved.path}')),
                            );
                          }
                        }
                      }
                    },
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildFilesSection(BuildContext context, NixState state, List<Message> msgs, List<String> files) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ARQUIVOS & DOCUMENTOS (${files.length})', style: NixTokens.labelUppercase()),
        const SizedBox(height: 8),
        if (files.isEmpty)
          Text('Nenhum arquivo indexado nesta conversa.',
              style: TextStyle(color: NixColors.textMuted, fontSize: 11.5))
        else
          ...files.map((file) {
            final name = LocalImageHelper.getFileName(file);
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: NixColors.surfaceElevated,
                borderRadius: NixTokens.borderSm,
                border: Border.all(color: NixColors.surfaceBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.insert_drive_file_outlined, size: 18, color: context.accentTextColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(color: NixColors.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_rounded, size: 18),
                    color: NixColors.textSecondary,
                    tooltip: 'Baixar arquivo',
                    onPressed: () async {
                      final bytes = await _resolveAttachmentBytes(state, msgs, file);
                      if (bytes != null && context.mounted) {
                        final confirmed = await SecureFileDownloadHelper.confirmDownload(
                          context,
                          fileName: name,
                          byteSize: bytes.length,
                        );
                        if (confirmed && context.mounted) {
                          final saved = await SecureFileDownloadHelper.saveFileSafely(
                            bytes: bytes,
                            rawFileName: name,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Arquivo salvo em: ${saved.path}')),
                            );
                          }
                        }
                      }
                    },
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildAudioSection(BuildContext context, NixState state, List<Message> msgs, List<String> audios) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MENSAGENS DE VOZ & ÁUDIOS (${audios.length})', style: NixTokens.labelUppercase()),
        const SizedBox(height: 8),
        if (audios.isEmpty)
          Text('Nenhum áudio indexado nesta conversa.',
              style: TextStyle(color: NixColors.textMuted, fontSize: 11.5))
        else
          ...audios.map((aud) {
            final name = LocalImageHelper.getFileName(aud);
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: NixColors.surfaceElevated,
                borderRadius: NixTokens.borderSm,
                border: Border.all(color: NixColors.surfaceBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.graphic_eq_rounded, size: 18, color: context.accentTextColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(color: NixColors.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text('Ouvir', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (_) => VoiceNoteDialog.listen(
                          load: () async {
                            final bytes = await _resolveAttachmentBytes(state, msgs, aud);
                            if (bytes == null) return null;
                            try {
                              return VoiceNote.fromWav(bytes);
                            } catch (_) {
                              try {
                                return VoiceNote.fromPcm(bytes);
                              } catch (_) {
                                return null;
                              }
                            }
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildLinksSection(BuildContext context, List<String> links) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LINKS COMPARTILHADOS (${links.length})', style: NixTokens.labelUppercase()),
        const SizedBox(height: 8),
        if (links.isEmpty)
          Text('Nenhum link detectado nesta conversa.',
              style: TextStyle(color: NixColors.textMuted, fontSize: 11.5))
        else
          ...links.map((link) => InkWell(
                onTap: () => ExternalLinkDialog.show(context, link),
                borderRadius: NixTokens.borderSm,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: NixColors.surfaceElevated,
                    borderRadius: NixTokens.borderSm,
                    border: Border.all(color: NixColors.surfaceBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.link_rounded, size: 16, color: context.accentTextColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          link,
                          style: const TextStyle(
                            color: Color(0xFF64B5F6),
                            fontSize: 11.5,
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFF64B5F6),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 15),
                        color: NixColors.textMuted,
                        tooltip: 'Copiar link',
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: link));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Link copiado para a área de transferência.'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
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
