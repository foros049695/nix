import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import '../../core/media/voice_note.dart';
import 'desktop_voice_audio.dart';
import 'voice_note_dialog.dart';
import '../navigation/interface_wallpaper_layer.dart';
import 'chat_inline_format.dart';
import '../../core/rich_text/nix_rich_text_controller.dart';
import 'direct_poll_widgets.dart';
import 'emoji_catalog.dart';
import 'chat_attachment_pickers.dart';
import 'image_quality_dialog.dart';
import 'offline_location_picker_dialog.dart';
import 'work_share_card.dart';
import '../profile/cultural_catalog_picker.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/messaging/scheduled_messages.dart';
import '../../core/security/file_picker_adapter.dart';
import '../../core/security/local_image_helper.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';
import '../design/nix_surfaces.dart';

class ChatInputBar extends StatefulWidget {
  final String channelName;
  final bool isDirectMessage;
  final String? scheduledConversationId;
  final void Function(String text, List<String> attachments)? onSendCustom;

  const ChatInputBar({
    super.key,
    required this.channelName,
    this.isDirectMessage = false,
    this.scheduledConversationId,
    this.onSendCustom,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

enum _AttachmentOption { media, documents, articles, location, music, acervo }

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = NixRichTextController();
  final _focusNode = FocusNode();
  final _keyboardFocusNode = FocusNode(skipTraversal: true);
  final _emojiSearchController = TextEditingController();

  final List<String> _pendingAttachments = [];
  bool _showEmojiPicker = false;
  bool _pickingAttachments = false;
  String _selectedEmojiCategory = 'Sorrisos';
  String _emojiSearchQuery = '';
  String? _lastLoadedEditId;
  final List<String> _recentEmojis = ['⚡', '🛡️', '🔒', '🔥', '💿', '🤝'];

  // Gestos Telegram para Mensagem de Voz (Segurar para gravar, arrastar para travar)
  bool _isVoiceRecording = false;
  bool _isVoiceLocked = false;
  int _voiceRecordingMs = 0;
  Timer? _voiceTimer;
  DesktopVoiceAudio? _desktopAudio;
  Offset? _voiceDragOrigin;
  double _voiceDragDy = 0.0;
  double _voiceDragDx = 0.0;

  static const Map<String, String> _emojiKeywords = {
    '😀': 'sorriso feliz alegre smile',
    '😎': 'oculos cool descolado',
    '👍': 'joinha positivo ok sim',
    '🤝': 'acordo aperto mao parceria',
    '🔒': 'cadeado seguro cripto fechado',
    '🔓': 'aberto desbloqueado',
    '🛡️': 'escudo seguranca defesa verificado',
    '⚡': 'raio rapido energia flash',
    '🔥': 'fogo alta tendencia',
    '🔑': 'chave acesso senha',
    '📡': 'antena radio rede tor',
    '📌': 'fixar pin alfinete',
    '🎬': 'filme cinema',
    '📚': 'livros biblioteca estudo',
    '🎧': 'musica audio fone',
    '💿': 'disco vinil album',
    '✓': 'check verificado ok',
    '✨': 'brilho novo',
    '👁️': 'olho privacidade',
  };

  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = _controller.text.trim().isNotEmpty;
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final currentHasText = _controller.text.trim().isNotEmpty;
    if (_hasText != currentHasText && mounted) {
      setState(() {
        _hasText = currentHasText;
      });
    }
  }

  @override
  void dispose() {
    _voiceTimer?.cancel();
    _desktopAudio?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _keyboardFocusNode.dispose();
    _emojiSearchController.dispose();
    super.dispose();
  }

  void _startVoiceRecording() async {
    _focusNode.unfocus();
    final desktop = switch (defaultTargetPlatform) {
      TargetPlatform.linux || TargetPlatform.windows when !Platform.environment.containsKey('FLUTTER_TEST') =>
        DesktopVoiceAudio(),
      _ => null,
    };
    _desktopAudio = desktop;
    try {
      if (desktop != null) {
        await desktop.start();
      } else {
        await VoiceNoteDialog.channel.invokeMethod<void>('start');
      }
    } catch (_) {
      return;
    }

    setState(() {
      _isVoiceRecording = true;
      _isVoiceLocked = false;
      _voiceRecordingMs = 0;
      _voiceDragDy = 0.0;
      _voiceDragDx = 0.0;
    });

    _voiceTimer?.cancel();
    _voiceTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted || !_isVoiceRecording) {
        t.cancel();
        return;
      }
      setState(() {
        _voiceRecordingMs += 100;
      });
      if (_voiceRecordingMs >= VoiceNote.maximumSeconds * 1000) {
        _finishVoiceRecording(send: true);
      }
    });
  }

  void _finishVoiceRecording({required bool send}) async {
    _voiceTimer?.cancel();
    final desktop = _desktopAudio;
    final totalMs = _voiceRecordingMs;

    setState(() {
      _isVoiceRecording = false;
      _isVoiceLocked = false;
      _voiceRecordingMs = 0;
      _desktopAudio = null;
    });

    try {
      if (!send || totalMs < 800) {
        if (desktop != null) {
          await desktop.cancel();
        } else {
          await VoiceNoteDialog.channel.invokeMethod<void>('cancel');
        }
        return;
      }

      final pcm = desktop != null
          ? await desktop.finish()
          : await VoiceNoteDialog.channel.invokeMethod<Uint8List>('finish');
      if (pcm == null || pcm.isEmpty) return;

      final note = VoiceNote.fromPcm(pcm);
      if (!mounted) return;
      final nixState = context.read<NixState>();
      final voiceConversation = widget.scheduledConversationId;

      if (voiceConversation != null && nixState.canSendVoiceNote(voiceConversation)) {
        await nixState.sendVoiceNote(voiceConversation, note);
      } else {
        await nixState.sendVoiceNoteEverywhere(
          note: note,
          isDirect: widget.isDirectMessage,
          onSendCustom: widget.onSendCustom,
        );
      }
    } catch (_) {}
  }

  Future<void> _pickAttachments() async {
    if (_pickingAttachments) return;
    _pickingAttachments = true;
    try {
      final source = await showModalBottomSheet<_AttachmentOption>(
        context: context,
        showDragHandle: true,
        backgroundColor: NixColors.surfaceElevatedHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  key: const Key('attach_option_media'),
                  leading: const Icon(Icons.photo_library_outlined, color: Colors.blueAccent),
                  title: const Text('Fotos'),
                  subtitle: const Text('Galeria de imagens e vídeos com prévia limpa', style: TextStyle(fontSize: 11)),
                  onTap: () => Navigator.pop(sheet, _AttachmentOption.media),
                ),
                ListTile(
                  key: const Key('attach_option_documents'),
                  leading: const Icon(Icons.description_outlined, color: Colors.amber),
                  title: const Text('Arquivos'),
                  subtitle: const Text('Documentos protegidos com verificação SHA-256', style: TextStyle(fontSize: 11)),
                  onTap: () => Navigator.pop(sheet, _AttachmentOption.documents),
                ),
                ListTile(
                  key: const Key('attach_option_articles'),
                  leading: const Icon(Icons.auto_stories_outlined, color: Colors.purpleAccent),
                  title: const Text('Artigos'),
                  subtitle: const Text('Nix Archive assinado criptograficamente', style: TextStyle(fontSize: 11)),
                  onTap: () => Navigator.pop(sheet, _AttachmentOption.articles),
                ),
                ListTile(
                  key: const Key('attach_option_location'),
                  leading: const Icon(Icons.explore_outlined, color: Colors.tealAccent),
                  title: const Text('Localização'),
                  subtitle: const Text('Mapa geográfico offline com marcador manual', style: TextStyle(fontSize: 11)),
                  onTap: () => Navigator.pop(sheet, _AttachmentOption.location),
                ),
                ListTile(
                  key: const Key('attach_option_music'),
                  leading: const Icon(Icons.music_note_outlined, color: Colors.cyanAccent),
                  title: const Text('Música'),
                  subtitle: const Text('Faixas da playlist local e acervo sonoro', style: TextStyle(fontSize: 11)),
                  onTap: () => Navigator.pop(sheet, _AttachmentOption.music),
                ),
                ListTile(
                  key: const Key('attach_option_acervo'),
                  leading: const Icon(Icons.bookmark_outline_rounded, color: Colors.pinkAccent),
                  title: const Text('Acervo'),
                  subtitle: const Text('Compartilhar obra do seu Acervo Cultural', style: TextStyle(fontSize: 11)),
                  onTap: () => Navigator.pop(sheet, _AttachmentOption.acervo),
                ),
              ],
            ),
          ),
        ),
      );
      if (!mounted || source == null) return;

      final nixState = context.read<NixState>();

      switch (source) {
        case _AttachmentOption.media:
          final extensions = [
            ...LocalImageHelper.supportedExtensions,
            'mp4', 'mkv', 'webm', 'mov', 'avi',
          ];
          List<String> picked;
          try {
            picked = await LocalImageHelper.filePickerAdapter.pickAttachments(
              allowedExtensions: extensions,
              allowMultiple: true,
            );
          } on FilePickerUnavailableException {
            if (!mounted) return;
            picked = await CrossPlatformFilePickerAdapter.showPortableFileChooserDialog(
              context,
              allowedExtensions: extensions,
            );
          }
          if (picked.isEmpty || !mounted) return;

          final isImage = LocalImageHelper.isSupportedExtension(picked.first);
          if (isImage && LocalImageHelper.filePickerAdapter is! ProgrammableFilePickerAdapter) {
            final quality = await ImageQualityDialog.selectQuality(
              context,
              filePath: picked.first,
            );
            if (quality == null || !mounted) return;
            if (quality == ImageSendQuality.asFile) {
              final markedDocs = picked.map((p) => p.startsWith('doc_') ? p : 'doc_$p').toList();
              setState(() => _pendingAttachments.addAll(markedDocs));
              return;
            }
          }
          setState(() => _pendingAttachments.addAll(picked));

        case _AttachmentOption.documents:
          const extensions = LocalImageHelper.supportedMediaExtensions;
          List<String> picked;
          try {
            picked = await LocalImageHelper.filePickerAdapter.pickAttachments(
              allowedExtensions: extensions,
              allowMultiple: true,
            );
          } on FilePickerUnavailableException {
            if (!mounted) return;
            picked = await CrossPlatformFilePickerAdapter.showPortableFileChooserDialog(
              context,
              allowedExtensions: extensions,
            );
          }
          if (picked.isNotEmpty && mounted) {
            setState(() => _pendingAttachments.addAll(picked));
          }

        case _AttachmentOption.articles:
          final article = await ArchiveArticlePickerDialog.show(context);
          if (article != null && mounted) {
            if (widget.onSendCustom != null) {
              widget.onSendCustom!(article.toMessageText(), const []);
            } else {
              nixState.sendMessage(article.toMessageText());
            }
          }

        case _AttachmentOption.location:
          final loc = await OfflineLocationPickerDialog.show(context);
          if (loc != null && mounted) {
            if (widget.onSendCustom != null) {
              widget.onSendCustom!(loc.toMessageText(), const []);
            } else {
              nixState.sendMessage(loc.toMessageText());
            }
          }

        case _AttachmentOption.music:
          final trackName = await ChatMusicPickerDialog.show(context);
          if (trackName != null && mounted) {
            final text = 'Música no Pager: $trackName';
            if (widget.onSendCustom != null) {
              widget.onSendCustom!(text, const []);
            } else {
              nixState.sendMessage(text);
            }
          }

        case _AttachmentOption.acervo:
          final work = await pickCulturalCatalogWork(context);
          if (work != null && mounted) {
            final creator = (work.creators != null && work.creators!.trim().isNotEmpty)
                ? work.creators!.split(',').first.trim()
                : '';
            final parsedGenres = (work.genres != null && work.genres!.trim().isNotEmpty)
                ? work.genres!.split(',').map((s) => s.trim()).toList()
                : const <String>[];

            // Busca se o usuário possui a obra em seu Acervo pessoal para compartilhar dados reais
            final userItem = nixState.userProfile.culturalItems.where((i) =>
                i.id == work.id ||
                i.id == 'catalog:${work.id}' ||
                (i.title.toLowerCase() == work.title.toLowerCase() &&
                    i.creatorOrYear.contains('${work.releaseYear}'))).firstOrNull;

            final userRating = userItem != null && userItem.rating.isNotEmpty
                ? double.tryParse(userItem.rating)
                : null;
            final userStage = userItem?.tracking.stage?.label;
            final userCurrent = userItem?.tracking.current;
            final userTotal = userItem?.tracking.total;
            final userPercent = userItem?.tracking.fraction != null
                ? (userItem!.tracking.fraction! * 100).round()
                : null;

            final workData = WorkShareData(
              id: work.id,
              title: work.title,
              originalTitle: work.originalTitle ?? '',
              creator: creator,
              year: work.releaseYear,
              kind: work.kind,
              rating: userRating,
              status: userStage,
              episodesCount: userCurrent,
              totalEpisodes: userTotal,
              completedPercent: userPercent,
              genres: parsedGenres,
              synopsis: work.summary ?? '',
              coverPath: userItem?.localImagePath ?? work.coverThumb,
              source: 'catalog',
              externalId: work.externalIds['wikidata'] as String? ??
                  work.externalIds['openlibrary'] as String?,
            );
            if (widget.onSendCustom != null) {
              widget.onSendCustom!(workData.toMessageText(), const []);
            } else {
              nixState.sendMessage(workData.toMessageText());
            }
          }
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'Não foi possível selecionar os arquivos.')),
        );
      }
    } finally {
      _pickingAttachments = false;
    }
  }

  void _removeAttachment(int index) {
    if (index >= 0 && index < _pendingAttachments.length) {
      setState(() {
        _pendingAttachments.removeAt(index);
      });
    }
  }

  void _send(NixState nixState) {
    final text = _controller.toMarkdown().trim();
    if (text.isNotEmpty || _pendingAttachments.isNotEmpty) {
      final attachments = List<String>.from(_pendingAttachments);
      if (widget.onSendCustom != null) {
        widget.onSendCustom!(text, attachments);
      } else {
        nixState.sendMessage(text, attachments: attachments);
      }
      _controller.clear();
      _hasText = false;
      _pendingAttachments.clear();
      _lastLoadedEditId = null;
      setState(() => _showEmojiPicker = false);
      _focusNode.requestFocus();
    }
  }

  Future<void> _scheduleDraft(NixState state, String conversationId) async {
    final text = _controller.toMarkdown().trim();
    if (text.isEmpty || _pendingAttachments.isNotEmpty ||
        state.editingMessage != null || state.replyingToMessage != null ||
        state.selectedEphemeralTimer != 0) {
      _scheduleNotice('Para agendar, escreva uma mensagem de texto sem anexos, resposta, edição ou temporizador.');
      return;
    }
    _focusNode.unfocus();
    final result = await showDialog<({DateTime when, MessageRecurrence recurrence})>(
      context: context,
      builder: (_) => const _ScheduleDraftDialog(),
    );
    if (result == null || !mounted || widget.scheduledConversationId != conversationId) return;
    try {
      await state.scheduleDirectMessage(
        conversationId: conversationId,
        text: text,
        dueAt: result.when,
        recurrence: result.recurrence,
      );
      if (mounted && _controller.text == text) _controller.clear();
      _scheduleNotice('Mensagem agendada no cofre.');
    } on FormatException catch (error) {
      _scheduleNotice(error.message);
    } catch (_) {
      _scheduleNotice('Não foi possível salvar o agendamento.');
    }
  }

  Future<void> _showScheduled(NixState state, String conversationId) async {
    try {
      final entries = await state.scheduledMessagesFor(conversationId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _ScheduledMessagesDialog(state: state, entries: entries),
      );
    } catch (_) {
      _scheduleNotice('Não foi possível abrir os agendamentos.');
    }
  }

  void _scheduleNotice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void _insertEmoji(String emoji) {
    if (!_recentEmojis.contains(emoji)) {
      _recentEmojis.insert(0, emoji);
      if (_recentEmojis.length > 14) _recentEmojis.removeLast();
    }

    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final newText = text.replaceRange(start, end, emoji);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    _focusNode.requestFocus();
  }

  List<String> get _currentDisplayEmojis {
    final q = _emojiSearchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      final all = nixEmojiCategories.values.expand((e) => e).toSet().toList();
      final matches = all.where((e) {
        final kw = _emojiKeywords[e] ?? '';
        return kw.contains(q) || e == q;
      }).toList();
      return matches.isNotEmpty ? matches : all;
    }
    if (_selectedEmojiCategory == 'Recentes') {
      return _recentEmojis;
    }
    return nixEmojiCategories[_selectedEmojiCategory] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final voiceConversation = widget.scheduledConversationId;
    final isSupportedVoicePlatform = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows;
    final canRecordVoice = isSupportedVoicePlatform &&
        (widget.isDirectMessage || nixState.currentChannel.permissions.allowMessages);

    final ephemeralTimer = nixState.selectedEphemeralTimer;
    final enterToSend = nixState.settings.enterToSend;
    final editing = nixState.editingMessage;
    final replying = nixState.replyingToMessage;
    final accent = context.accentColor;
    final accentText = context.accentTextColor;

    if (editing != null && _lastLoadedEditId != editing.id) {
      _lastLoadedEditId = editing.id;
      _controller.loadMarkdown(editing.text);
    } else if (editing == null && _lastLoadedEditId != null) {
      _lastLoadedEditId = null;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Seletor de Emojis Completo com Categorias, Busca e Inserção no Cursor
        if (_showEmojiPicker && MediaQuery.viewInsetsOf(context).bottom == 0)
          Container(
            height: 256,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: NixColors.surfaceElevatedHigh,
              border: Border(
                  top: BorderSide(
                      color: NixColors.surfaceBorderStrong, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _categoryChip(
                                context, 'Recentes', Icons.history_rounded),
                            for (final category in nixEmojiCategories.keys)
                              _categoryChip(context, category, Icons.emoji_emotions_outlined),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.close,
                          size: 16, color: NixColors.textMuted),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _showEmojiPicker = false),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  key: const Key('emoji_search_input'),
                  controller: _emojiSearchController,
                  onChanged: (v) => setState(() => _emojiSearchQuery = v),
                  style: TextStyle(color: NixColors.textPrimary, fontSize: 12),
                  decoration: const InputDecoration(
                    hintText:
                        'Pesquisar emoji (ex: escudo, fogo, livro, chave)...',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 10,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                    ),
                    itemCount: _currentDisplayEmojis.length,
                    itemBuilder: (context, idx) {
                      final e = _currentDisplayEmojis[idx];
                      return InkWell(
                        onTap: () => _insertEmoji(e),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          decoration: BoxDecoration(
                            color: NixColors.surfaceCard,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: NixColors.surfaceBorder),
                          ),
                          alignment: Alignment.center,
                          child: Text(e, style: const TextStyle(fontSize: 18, fontFamilyFallback: ['NixEmoji'])),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

        // Banner Responder / Editar
        if (replying != null || editing != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: NixColors.surfaceCard,
              border: Border(
                top: BorderSide(color: NixColors.surfaceBorder),
                left: BorderSide(color: accent, width: 3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  editing != null ? Icons.edit_outlined : Icons.reply_rounded,
                  size: 16,
                  color: accentText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    editing != null
                        ? 'Editando mensagem: ${editing.text}'
                        : 'Respondendo a ${replying!.senderName}: ${replying.text}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: NixColors.textSecondary, fontSize: 11.5),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      size: 15, color: NixColors.textMuted),
                  onPressed: () {
                    if (editing != null) {
                      nixState.cancelEditMessage();
                      _controller.clear();
                    } else {
                      nixState.cancelReply();
                    }
                  },
                ),
              ],
            ),
          ),

        // Bandeja de Pré-visualização de Anexos Selecionados
        if (_pendingAttachments.isNotEmpty)
          _buildAttachmentsPreviewTray(context),

        // Barra Principal de Entrada
        LayoutBuilder(builder: (context, constraints) {
          final isGlass = InterfaceWallpaperLayer.translucentPanelsOf(context);
          final compact = constraints.maxWidth < 480;
          final durationSec = (_voiceRecordingMs / 1000).floor();
          final durationStr =
              '${(durationSec ~/ 60).toString().padLeft(2, '0')}:${(durationSec % 60).toString().padLeft(2, '0')}';

          return Container(
            margin: EdgeInsets.fromLTRB(compact ? 7 : 13, 6, compact ? 9 : 15, 9),
            padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 10, vertical: 5),
            decoration: _isVoiceRecording
                ? BoxDecoration(
                    color: NixColors.surfaceSidebar,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.8), width: 1.5),
                  )
                : (isGlass
                    ? BoxDecoration(
                        color: NixColors.surfaceSidebar.withValues(
                            alpha: InterfaceWallpaperLayer.panelOpacityOf(context)),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: NixColors.surfaceBorderStrong.withValues(alpha: 0.3)),
                      )
                    : nixFrameDecoration(context, background: context.surfaceSidebarColor)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_isVoiceRecording) ...[
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      key: const Key('voice_cancel_button'),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                      tooltip: 'Cancelar gravação',
                      onPressed: () => _finishVoiceRecording(send: false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    durationStr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (details) {
                        if (!_isVoiceLocked) {
                          setState(() {
                            _voiceDragDx = (_voiceDragDx + details.delta.dx).clamp(-100.0, 0.0);
                          });
                          if (_voiceDragDx <= -50) {
                            _finishVoiceRecording(send: false);
                          }
                        }
                      },
                      child: _isVoiceLocked
                          ? const Text(
                              'Gravando sem as mãos...',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            )
                          : Transform.translate(
                              offset: Offset(_voiceDragDx.clamp(-40.0, 0.0), 0),
                              child: Row(
                                children: [
                                  const Icon(Icons.chevron_left_rounded, size: 16, color: Colors.white38),
                                  Text(
                                    _voiceDragDx <= -30 ? 'Solte para cancelar' : 'Deslize para cancelar',
                                    style: TextStyle(
                                      color: _voiceDragDx <= -30 ? Colors.redAccent : Colors.white38,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                    key: const Key('chat_attach_button'),
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.attach_file_rounded,
                        color: NixColors.textSecondary, size: 20),
                    tooltip: 'Anexar Mídia / Arquivo (EXIF Sanitizado)',
                    onPressed: _pickAttachments,
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: _EphemeralTimerSelector(
                    currentTimer: ephemeralTimer,
                    onPoll: voiceConversation != null && nixState.canUseDirectPolls(voiceConversation)
                        ? () {
                            _focusNode.unfocus();
                            showDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => CreateDirectPollDialog(
                                onCreate: (poll) => nixState.createDirectPoll(voiceConversation, poll),
                              ),
                            );
                          }
                        : null,
                    onChanged: nixState.setEphemeralTimer,
                    onSchedule: nixState.canScheduleDirectMessages &&
                            widget.scheduledConversationId != null
                        ? () => _scheduleDraft(nixState, widget.scheduledConversationId!)
                        : null,
                    onShowSchedules: nixState.canScheduleDirectMessages &&
                            widget.scheduledConversationId != null
                        ? () => _showScheduled(nixState, widget.scheduledConversationId!)
                        : null,
                  ),
                ),
                if (!compact) const SizedBox(width: 4),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    key: const Key('emoji_picker_toggle_button'),
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      _showEmojiPicker
                          ? Icons.keyboard_rounded
                          : Icons.sentiment_satisfied_alt_rounded,
                      color: _showEmojiPicker
                          ? accentText
                          : NixColors.textSecondary,
                      size: 20,
                    ),
                    tooltip: 'Seletor de Emojis',
                    onPressed: () {
                      _focusNode.unfocus();
                      setState(() => _showEmojiPicker = !_showEmojiPicker);
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Focus(
                    focusNode: _keyboardFocusNode,
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent) {
                        final isCtrlOrCmd = HardwareKeyboard.instance.isControlPressed ||
                            HardwareKeyboard.instance.isMetaPressed;
                        if (isCtrlOrCmd) {
                          if (event.logicalKey == LogicalKeyboardKey.keyB) {
                            _controller.toggleBold();
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey == LogicalKeyboardKey.keyI) {
                            _controller.toggleItalic();
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey == LogicalKeyboardKey.keyU) {
                            _controller.toggleUnderline();
                            return KeyEventResult.handled;
                          }
                          if (HardwareKeyboard.instance.isShiftPressed &&
                              (event.logicalKey == LogicalKeyboardKey.keyX ||
                                  event.logicalKey == LogicalKeyboardKey.keyS)) {
                            _controller.toggleStrikethrough();
                            return KeyEventResult.handled;
                          }
                          if (HardwareKeyboard.instance.isShiftPressed &&
                              event.logicalKey == LogicalKeyboardKey.keyM) {
                            _controller.toggleMonospace();
                            return KeyEventResult.handled;
                          }
                          if (HardwareKeyboard.instance.isShiftPressed &&
                              event.logicalKey == LogicalKeyboardKey.keyP) {
                            _controller.toggleSpoiler();
                            return KeyEventResult.handled;
                          }
                        }
                        if (enterToSend &&
                            event.logicalKey == LogicalKeyboardKey.enter &&
                            !HardwareKeyboard.instance.isShiftPressed) {
                          _send(nixState);
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      key: const Key('chat_message_input'),
                      contextMenuBuilder: buildChatFormatMenu,
                      controller: _controller,
                      focusNode: _focusNode,
                      onChanged: (_) => _onTextChanged(),
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: enterToSend ? TextInputAction.send : TextInputAction.newline,
                      onSubmitted: enterToSend ? (_) => _send(nixState) : null,
                      style: TextStyle(
                          color: NixColors.textPrimary, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: editing != null
                            ? 'Editar mensagem...'
                            : (widget.isDirectMessage
                                ? (widget.channelName.contains('Salvas')
                                    ? 'Escrever nota privada em Mensagens Salvas...'
                                    : 'Mensagem cifrada para ${widget.channelName}...')
                                : 'Mensagem cifrada em #${widget.channelName}...'),
                        hintStyle:
                            TextStyle(color: NixColors.textMuted, fontSize: 13),
                        filled: true,
                        fillColor: NixColors.surfaceInput,
                        border: OutlineInputBorder(
                          borderRadius: NixTokens.borderInput,
                          borderSide:
                              BorderSide(color: NixColors.surfaceBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: NixTokens.borderInput,
                          borderSide:
                              BorderSide(color: NixColors.surfaceBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: NixTokens.borderInput,
                          borderSide: BorderSide(color: accent, width: 1.4),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                ),
                ],
                const SizedBox(width: 8),
                Builder(
                  builder: (context) {
                    final hasText = _controller.text.trim().isNotEmpty;
                    final hasAttachments = _pendingAttachments.isNotEmpty;
                    final isEditing = editing != null;
                    final isLockedVoice = _isVoiceRecording && _isVoiceLocked;
                    final showSend = (isEditing || hasAttachments || hasText) && !_isVoiceRecording;

                    if (showSend || isLockedVoice) {
                      return Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isLockedVoice ? Colors.green.shade600 : accent,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          key: const Key('chat_send_button'),
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            isEditing ? Icons.check_rounded : Icons.arrow_upward_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          tooltip: isLockedVoice
                              ? 'Enviar Mensagem de Voz'
                              : (isEditing
                                  ? 'Salvar Edição'
                                  : (hasAttachments
                                      ? 'Enviar Anexos Cifrados'
                                      : 'Transmitir Envelope Cifrado (Enter)')),
                          onPressed: () {
                            if (isLockedVoice) {
                              _finishVoiceRecording(send: true);
                            } else {
                              _send(nixState);
                            }
                          },
                        ),
                      );
                    }

                    return Tooltip(
                      message: canRecordVoice
                          ? (_isVoiceRecording
                              ? 'Arraste para cima para travar · Arraste para esquerda para cancelar'
                              : 'Segure para gravar · Arraste para cima para travar')
                          : 'Gravação não disponível neste canal',
                      child: GestureDetector(
                        key: const Key('voice_record_button'),
                        behavior: HitTestBehavior.opaque,
                        onTap: !canRecordVoice
                            ? null
                            : () {
                                if (_isVoiceRecording) {
                                  setState(() {
                                    _isVoiceLocked = true;
                                  });
                                } else {
                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Segure o microfone para gravar áudio · Arraste para cima para travar'),
                                      duration: Duration(milliseconds: 1800),
                                    ),
                                  );
                                }
                              },
                        onLongPressStart: !canRecordVoice
                            ? null
                            : (details) {
                                _voiceDragOrigin = details.globalPosition;
                                _startVoiceRecording();
                              },
                        onLongPressMoveUpdate: !canRecordVoice
                            ? null
                            : (details) {
                                if (_isVoiceRecording && !_isVoiceLocked && _voiceDragOrigin != null) {
                                  final dy = details.globalPosition.dy - _voiceDragOrigin!.dy;
                                  final dx = details.globalPosition.dx - _voiceDragOrigin!.dx;
                                  setState(() {
                                    _voiceDragDy = dy;
                                    _voiceDragDx = dx;
                                  });
                                  // Arrastou para cima >= 40px: TRAVA GRAVAÇÃO MÃOS LIVRES
                                  if (dy <= -40) {
                                    setState(() {
                                      _isVoiceLocked = true;
                                    });
                                  }
                                  // Arrastou para esquerda >= 50px: CANCELA
                                  if (dx <= -50) {
                                    _finishVoiceRecording(send: false);
                                  }
                                }
                              },
                        onLongPressEnd: !canRecordVoice
                            ? null
                            : (_) {
                                if (_isVoiceRecording && !_isVoiceLocked) {
                                  _finishVoiceRecording(send: _voiceRecordingMs >= 800);
                                }
                              },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: _isVoiceRecording ? 40 : 36,
                          height: _isVoiceRecording ? 40 : 36,
                          decoration: BoxDecoration(
                            color: _isVoiceRecording
                                ? Colors.redAccent
                                : (canRecordVoice ? accent : NixColors.surfaceCard),
                            shape: BoxShape.circle,
                            boxShadow: _isVoiceRecording
                                ? [
                                    BoxShadow(
                                      color: Colors.redAccent.withValues(alpha: 0.5),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                            border: canRecordVoice && !_isVoiceRecording
                                ? null
                                : Border.all(color: _isVoiceRecording ? Colors.white70 : NixColors.surfaceBorder),
                          ),
                          alignment: Alignment.center,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                Icons.mic_rounded,
                                size: _isVoiceRecording ? 22 : 20,
                                color: _isVoiceRecording
                                    ? Colors.white
                                    : (canRecordVoice
                                        ? context.onAccentColor
                                        : NixColors.textMuted),
                              ),
                              if (_isVoiceRecording && _voiceDragDy <= -20)
                                Positioned(
                                  top: 2,
                                  child: Icon(
                                    Icons.lock_open_rounded,
                                    size: 10,
                                    color: _voiceDragDy <= -40 ? Colors.white : Colors.white70,
                                  ),
                                ),
                            ],
                          ),
                        ),
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



  Widget _buildAttachmentsPreviewTray(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: NixColors.surfaceCard,
        border: Border(top: BorderSide(color: NixColors.surfaceBorder)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _pendingAttachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, idx) {
          final path = _pendingAttachments[idx];
          final name = LocalImageHelper.getFileName(path);
          final ext = name.split('.').last.toLowerCase();
          IconData icon = Icons.insert_drive_file_outlined;
          if (['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) {
            icon = Icons.image_outlined;
          } else if (['mp4', 'mkv', 'webm'].contains(ext)) {
            icon = Icons.videocam_outlined;
          } else if (['mp3', 'ogg', 'wav', 'flac'].contains(ext)) {
            icon = Icons.audiotrack_outlined;
          } else if (['pdf', 'txt', 'docx', 'md'].contains(ext)) {
            icon = Icons.description_outlined;
          }

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: NixColors.surfaceElevated,
              borderRadius: NixTokens.borderSm,
              border: Border.all(color: NixColors.surfaceBorderStrong),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (LocalImageHelper.isSupportedExtension(path) && File(path).isAbsolute)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.file(
                      File(path),
                      key: ValueKey('attachment_preview_$path'),
                      width: 36,
                      height: 36,
                      cacheWidth: 72,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      errorBuilder: (_, __, ___) =>
                          Icon(icon, size: 16, color: context.accentTextColor),
                    ),
                  )
                else
                  Icon(icon, size: 16, color: context.accentTextColor),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    name,
                    style:
                        TextStyle(color: NixColors.textPrimary, fontSize: 11.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  key: Key('remove_attachment_$idx'),
                  onTap: () => _removeAttachment(idx),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded,
                        size: 14, color: NixColors.textMuted),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _categoryChip(BuildContext context, String title, IconData icon) {
    final selected = _selectedEmojiCategory == title;
    final accent = context.accentColor;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => setState(() => _selectedEmojiCategory = title),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? accent : NixColors.surfaceCard,
            borderRadius: BorderRadius.circular(6),
            border:
                Border.all(color: selected ? accent : NixColors.surfaceBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 12,
                  color: selected
                      ? context.onAccentColor
                      : NixColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  color: selected
                      ? context.onAccentColor
                      : NixColors.textSecondary,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EphemeralTimerSelector extends StatelessWidget {
  final int currentTimer;
  final ValueChanged<int> onChanged;
  final VoidCallback? onSchedule;
  final VoidCallback? onPoll;
  final VoidCallback? onShowSchedules;

  const _EphemeralTimerSelector({
    required this.currentTimer,
    required this.onChanged,
    this.onSchedule,
    this.onPoll,
    this.onShowSchedules,
  });

  @override
  Widget build(BuildContext context) {
    final isTimerActive = currentTimer > 0;
    return PopupMenuButton<int>(
      key: const Key('chat_timer_button'),
      tooltip: onPoll != null ? 'Enquete, temporizador e agendamento' :
          onSchedule == null ? 'Temporizador de Mensagem Efêmera' : 'Temporizador e agendamento',
      initialValue: currentTimer,
      onSelected: (value) {
        switch (value) {
          case -1:
            onSchedule?.call();
          case -2:
            onShowSchedules?.call();
          case -3:
            onPoll?.call();
          default:
            onChanged(value);
        }
      },
      padding: EdgeInsets.zero,
      color: NixColors.surfaceElevatedHigh,
      shape: RoundedRectangleBorder(
        borderRadius: NixTokens.borderSm,
        side: BorderSide(color: NixColors.surfaceBorderStrong),
      ),
      icon: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            isTimerActive ? Icons.timer_rounded : Icons.timer_outlined,
            size: 20,
            color: isTimerActive
                ? context.accentTextColor
                : NixColors.textSecondary,
          ),
          if (isTimerActive)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 2.5, vertical: 0.5),
                decoration: BoxDecoration(
                  color: context.accentColor,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  _formatSeconds(currentTimer),
                  style: TextStyle(
                    color: context.onAccentColor,
                    fontSize: 7.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
      itemBuilder: (context) => [
        if (onPoll != null)
          const PopupMenuItem(value: -3, child: Text('Criar enquete')),
        if (onSchedule != null) ...[
          const PopupMenuItem(value: -1, child: Text('Agendar este texto')),
          const PopupMenuItem(value: -2, child: Text('Ver agendamentos')),
          const PopupMenuDivider(),
        ],
        PopupMenuItem(
            value: 0,
            child: Text('Desativado (Permanente)',
                style: TextStyle(color: NixColors.textPrimary, fontSize: 12))),
        PopupMenuItem(
            value: 30,
            child: Text('30 segundos',
                style: TextStyle(color: NixColors.textPrimary, fontSize: 12))),
        PopupMenuItem(
            value: 60,
            child: Text('1 minuto',
                style: TextStyle(color: NixColors.textPrimary, fontSize: 12))),
        PopupMenuItem(
            value: 300,
            child: Text('5 minutos',
                style: TextStyle(color: NixColors.textPrimary, fontSize: 12))),
        PopupMenuItem(
            value: 3600,
            child: Text('1 hora',
                style: TextStyle(color: NixColors.textPrimary, fontSize: 12))),
        PopupMenuItem(
            value: 86400,
            child: Text('24 horas',
                style: TextStyle(color: NixColors.textPrimary, fontSize: 12))),
      ],
    );
  }

  String _formatSeconds(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    return '${seconds ~/ 3600}h';
  }
}


class _ScheduleDraftDialog extends StatefulWidget {
  const _ScheduleDraftDialog();

  @override
  State<_ScheduleDraftDialog> createState() => _ScheduleDraftDialogState();
}

class _ScheduleDraftDialogState extends State<_ScheduleDraftDialog> {
  DateTime _when = DateTime.now().add(const Duration(minutes: 5));
  MessageRecurrence _recurrence = MessageRecurrence.once;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return AlertDialog(
      title: const Text('Agendar mensagem'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text(localizations.formatMediumDate(_when)),
            onPressed: () async {
              final now = DateTime.now();
              final day = await showDatePicker(
                context: context,
                initialDate: _when.isBefore(now) ? now : _when,
                firstDate: now,
                lastDate: now.add(const Duration(days: 365)),
              );
              if (mounted && day != null) {
                setState(() => _when = DateTime(
                  day.year, day.month, day.day, _when.hour, _when.minute,
                ));
              }
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.access_time),
            label: Text(TimeOfDay.fromDateTime(_when).format(context)),
            onPressed: () async {
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(_when),
              );
              if (mounted && time != null) {
                setState(() => _when = DateTime(
                  _when.year, _when.month, _when.day, time.hour, time.minute,
                ));
              }
            },
          ),
          DropdownButton<MessageRecurrence>(
            value: _recurrence,
            isExpanded: true,
            onChanged: (value) => setState(() => _recurrence = value!),
            items: [
              for (final recurrence in MessageRecurrence.values)
                DropdownMenuItem(value: recurrence, child: Text(recurrence.label)),
            ],
          ),
          const Text('O envio requer o Nix aberto, o cofre desbloqueado e o relay Onion disponível.'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (when: _when, recurrence: _recurrence)),
          child: const Text('Agendar'),
        ),
      ],
      scrollable: true,
    );
  }
}

class _ScheduledMessagesDialog extends StatefulWidget {
  const _ScheduledMessagesDialog({required this.state, required this.entries});

  final NixState state;
  final List<ScheduledMessage> entries;

  @override
  State<_ScheduledMessagesDialog> createState() => _ScheduledMessagesDialogState();
}

class _ScheduledMessagesDialogState extends State<_ScheduledMessagesDialog> {
  late final _entries = widget.entries.toList();
  String? _error;

  Future<void> _cancel(ScheduledMessage entry) async {
    try {
      final cancelled = await widget.state.cancelScheduledMessage(entry);
      if (mounted) {
        setState(() {
          _entries.remove(entry);
          _error = cancelled ? null : 'Este agendamento já foi processado ou removido.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível cancelar o agendamento.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return AlertDialog(
      title: const Text('Mensagens agendadas'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) Text(_error!),
            if (_entries.isEmpty) const Text('Nenhuma mensagem agendada nesta conversa.'),
            for (final entry in _entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${localizations.formatShortDate(entry.dueAt.toLocal())} '
                  '${TimeOfDay.fromDateTime(entry.dueAt.toLocal()).format(context)} · '
                  '${entry.recurrence.label}',
                ),
                trailing: IconButton(
                  tooltip: 'Cancelar agendamento',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _cancel(entry),
                ),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}
