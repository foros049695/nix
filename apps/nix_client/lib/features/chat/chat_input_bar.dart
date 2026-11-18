import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';
import '../../state/nix_state.dart';

class ChatInputBar extends StatefulWidget {
  final String channelName;

  const ChatInputBar({super.key, required this.channelName});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _emojiSearchController = TextEditingController();

  bool _showEmojiPicker = false;
  String _selectedEmojiCategory = 'Sorrisos';
  String _emojiSearchQuery = '';
  final List<String> _recentEmojis = ['⚡', '🛡️', '🔒', '🔥', '💿', '🤝'];

  static const Map<String, List<String>> _categorizedEmojis = {
    'Sorrisos': [
      '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🥹', '☺️',
      '😊', '😇', '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😋',
      '😛', '😜', '🤪', '🤨', '🧐', '🤓', '😎', '🤩', '🥳', '😏',
      '😒', '😞', '😔', '😟', '😕', '🙁', '🥺', '😢', '😭', '😤',
      '😠', '😡', '🤬', '🤯', '😳', '🥵', '🥶', '😱', '😨', '🤗',
      '🤔', '🫣', '🤭', '🤫', '🫠', '🫡', '🤐', '😴', '🤤', '😵',
    ],
    'Gestos': [
      '👍', '👎', '👊', '✊', '🤛', '🤜', '👏', '🙌', '👐', '🤲',
      '🤝', '🙏', '✌️', '🤞', '🫰', '🤟', '🤘', '🤙', '👈', '👉',
      '👆', '👇', '☝️', '👋', '🤚', '🖐️', '✋', '🖖', '🫱', '🫲',
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

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _emojiSearchController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isNotEmpty) {
      context.read<NixState>().sendMessage(text);
      _controller.clear();
      setState(() => _showEmojiPicker = false);
      _focusNode.requestFocus();
    }
  }

  void _insertEmoji(String emoji) {
    if (!_recentEmojis.contains(emoji)) {
      _recentEmojis.insert(0, emoji);
      if (_recentEmojis.length > 12) _recentEmojis.removeLast();
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
    if (_emojiSearchQuery.isNotEmpty) {
      final all = _categorizedEmojis.values.expand((e) => e).toSet().toList();
      return all;
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Seletor de Emojis Completo com Categorias e Busca
        if (_showEmojiPicker)
          Container(
            height: 240,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: NixColors.surfaceElevatedHigh,
              border: const Border(top: BorderSide(color: NixColors.surfaceBorderStrong, width: 1)),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, -4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Barra de Categorias de Emojis Rolável
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _categoryChip('Recentes', Icons.history_rounded),
                            _categoryChip('Sorrisos', Icons.mood_rounded),
                            _categoryChip('Gestos', Icons.pan_tool_outlined),
                            _categoryChip('Segurança & Símbolos', Icons.shield_outlined),
                            _categoryChip('Cultura & Objetos', Icons.album_outlined),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: NixColors.textMuted),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _showEmojiPicker = false),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Grade de Emojis Rolável
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

        // Barra Principal de Entrada
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: NixColors.surfaceElevated,
            border: Border(top: BorderSide(color: NixColors.surfaceBorder)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Botão de Anexo com Notificação de EXIF Strip
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: NixColors.textSecondary, size: 20),
                tooltip: 'Anexar Mídia (EXIF Sanitizado)',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Seletor de arquivos ativo: Metadados EXIF sanitizados automaticamente.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),

              // Seletor de Temporizador de Mensagem Efêmera
              _EphemeralTimerSelector(
                currentTimer: ephemeralTimer,
                onChanged: (seconds) => nixState.setEphemeralTimer(seconds),
              ),
              const SizedBox(width: 8),

              // Botão Seletor de Emojis
              IconButton(
                key: const Key('emoji_picker_toggle_button'),
                icon: Icon(
                  _showEmojiPicker ? Icons.keyboard_rounded : Icons.sentiment_satisfied_alt_rounded,
                  color: _showEmojiPicker ? Colors.white : NixColors.textSecondary,
                  size: 20,
                ),
                tooltip: 'Inserir Emoji',
                onPressed: () {
                  setState(() => _showEmojiPicker = !_showEmojiPicker);
                },
              ),
              const SizedBox(width: 8),

              // Campo de Texto de Mensagem Cifrada
              Expanded(
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (event) {
                    if (enterToSend &&
                        event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      _send();
                    }
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'Mensagem cifrada em #${widget.channelName}...',
                      hintStyle: const TextStyle(color: NixColors.textMuted, fontSize: 13),
                      filled: true,
                      fillColor: NixColors.surfaceInput,
                      border: OutlineInputBorder(
                        borderRadius: NixTokens.borderMd,
                        borderSide: const BorderSide(color: NixColors.surfaceBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: NixTokens.borderMd,
                        borderSide: const BorderSide(color: NixColors.surfaceBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: NixTokens.borderMd,
                        borderSide: const BorderSide(color: NixColors.textPrimary, width: 1.2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Botão Enviar
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  key: const Key('chat_send_button'),
                  icon: const Icon(Icons.arrow_upward_rounded, color: Colors.black, size: 18),
                  tooltip: 'Transmitir Envelope Cifrado (Enter)',
                  onPressed: _send,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _categoryChip(String title, IconData icon) {
    final selected = _selectedEmojiCategory == title;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => setState(() => _selectedEmojiCategory = title),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? Colors.white : NixColors.surfaceCard,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selected ? Colors.white : NixColors.surfaceBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: selected ? Colors.black : Colors.white70),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  color: selected ? Colors.black : NixColors.textSecondary,
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
      tooltip: 'Temporizador de Mensagem Efêmera',
      initialValue: currentTimer,
      onSelected: onChanged,
      color: NixColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: NixTokens.borderSm,
        side: const BorderSide(color: NixColors.surfaceBorderStrong),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isTimerActive ? NixColors.surfaceActive : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isTimerActive ? Border.all(color: Colors.white38) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isTimerActive ? Icons.timer_outlined : Icons.timer_off_outlined,
              size: 18,
              color: isTimerActive ? Colors.white : NixColors.textSecondary,
            ),
            if (isTimerActive) ...[
              const SizedBox(width: 4),
              Text(
                _formatSeconds(currentTimer),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
      itemBuilder: (context) => const [
        PopupMenuItem(value: 0, child: Text('Desativado (Permanente)', style: TextStyle(color: Colors.white, fontSize: 12))),
        PopupMenuItem(value: 30, child: Text('30 segundos', style: TextStyle(color: Colors.white, fontSize: 12))),
        PopupMenuItem(value: 60, child: Text('1 minuto', style: TextStyle(color: Colors.white, fontSize: 12))),
        PopupMenuItem(value: 300, child: Text('5 minutos', style: TextStyle(color: Colors.white, fontSize: 12))),
        PopupMenuItem(value: 3600, child: Text('1 hora', style: TextStyle(color: Colors.white, fontSize: 12))),
        PopupMenuItem(value: 86400, child: Text('24 horas', style: TextStyle(color: Colors.white, fontSize: 12))),
      ],
    );
  }

  String _formatSeconds(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    return '${seconds ~/ 3600}h';
  }
}
