import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import '../../core/rich_text/nix_rich_text_controller.dart';
import 'external_link_dialog.dart';

enum ChatInlineFormat {
  bold('Negrito', '**'),
  italic('Itálico', '_'),
  underline('Sublinhado', '<u>'),
  strike('Tachado', '~~'),
  monospace('Monoespaçado', '`'),
  spoiler('Spoiler', '||'),
  quote('Citação', '> '),
  link('Link', '');

  const ChatInlineFormat(this.label, this.delimiter);

  final String label;
  final String delimiter;

  TextEditingValue? apply(TextEditingValue value) {
    if (this == ChatInlineFormat.link) return null;
    final selection = value.selection;
    if (!selection.isValid ||
        selection.isCollapsed ||
        selection.end > value.text.length) {
      return null;
    }
    final selected = selection.textInside(value.text);
    final body = selected.trim();
    if (body.isEmpty || body.contains('\n')) {
      return null;
    }
    final start = selection.start + selected.indexOf(body);
    final end = start + body.length;
    if (delimiter.isNotEmpty && body.contains(delimiter)) {
      return null;
    }
    final closeTag = delimiter == '<u>' ? '</u>' : (delimiter == '> ' ? '' : delimiter);
    return value.copyWith(
      text: value.text.replaceRange(start, end, '$delimiter$body$closeTag'),
      selection: TextSelection(
        baseOffset: start + delimiter.length,
        extentOffset: end + delimiter.length,
      ),
      composing: TextRange.empty,
    );
  }
}

Widget buildChatFormatMenu(BuildContext context, EditableTextState editable) {
  final items = editable.contextMenuButtonItems;
  final controller = editable.widget.controller;

  if (controller is NixRichTextController) {
    final sel = controller.selection;
    final hasSelection = sel.isValid && !sel.isCollapsed && sel.end <= controller.text.length;

    final formatButtons = <ContextMenuButtonItem>[];
    if (hasSelection) {
      formatButtons.addAll([
        ContextMenuButtonItem(
          label: 'Negrito',
          onPressed: () {
            controller.toggleBold();
            editable.hideToolbar();
          },
        ),
        ContextMenuButtonItem(
          label: 'Itálico',
          onPressed: () {
            controller.toggleItalic();
            editable.hideToolbar();
          },
        ),
        ContextMenuButtonItem(
          label: 'Sublinhado',
          onPressed: () {
            controller.toggleUnderline();
            editable.hideToolbar();
          },
        ),
        ContextMenuButtonItem(
          label: 'Tachado',
          onPressed: () {
            controller.toggleStrikethrough();
            editable.hideToolbar();
          },
        ),
        ContextMenuButtonItem(
          label: 'Monoespaçado',
          onPressed: () {
            controller.toggleMonospace();
            editable.hideToolbar();
          },
        ),
        ContextMenuButtonItem(
          label: 'Spoiler',
          onPressed: () {
            controller.toggleSpoiler();
            editable.hideToolbar();
          },
        ),
        ContextMenuButtonItem(
          label: 'Citação',
          onPressed: () {
            controller.toggleBlockquote();
            editable.hideToolbar();
          },
        ),
        ContextMenuButtonItem(
          label: 'Link',
          onPressed: () async {
            editable.hideToolbar();
            final urlCtrl = TextEditingController(text: 'https://');
            final result = await showDialog<bool>(
              context: context,
              builder: (dialog) => AlertDialog(
                title: const Text('Inserir Link'),
                content: TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(labelText: 'URL (https:// ou onion://)'),
                  autofocus: true,
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancelar')),
                  FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Aplicar')),
                ],
              ),
            );
            if (result == true && urlCtrl.text.trim().isNotEmpty) {
              controller.setLink(urlCtrl.text.trim());
            }
          },
        ),
      ]);
    }

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editable.contextMenuAnchors,
      buttonItems: [
        ...items,
        ...formatButtons,
      ],
    );
  }

  final value = editable.textEditingValue;
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editable.contextMenuAnchors,
    buttonItems: [
      ...items,
      for (final format in ChatInlineFormat.values)
        if (format.apply(value) != null)
          ContextMenuButtonItem(
            label: format.label,
            onPressed: () {
              final updated = format.apply(editable.textEditingValue);
              if (updated != null) {
                editable.userUpdateTextEditingValue(
                    updated, SelectionChangedCause.toolbar);
              }
              editable.hideToolbar();
            },
          ),
    ],
  );
}

class ChatSpoilerText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  const ChatSpoilerText({required this.text, this.style, super.key});

  @override
  State<ChatSpoilerText> createState() => _ChatSpoilerTextState();
}

class _ChatSpoilerTextState extends State<ChatSpoilerText> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _revealed = !_revealed),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: _revealed ? Colors.white.withOpacity(0.08) : const Color(0xFF333B4D),
          borderRadius: BorderRadius.circular(4),
        ),
        child: _revealed
            ? Text(widget.text, style: widget.style)
            : Text(
                '•' * widget.text.length,
                style: (widget.style ?? const TextStyle()).copyWith(
                  color: const Color(0xFF94A3B8),
                  letterSpacing: 2,
                ),
              ),
      ),
    );
  }
}

class ChatInlineText extends StatelessWidget {
  const ChatInlineText(this.source, {required this.style, super.key});

  final String source;
  final TextStyle style;

  static final _document = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  static final _urlRegex = RegExp(
    r'(https?://[^\s<>]+|[a-z0-9]{16,56}\.onion(/[^\s<>]*)?)',
    caseSensitive: false,
  );
  static final _spoilerRegex = RegExp(r'\|\|(.*?)\|\|');
  static final _marker = RegExp(
    r'[*_`~]|https?://|[a-z0-9]+\.onion|\[.*?\]\(.*?\)|\<\/?(u|ins)\>|\|\||>',
    caseSensitive: false,
  );

  static List<InlineSpan> _parseTextWithUrls(BuildContext context, String text, [TextStyle? baseStyle]) {
    final spans = <InlineSpan>[];

    // Verifica se há spoilers inline no texto
    final spoilerMatches = _spoilerRegex.allMatches(text);
    if (spoilerMatches.isNotEmpty) {
      var lastSpoilerIdx = 0;
      for (final sm in spoilerMatches) {
        if (sm.start > lastSpoilerIdx) {
          spans.addAll(_parseUrlsOnly(context, text.substring(lastSpoilerIdx, sm.start), baseStyle));
        }
        final spoilerContent = sm.group(1) ?? '';
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: ChatSpoilerText(text: spoilerContent, style: baseStyle),
          ),
        );
        lastSpoilerIdx = sm.end;
      }
      if (lastSpoilerIdx < text.length) {
        spans.addAll(_parseUrlsOnly(context, text.substring(lastSpoilerIdx), baseStyle));
      }
      return spans;
    }

    return _parseUrlsOnly(context, text, baseStyle);
  }

  static List<InlineSpan> _parseUrlsOnly(BuildContext context, String text, [TextStyle? baseStyle]) {
    final spans = <InlineSpan>[];
    final matches = _urlRegex.allMatches(text);
    if (matches.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }

    var lastIndex = 0;
    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start), style: baseStyle));
      }
      final url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: (baseStyle ?? const TextStyle()).copyWith(
            color: const Color(0xFF64B5F6),
            decoration: TextDecoration.underline,
            decorationColor: const Color(0xFF64B5F6),
            fontWeight: FontWeight.w600,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => ExternalLinkDialog.show(context, url),
          mouseCursor: SystemMouseCursors.click,
        ),
      );
      lastIndex = match.end;
    }
    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex), style: baseStyle));
    }
    return spans;
  }

  static List<InlineSpan>? _spans(BuildContext context, List<md.Node> nodes, [TextStyle? currentStyle]) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node is md.Text) {
        spans.addAll(_parseTextWithUrls(context, node.text, currentStyle));
        continue;
      }
      if (node is! md.Element) continue;

      if (node.tag == 'a') {
        final href = node.attributes['href'] ?? '';
        final label = node.textContent.isNotEmpty ? node.textContent : href;
        spans.add(
          TextSpan(
            text: label,
            style: const TextStyle(
              color: Color(0xFF64B5F6),
              decoration: TextDecoration.underline,
              decorationColor: Color(0xFF64B5F6),
              fontWeight: FontWeight.w600,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => ExternalLinkDialog.show(context, href),
            mouseCursor: SystemMouseCursors.click,
          ),
        );
        continue;
      }

      final elemStyle = switch (node.tag) {
        'strong' => const TextStyle(fontWeight: FontWeight.bold),
        'em' => const TextStyle(fontStyle: FontStyle.italic),
        'u' || 'ins' => const TextStyle(decoration: TextDecoration.underline),
        'del' => const TextStyle(decoration: TextDecoration.lineThrough),
        'code' => const TextStyle(fontFamily: 'monospace'),
        'blockquote' => const TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF94A3B8)),
        _ => null,
      };

      final mergedStyle = (currentStyle != null && elemStyle != null)
          ? currentStyle.merge(elemStyle)
          : (elemStyle ?? currentStyle);

      final children = _spans(context, node.children ?? const [], mergedStyle);
      if (children != null) {
        spans.add(TextSpan(style: elemStyle, children: children));
      } else {
        spans.addAll(_parseTextWithUrls(context, node.textContent, mergedStyle));
      }
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    if (source.length > 16000 || !_marker.hasMatch(source)) {
      return Text(source, style: style);
    }
    final nodes = _document.parseInline(source);
    if (nodes.any((node) => node is md.Element && node.tag == 'img')) {
      return Text(source, style: style);
    }
    final formatted = _spans(context, nodes);
    if (formatted == null || formatted.isEmpty) return Text(source, style: style);
    return Text.rich(TextSpan(children: formatted), style: style);
  }
}
