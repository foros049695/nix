import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/models/channel.dart';
import '../../state/nix_state.dart';
import 'message_header.dart';
import 'message_bubble.dart';
import 'chat_input_bar.dart';

class ChatView extends StatefulWidget {
  final Channel channel;

  const ChatView({super.key, required this.channel});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final messages = nixState.currentMessages;

    _scrollToBottom();

    return Column(
      children: [
        // Cabeçalho do Canal
        MessageHeader(channel: widget.channel),

        // Área Central: Lista de Mensagens
        Expanded(
          child: Container(
            color: NixColors.background,
            child: messages.isEmpty
                ? _buildEmptyChat()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return MessageBubble(message: msg);
                    },
                  ),
          ),
        ),

        // Barra Inferior de Entrada
        ChatInputBar(channelName: widget.channel.name),
      ],
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.channel.icon, size: 48, color: NixColors.textMuted),
          const SizedBox(height: 12),
          Text(
            'Início de #${widget.channel.name}',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Este tópico é protegido com Double Ratchet e tráfego Onion v3.',
            style: TextStyle(color: NixColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
