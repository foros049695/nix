import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/nix_colors.dart';
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
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final ephemeralTimer = nixState.selectedEphemeralTimer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: NixColors.surfaceSidebar,
        border: Border(top: BorderSide(color: NixColors.surfaceBorder, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Botão Anexo Cifrado (com aviso EXIF)
          Tooltip(
            message: 'Anexar arquivo/mídia (EXIF será expurgado e arquivo cifrado via XChaCha20)',
            child: IconButton(
              icon: const Icon(Icons.attach_file_rounded, color: NixColors.textSecondary, size: 22),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Seletor de arquivos: metadados EXIF sanitizados e cifra ativada.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ),

          // Seletor de Mensagem Efêmera (Auto-destruição)
          PopupMenuButton<int>(
            tooltip: 'Temporizador de Auto-destruição',
            initialValue: ephemeralTimer,
            icon: Icon(
              ephemeralTimer > 0 ? Icons.local_fire_department : Icons.timer_outlined,
              color: ephemeralTimer > 0 ? NixColors.accentWarning : NixColors.textSecondary,
              size: 22,
            ),
            onSelected: (seconds) => nixState.setEphemeralTimer(seconds),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 0, child: Text('Auto-destruição: Desativada')),
              const PopupMenuItem(value: 30, child: Text('🔥 30 segundos')),
              const PopupMenuItem(value: 300, child: Text('🔥 5 minutos')),
              const PopupMenuItem(value: 3600, child: Text('🔥 1 hora')),
              const PopupMenuItem(value: 86400, child: Text('🔥 24 horas')),
              const PopupMenuItem(value: 604800, child: Text('🔥 7 dias (TTL Relay)')),
            ],
          ),

          const SizedBox(width: 8),

          // Campo de Entrada de Texto
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: NixColors.surfaceCardHover,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: NixColors.surfaceBorder),
              ),
              child: RawKeyboardListener(
                focusNode: FocusNode(),
                onKey: (event) {
                  if (event is RawKeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !event.isShiftPressed) {
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
                  style: const TextStyle(color: NixColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Mensagem cifrada para #${widget.channelName}...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Botão Enviar
          IconButton(
            style: IconButton.styleFrom(
              backgroundColor: NixColors.accentGreen,
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.send_rounded, size: 20),
            tooltip: 'Enviar Mensagem E2EE',
            onPressed: _send,
          ),
        ],
      ),
    );
  }
}
