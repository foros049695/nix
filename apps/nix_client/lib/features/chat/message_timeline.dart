import 'package:flutter/material.dart';

import '../../core/models/message.dart';
import 'message_bubble.dart';

class MessageTimeline extends StatefulWidget {
  const MessageTimeline({
    super.key,
    required this.messages,
    this.highlightedMessageId,
  });

  final List<Message> messages;
  final String? highlightedMessageId;

  @override
  State<MessageTimeline> createState() => _MessageTimelineState();
}

class _MessageTimelineState extends State<MessageTimeline> {
  final _controller = ScrollController();
  String? _tailId;

  @override
  void initState() {
    super.initState();
    _tailId = widget.messages.lastOrNull?.id;
  }

  @override
  void didUpdateWidget(MessageTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final highlighted = widget.highlightedMessageId;
    final latest = widget.messages.lastOrNull;
    final wasAtBottom = !_controller.hasClients || _controller.offset <= 72;
    final hasNewMessage = latest?.id != _tailId;
    _tailId = latest?.id;

    if (highlighted != null && highlighted != oldWidget.highlightedMessageId) {
      final reverseIndex = widget.messages.reversed.toList().indexWhere(
            (message) => message.id == highlighted,
          );
      if (reverseIndex >= 0) {
        _afterLayout((position) {
          final fraction = reverseIndex /
              (widget.messages.length - 1).clamp(1, double.infinity);
          return position.maxScrollExtent * fraction;
        });
      }
    } else if (hasNewMessage &&
        latest != null &&
        (latest.isMe || wasAtBottom)) {
      _afterLayout((position) => position.minScrollExtent);
    }
  }

  void _afterLayout(double Function(ScrollPosition position) target) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final offset = target(_controller.position);
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.jumpTo(offset);
      } else {
        _controller.animateTo(offset,
            duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
        controller: _controller,
        reverse: true,
        padding: const EdgeInsets.all(16),
        itemCount: widget.messages.length,
        itemBuilder: (context, index) {
          final message = widget.messages[widget.messages.length - index - 1];
          return MessageBubble(key: ValueKey(message.id), message: message);
        },
      );
}
