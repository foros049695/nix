import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'external_link_dialog.dart';

enum ChatInlineFormat {
  bold('Negrito', '**'),
  italic('Itálico', '_'),
  strike('Tachado', '~~'),
  monospace('Monoespaçado', '`');

  const ChatInlineFormat(this.label, this.delimiter);

  final String label;
  final String delimiter;

  TextEditingValue? apply(TextEditingValue value) {
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
    if (body.contains(delimiter)) {
      return null;
    }
    return value.copyWith(
      text: value.text.replaceRange(start, end, '$delimiter$body$delimiter'),
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
  static final _marker = RegExp(
    r'[*_`~]|https?://|[a-z0-9]+\.onion|\[.*?\]\(.*?\)',
    caseSensitive: false,
  );

  static List<InlineSpan> _parseTextWithUrls(BuildContext context, String text) {
    final spans = <InlineSpan>[];
    final matches = _urlRegex.allMatches(text);
    if (matches.isEmpty) {
      return [TextSpan(text: text)];
    }

    var lastIndex = 0;
    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }
      final url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: const TextStyle(
            color: Color(0xFF64B5F6),
            decoration: TextDecoration.underline,
            decorationColor: Color(0xFF64B5F6),
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
      spans.add(TextSpan(text: text.substring(lastIndex)));
    }
    return spans;
  }

  static List<InlineSpan>? _spans(BuildContext context, List<md.Node> nodes) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node is md.Text) {
        spans.addAll(_parseTextWithUrls(context, node.text));
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
        'del' => const TextStyle(decoration: TextDecoration.lineThrough),
        'code' => const TextStyle(fontFamily: 'monospace'),
        _ => null,
      };

      final children = _spans(context, node.children ?? const []);
      if (children != null) {
        spans.add(TextSpan(style: elemStyle, children: children));
      } else {
        spans.addAll(_parseTextWithUrls(context, node.textContent));
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
