import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'voice_note_dialog.dart';
import 'chat_inline_format.dart';
import 'emoji_catalog.dart';
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

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
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

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _keyboardFocusNode.dispose();
    _emojiSearchController.dispose();
    super.dispose();
  }

  Future<void> _pickAttachments() async {
    if (_pickingAttachments) return;
    _pickingAttachments = true;
    try {
      List<String> picked;
      try {
        picked = await LocalImageHelper.pickAttachmentsNativeDesktop();
      } on FilePickerUnavailableException {
        if (!mounted) return;
        picked = await CrossPlatformFilePickerAdapter.showPortableFileChooserDialog(
          context,
          allowedExtensions: LocalImageHelper.supportedMediaExtensions,
        );
      }
      if (picked.isNotEmpty && mounted) {
        setState(() => _pendingAttachments.addAll(picked));
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'Não foi possível selecionar arquivos.')),
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
    final text = _controller.text;
    if (text.trim().isNotEmpty || _pendingAttachments.isNotEmpty) {
      final attachments = List<String>.from(_pendingAttachments);
      if (widget.onSendCustom != null) {
        widget.onSendCustom!(text, attachments);
      } else {
        nixState.sendMessage(text, attachments: attachments);
      }
      _controller.clear();
      _pendingAttachments.clear();
      _lastLoadedEditId = null;
      setState(() => _showEmojiPicker = false);
      _focusNode.requestFocus();
    }
  }

  Future<void> _scheduleDraft(NixState state, String conversationId) async {
    final text = _controller.text;
    if (text.trim().isEmpty || _pendingAttachments.isNotEmpty ||
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
    final canRecordVoice = defaultTargetPlatform == TargetPlatform.android &&
        voiceConversation != null && nixState.canSendVoiceNote(voiceConversation);

    final ephemeralTimer = nixState.selectedEphemeralTimer;
    final enterToSend = nixState.settings.enterToSend;
    final editing = nixState.editingMessage;
    final replying = nixState.replyingToMessage;
    final accent = context.accentColor;
    final accentText = context.accentTextColor;

    if (editing != null && _lastLoadedEditId != editing.id) {
      _lastLoadedEditId = editing.id;
      _controller.text = editing.text;
      _controller.selection =
          TextSelection.collapsed(offset: editing.text.length);
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
          final compact = constraints.maxWidth < 480;
          return Container(
            margin: EdgeInsets.fromLTRB(compact ? 7 : 13, 6, compact ? 9 : 15, 9),
            padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 10, vertical: 5),
            decoration: nixFrameDecoration(context, background: context.surfaceSidebarColor),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
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
                      if (enterToSend &&
                          event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter &&
                          !HardwareKeyboard.instance.isShiftPressed) {
                        _send(nixState);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      key: const Key('chat_message_input'),
                      contextMenuBuilder: buildChatFormatMenu,
                      controller: _controller,
                      focusNode: _focusNode,
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
                const SizedBox(width: 8),
                if (!compact || canRecordVoice) ...[
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      key: const Key('voice_record_button'),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.mic_none_rounded, size: 20),
                      tooltip: canRecordVoice
                          ? 'Gravar mensagem de voz'
                          : 'Voz disponível em conversas diretas cifradas no Android',
                      onPressed: !canRecordVoice ? null : () {
                        _focusNode.unfocus();
                        showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => VoiceNoteDialog.record(
                            onSend: (note) => nixState.sendVoiceNote(voiceConversation, note),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    key: const Key('chat_send_button'),
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      editing != null
                          ? Icons.check_rounded
                          : Icons.arrow_upward_rounded,
                      color: context.onAccentColor,
                      size: 18,
                    ),
                    tooltip: editing != null
                        ? 'Salvar Edição'
                        : 'Transmitir Envelope Cifrado (Enter)',
                    onPressed: () => _send(nixState),
                  ),
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
      height: 48,
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
  final VoidCallback? onShowSchedules;

  const _EphemeralTimerSelector({
    required this.currentTimer,
    required this.onChanged,
    this.onSchedule,
    this.onShowSchedules,
  });

  @override
  Widget build(BuildContext context) {
    final isTimerActive = currentTimer > 0;
    return PopupMenuButton<int>(
      key: const Key('chat_timer_button'),
      tooltip: onSchedule == null ? 'Temporizador de Mensagem Efêmera' : 'Temporizador e agendamento',
      initialValue: currentTimer,
      onSelected: (value) {
        switch (value) {
          case -1:
            onSchedule?.call();
          case -2:
            onShowSchedules?.call();
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
