import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

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
        selection.end > value.text.length) return null;
    final selected = selection.textInside(value.text);
    final body = selected.trim();
    if (body.isEmpty || body.contains('\n')) return null;
    final start = selection.start + selected.indexOf(body);
    final end = start + body.length;
    if (body.contains(delimiter)) return null;
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
  static final _marker = RegExp(r'[*_`~]');

  static InlineSpan? _span(md.Node node) {
    if (node is md.Text) return TextSpan(text: node.text);
    if (node is! md.Element) return null;
    final style = switch (node.tag) {
      'strong' => const TextStyle(fontWeight: FontWeight.bold),
      'em' => const TextStyle(fontStyle: FontStyle.italic),
      'del' => const TextStyle(decoration: TextDecoration.lineThrough),
      'code' => const TextStyle(fontFamily: 'monospace'),
      _ => null,
    };
    if (style == null) return null;
    final children = _spans(node.children ?? const []);
    return children == null ? null : TextSpan(style: style, children: children);
  }

  static List<InlineSpan>? _spans(List<md.Node> nodes) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      final span = _span(node);
      if (span == null) return null;
      spans.add(span);
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    // Mantém textos comuns, URLs, HTML e entradas grandes no renderer de texto simples.
    if (source.length > 16000 || !_marker.hasMatch(source)) {
      return Text(source, style: style);
    }
    final nodes = _document.parseInline(source);
    if (!nodes.any((node) => node is md.Element))
      return Text(source, style: style);
    final formatted = _spans(nodes);
    if (formatted == null) return Text(source, style: style);
    return Text.rich(TextSpan(children: formatted), style: style);
  }
}
