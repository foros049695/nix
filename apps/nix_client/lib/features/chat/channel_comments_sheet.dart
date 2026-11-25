import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/channel.dart';
import '../../core/models/message.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';
import 'chat_inline_format.dart';
import 'message_attachment_tile.dart';

/// Painel interativo de comentários de postagens em canais (Telegram Style).
/// Permite aos assinantes e membros discutirem tópicos específicos sem poluir a timeline principal.
class ChannelCommentsSheet extends StatefulWidget {
  final Channel channel;
  final Message message;

  const ChannelCommentsSheet({
    super.key,
    required this.channel,
    required this.message,
  });

  static Future<void> show(
    BuildContext context, {
    required Channel channel,
    required Message message,
  }) async {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 640) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ChannelCommentsSheet(channel: channel, message: message),
      );
    } else {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: Center(
            child: SizedBox(
              width: 580,
              height: 680,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ChannelCommentsSheet(channel: channel, message: message),
              ),
            ),
          ),
        ),
      );
    }
  }

  @override
  State<ChannelCommentsSheet> createState() => _ChannelCommentsSheetState();
}

class _ChannelCommentsSheetState extends State<ChannelCommentsSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendComment(NixState state) {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    final ok = state.sendMessage(text, replyTo: widget.message);
    if (ok) {
      _controller.clear();
      Future.delayed(const Duration(milliseconds: 150), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
    setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final accent = context.accentColor;
    final accentText = context.accentTextColor;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    final allChannelMsgs = nixState.messagesFor(widget.channel.id);
    final comments = allChannelMsgs
        .where((m) => m.replyToMessageId == widget.message.id)
        .toList();

    final allowComments = widget.channel.permissions.allowComments;

    return Container(
      decoration: BoxDecoration(
        color: NixColors.surfaceSidebar,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border.all(color: NixColors.surfaceBorderStrong),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          children: [
            // Cabeçalho do Painel
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: NixColors.surfaceCard,
                border: Border(bottom: BorderSide(color: NixColors.surfaceBorder)),
              ),
              child: Row(
                children: [
                  Icon(Icons.chat_bubble_outline_rounded, size: 20, color: accentText),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Comentários da Postagem',
                          style: TextStyle(
                            color: NixColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          comments.isEmpty
                              ? 'Discussão aberta'
                              : '${comments.length} ${comments.length == 1 ? 'comentário registrado' : 'comentários registrados'}',
                          style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: NixColors.textSecondary),
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Card Resumo da Postagem Original
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: NixColors.surfaceElevated.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: NixColors.surfaceBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 3.5,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.channel.name.isNotEmpty ? widget.channel.name : widget.message.senderName,
                          style: TextStyle(
                            color: accentText,
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.message.text.isNotEmpty
                              ? widget.message.text
                              : (widget.message.attachments.isNotEmpty ? '[Mídia anexada]' : ''),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: NixColors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.message.attachments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: MessageAttachmentTile(
                            message: widget.message,
                            index: 0,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Lista de Comentários
            Expanded(
              child: comments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.forum_outlined, size: 44, color: NixColors.textMuted.withValues(alpha: 0.6)),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhum comentário ainda',
                            style: TextStyle(
                              color: NixColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            allowComments
                                ? 'Seja o primeiro a participar da discussão!'
                                : 'Comentários foram desativados pelo administrador.',
                            style: TextStyle(color: NixColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      itemCount: comments.length,
                      itemBuilder: (context, index) {
                        final c = comments[index];
                        final isMyComment = c.isMe;
                        final hour = c.timestamp.hour.toString().padLeft(2, '0');
                        final minute = c.timestamp.minute.toString().padLeft(2, '0');

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isMyComment
                                ? accent.withValues(alpha: 0.12)
                                : NixColors.surfaceCard,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isMyComment
                                  ? accent.withValues(alpha: 0.3)
                                  : NixColors.surfaceBorder,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    c.senderName,
                                    style: TextStyle(
                                      color: isMyComment ? accentText : NixColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    c.senderFingerprint.length >= 8
                                        ? c.senderFingerprint.substring(0, 8)
                                        : c.senderFingerprint,
                                    style: TextStyle(
                                      color: NixColors.textMuted,
                                      fontSize: 9.5,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '$hour:$minute',
                                    style: TextStyle(color: NixColors.textMuted, fontSize: 10),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ChatInlineText(
                                c.text,
                                style: TextStyle(
                                  color: NixColors.textPrimary,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // Barra de Entrada de Comentários
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: NixColors.surfaceCard,
                border: Border(top: BorderSide(color: NixColors.surfaceBorder)),
              ),
              child: allowComments
                  ? Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: NixColors.background,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: NixColors.surfaceBorderStrong),
                            ),
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              minLines: 1,
                              maxLines: 4,
                              style: TextStyle(color: NixColors.textPrimary, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Escreva um comentário...',
                                hintStyle: TextStyle(color: NixColors.textMuted, fontSize: 13),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              onSubmitted: (_) => _sendComment(nixState),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          key: const Key('channel_comment_send_button'),
                          icon: Icon(Icons.send_rounded, color: accentText, size: 20),
                          tooltip: 'Enviar comentário',
                          onPressed: () => _sendComment(nixState),
                        ),
                      ],
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_outline_rounded, size: 14, color: NixColors.textMuted),
                          const SizedBox(width: 6),
                          Text(
                            'Comentários desativados pelo administrador deste canal.',
                            style: TextStyle(color: NixColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
