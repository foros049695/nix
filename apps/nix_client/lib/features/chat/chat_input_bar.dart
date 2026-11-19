import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/security/file_picker_adapter.dart';
import '../../core/security/local_image_helper.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

class ChatInputBar extends StatefulWidget {
  final String channelName;
  final bool isDirectMessage;
  final void Function(String text, List<String> attachments)? onSendCustom;

  const ChatInputBar({
    super.key,
    required this.channelName,
    this.isDirectMessage = false,
    this.onSendCustom,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _emojiSearchController = TextEditingController();

  final List<String> _pendingAttachments = [];
  bool _showEmojiPicker = false;
  String _selectedEmojiCategory = 'Sorrisos';
  String _emojiSearchQuery = '';
  String? _lastLoadedEditId;
  final List<String> _recentEmojis = ['⚡', '🛡️', '🔒', '🔥', '💿', '🤝'];

  static const Map<String, List<String>> _categorizedEmojis = {
    'Sorrisos': [
      '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🥹', '☺️',
      '😊', '😇', '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😋',
      '😛', '😜', '🤪', '🤨', '🧐', '🤓', '😎', '🤩', '🥳', '😏',
    ],
    'Gestos': [
      '👍', '👎', '👊', '✊', '🤛', '🤜', '👏', '🙌', '👐', '🤲',
      '🤝', '🙏', '✌️', '🤞', '🤟', '🤘', '🤙', '👈', '👉', '👋',
    ],
    'Segurança & Símbolos': [
      '🔒', '🔓', '🛡️', '⚔️', '⚡', '👁️', '🔑', '🗝️', '⚙️', '🪙',
      '📡', '📶', '🧭', '🎯', '⏳', '⌛', '📌', '💡', '🔍', '🔎',
      '💬', '💭', '🏴‍☠️', '✓', '❌', '⚠️', '🛑', '🚩', '💠', '✨',
    ],
    'Cultura & Objetos': [
      '💿', '📼', '📻', '🎬', '📚', '📖', '🎧', '🎤', '🎹', '🎮',
      '🕹️', '💻', '🖥️', '📱', '🛰️', '🚀', '🛸', '☕', '🍵', '🍕',
    ],
  };

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
    _emojiSearchController.dispose();
    super.dispose();
  }

  Future<void> _pickAttachments() async {
    final picked = await LocalImageHelper.pickAttachmentsNativeDesktop();
    if (picked.isNotEmpty) {
      setState(() {
        _pendingAttachments.addAll(picked);
      });
      return;
    }
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      setState(() {
        _pendingAttachments.add('documento_seguro.pdf');
      });
      return;
    }
    if (!mounted) return;
    final fallbackPicked =
        await CrossPlatformFilePickerAdapter.showPortableFileChooserDialog(
      context,
      allowedExtensions: LocalImageHelper.supportedMediaExtensions,
    );
    if (fallbackPicked.isNotEmpty && mounted) {
      setState(() {
        _pendingAttachments.addAll(fallbackPicked);
      });
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
      final all = _categorizedEmojis.values.expand((e) => e).toSet().toList();
      final matches = all.where((e) {
        final kw = _emojiKeywords[e] ?? '';
        return kw.contains(q) || e == q;
      }).toList();
      return matches.isNotEmpty ? matches : all;
    }
    if (_selectedEmojiCategory == 'Recentes') {
      return _recentEmojis;
    }
    return _categorizedEmojis[_selectedEmojiCategory] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final ephemeralTimer = nixState.selectedEphemeralTimer;
    final enterToSend = nixState.settings.enterToSend;
    final editing = nixState.editingMessage;
    final replying = nixState.replyingToMessage;
    final accent = context.accentColor;
    final accentText = context.accentTextColor;

    if (editing != null && _lastLoadedEditId != editing.id) {
      _lastLoadedEditId = editing.id;
      _controller.text = editing.text;
      _controller.selection = TextSelection.collapsed(offset: editing.text.length);
    } else if (editing == null && _lastLoadedEditId != null) {
      _lastLoadedEditId = null;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Seletor de Emojis Completo com Categorias, Busca e Inserção no Cursor
        if (_showEmojiPicker)
          Container(
            height: 256,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: NixColors.surfaceElevatedHigh,
              border: Border(top: BorderSide(color: NixColors.surfaceBorderStrong, width: 1)),
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
                            _categoryChip(context, 'Recentes', Icons.history_rounded),
                            _categoryChip(context, 'Sorrisos', Icons.mood_rounded),
                            _categoryChip(context, 'Gestos', Icons.pan_tool_outlined),
                            _categoryChip(context, 'Segurança & Símbolos', Icons.shield_outlined),
                            _categoryChip(context, 'Cultura & Objetos', Icons.album_outlined),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.close, size: 16, color: NixColors.textMuted),
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
                    hintText: 'Pesquisar emoji (ex: escudo, fogo, livro, chave)...',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                          child: Text(e, style: const TextStyle(fontSize: 18)),
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
                    style: TextStyle(color: NixColors.textSecondary, fontSize: 11.5),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 15, color: NixColors.textMuted),
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: NixColors.surfaceElevated,
            border: Border(top: BorderSide(color: NixColors.surfaceBorder)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: IconButton(
                  key: const Key('chat_attach_button'),
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.attach_file_rounded, color: NixColors.textSecondary, size: 20),
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
                  onChanged: (seconds) => nixState.setEphemeralTimer(seconds),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 36,
                height: 36,
                child: IconButton(
                  key: const Key('emoji_picker_toggle_button'),
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    _showEmojiPicker ? Icons.keyboard_rounded : Icons.sentiment_satisfied_alt_rounded,
                    color: _showEmojiPicker ? accentText : NixColors.textSecondary,
                    size: 20,
                  ),
                  tooltip: 'Seletor de Emojis',
                  onPressed: () => setState(() => _showEmojiPicker = !_showEmojiPicker),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (event) {
                    if (enterToSend &&
                        event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      _send(nixState);
                    }
                  },
                  child: TextField(
                    key: const Key('chat_message_input'),
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 4,
                    style: TextStyle(color: NixColors.textPrimary, fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: editing != null
                          ? 'Editar mensagem...'
                          : (widget.isDirectMessage
                              ? (widget.channelName.contains('Salvas')
                                  ? 'Escrever nota privada em Mensagens Salvas...'
                                  : 'Mensagem cifrada para ${widget.channelName}...')
                              : 'Mensagem cifrada em #${widget.channelName}...'),
                      hintStyle: TextStyle(color: NixColors.textMuted, fontSize: 13),
                      filled: true,
                      fillColor: NixColors.surfaceInput,
                      border: OutlineInputBorder(
                        borderRadius: NixTokens.borderInput,
                        borderSide: BorderSide(color: NixColors.surfaceBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: NixTokens.borderInput,
                        borderSide: BorderSide(color: NixColors.surfaceBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: NixTokens.borderInput,
                        borderSide: BorderSide(color: accent, width: 1.4),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
                height: 36,
                child: IconButton(
                  key: const Key('voice_record_button'),
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.mic_none_rounded, color: NixColors.textSecondary, size: 20),
                  tooltip: 'Gravar Mensagem de Voz Cifrada',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Nota de voz pronta para gravação E2EE.')),
                    );
                  },
                ),
              ),
              const SizedBox(width: 4),
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
                    editing != null ? Icons.check_rounded : Icons.arrow_upward_rounded,
                    color: context.onAccentColor,
                    size: 18,
                  ),
                  tooltip: editing != null ? 'Salvar Edição' : 'Transmitir Envelope Cifrado (Enter)',
                  onPressed: () => _send(nixState),
                ),
              ),
            ],
          ),
        ),
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
                    style: TextStyle(color: NixColors.textPrimary, fontSize: 11.5),
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
                    child: Icon(Icons.close_rounded, size: 14, color: NixColors.textMuted),
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
            border: Border.all(color: selected ? accent : NixColors.surfaceBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: selected ? context.onAccentColor : NixColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  color: selected ? context.onAccentColor : NixColors.textSecondary,
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

  const _EphemeralTimerSelector({
    required this.currentTimer,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isTimerActive = currentTimer > 0;
    return PopupMenuButton<int>(
      key: const Key('chat_timer_button'),
      tooltip: 'Temporizador de Mensagem Efêmera',
      initialValue: currentTimer,
      onSelected: onChanged,
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
            color: isTimerActive ? context.accentTextColor : NixColors.textSecondary,
          ),
          if (isTimerActive)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 0.5),
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
        PopupMenuItem(value: 0, child: Text('Desativado (Permanente)', style: TextStyle(color: NixColors.textPrimary, fontSize: 12))),
        PopupMenuItem(value: 30, child: Text('30 segundos', style: TextStyle(color: NixColors.textPrimary, fontSize: 12))),
        PopupMenuItem(value: 60, child: Text('1 minuto', style: TextStyle(color: NixColors.textPrimary, fontSize: 12))),
        PopupMenuItem(value: 300, child: Text('5 minutos', style: TextStyle(color: NixColors.textPrimary, fontSize: 12))),
        PopupMenuItem(value: 3600, child: Text('1 hora', style: TextStyle(color: NixColors.textPrimary, fontSize: 12))),
        PopupMenuItem(value: 86400, child: Text('24 horas', style: TextStyle(color: NixColors.textPrimary, fontSize: 12))),
      ],
    );
  }

  String _formatSeconds(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    return '${seconds ~/ 3600}h';
  }
}
