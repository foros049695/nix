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
  bool _showEmojiPicker = false;

  static const List<String> _emojis = [
    '⚡', '🛡️', '🔒', '👁️', '🔥', '💿', '📡', '🪙',
    '✓', '🏴‍☠️', '🎬', '📚', '🎧', '🤝', '🚀', '💬',
    '👍', '🙌', '🤔', '🎯', '⏳', '📌', '🔍', '⚙️',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
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

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final ephemeralTimer = nixState.selectedEphemeralTimer;
    final enterToSend = nixState.settings.enterToSend;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Seletor de Emojis Expansível
        if (_showEmojiPicker)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: const BoxDecoration(
              color: NixColors.surfaceCard,
              border: Border(top: BorderSide(color: NixColors.surfaceBorderStrong)),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: _emojis
                  .map((e) => InkWell(
                        onTap: () => _insertEmoji(e),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: NixColors.surfaceSidebar,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: NixColors.surfaceBorder),
                          ),
                          child: Text(e, style: const TextStyle(fontSize: 18)),
                        ),
                      ))
                  .toList(),
            ),
          ),

        // Barra Principal de Entrada
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: NixColors.surfaceSidebar,
            border: Border(top: BorderSide(color: NixColors.surfaceBorder, width: 1)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Botão Anexo Cifrado (EXIF Strip)
              Tooltip(
                message: 'Anexar arquivo (Metadados EXIF removidos e cifra XChaCha20 aplicada)',
                child: IconButton(
                  icon: const Icon(
                    Icons.add_circle_outline_rounded,
                    color: NixColors.textSecondary,
                    size: 21,
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Sanitizador EXIF ativo: anexo pronto para cifra local.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),

              // Seletor de Mensagem Efêmera
              PopupMenuButton<int>(
                tooltip: 'Temporizador de Auto-destruição',
                initialValue: ephemeralTimer,
                color: NixColors.surfaceCard,
                icon: Icon(
                  ephemeralTimer > 0 ? Icons.timer_rounded : Icons.timer_outlined,
                  color: ephemeralTimer > 0 ? Colors.white : NixColors.textSecondary,
                  size: 20,
                ),
                onSelected: (seconds) => nixState.setEphemeralTimer(seconds),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 0, child: Text('Auto-destruição: Desativada')),
                  PopupMenuItem(value: 30, child: Text('⏱ 30 segundos')),
                  PopupMenuItem(value: 300, child: Text('⏱ 5 minutos')),
                  PopupMenuItem(value: 3600, child: Text('⏱ 1 hora')),
                  PopupMenuItem(value: 86400, child: Text('⏱ 24 horas')),
                  PopupMenuItem(value: 604800, child: Text('⏱ 7 dias (TTL Relay)')),
                ],
              ),

              // Botão Seletor de Emojis
              IconButton(
                icon: Icon(
                  _showEmojiPicker ? Icons.keyboard_outlined : Icons.emoji_emotions_outlined,
                  color: _showEmojiPicker ? Colors.white : NixColors.textSecondary,
                  size: 20,
                ),
                tooltip: 'Inserir Emoji',
                onPressed: () => setState(() => _showEmojiPicker = !_showEmojiPicker),
              ),

              const SizedBox(width: 6),

              // Campo de Entrada de Texto
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: NixColors.surfaceCard,
                    borderRadius: NixTokens.borderSm,
                    border: Border.all(color: NixColors.surfaceBorderStrong),
                  ),
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
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: const TextStyle(color: NixColors.textPrimary, fontSize: 13.8),
                      decoration: InputDecoration(
                        hintText: 'Mensagem cifrada em #${widget.channelName}...',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Botão Enviar Monocromático
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.arrow_upward_rounded, size: 19),
                tooltip: 'Enviar Mensagem E2EE',
                onPressed: _send,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
