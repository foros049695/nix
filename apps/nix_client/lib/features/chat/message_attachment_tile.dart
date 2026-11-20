import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/message.dart';
import '../../core/security/local_image_helper.dart';
import '../../core/theme.dart';
import '../../state/nix_state.dart';

class MessageAttachmentTile extends StatefulWidget {
  const MessageAttachmentTile(
      {super.key, required this.message, required this.index});

  final Message message;
  final int index;

  @override
  State<MessageAttachmentTile> createState() => _MessageAttachmentTileState();
}

class _MessageAttachmentTileState extends State<MessageAttachmentTile> {
  Future<Uint8List?>? _imageBytes;

  String get _reference => widget.message.attachments[widget.index];
  String get _name => LocalImageHelper.getFileName(_reference);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(MessageAttachmentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.index != widget.index ||
        oldWidget.message.attachments[oldWidget.index] != _reference) {
      _imageBytes = null;
      _load();
    }
  }

  void _load() {
    if (_imageBytes != null || !LocalImageHelper.isSupportedExtension(_name))
      return;
    _imageBytes =
        context.read<NixState>().readMessageImage(widget.message, widget.index);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.nixScheme;
    return FutureBuilder<Uint8List?>(
      future: _imageBytes,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        Widget image({bool thumbnail = true}) => Image.memory(
              bytes!,
              fit: BoxFit.contain,
              cacheWidth: thumbnail ? 480 : 1024,
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.broken_image_outlined),
              ),
            );
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 310),
          child: DecoratedBox(
            decoration: BoxDecoration(
                color: scheme.surfaceElevated,
                borderRadius: BorderRadius.circular(8)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (bytes != null)
                    InkWell(
                      key: ValueKey(
                          'message_image_${widget.message.id}_${widget.index}'),
                      onTap: () => showDialog<void>(
                          context: context,
                          builder: (dialog) => Dialog(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                          title: Text(_name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis),
                                          trailing: IconButton(
                                              icon: const Icon(Icons.close),
                                              tooltip: 'Fechar imagem',
                                              onPressed: () =>
                                                  Navigator.pop(dialog))),
                                      Flexible(
                                          child: InteractiveViewer(
                                              child: image(thumbnail: false))),
                                    ]),
                              )),
                      child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8)),
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 200),
                              child: image())),
                    ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                          LocalImageHelper.isSupportedExtension(_name)
                              ? Icons.image_outlined
                              : Icons.attach_file,
                          size: 14,
                          color: context.accentTextColor),
                      const SizedBox(width: 5),
                      Flexible(
                          child: Tooltip(
                              message: _name,
                              child: Text(_name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11)))),
                    ]),
                  ),
                ]),
          ),
        );
      },
    );
  }
}
