import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../core/theme.dart';

/// Mostra a árvore local do documento com widgets de texto. A leitura não
/// instancia uma WebView nem carrega imagens, URLs ou scripts.
class ArchiveDocument extends StatelessWidget {
  final String source;

  const ArchiveDocument({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    final fragment = html.parseFragment(source);
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _blocks(context, fragment.nodes),
      ),
    );
  }

  static const _headings = {'h1': 24.0, 'h2': 21.0, 'h3': 18.0, 'h4': 16.0};
  static const _forbidden = {
    'script',
    'style',
    'iframe',
    'img',
    'video',
    'audio',
    'object'
  };

  List<Widget> _blocks(BuildContext context, List<dom.Node> nodes,
      [int depth = 0]) {
    if (depth >= 12) return [_paragraph(context, nodes)];
    return [
      for (final node in nodes)
        if (node is dom.Element && !_forbidden.contains(node.localName))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _block(context, node, depth),
          )
        else if (node is dom.Text && node.data.trim().isNotEmpty)
          _paragraph(context, [node]),
    ];
  }

  Widget _block(BuildContext context, dom.Element node, int depth) {
    final name = node.localName;
    final heading = _headings[name];
    if (heading != null) {
      return _paragraph(context, node.nodes,
          style: TextStyle(fontSize: heading, fontWeight: FontWeight.bold));
    }
    switch (name) {
      case 'ul':
      case 'ol':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, item) in node.children.indexed)
              if (item.localName == 'li')
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name == 'ol' ? '${index + 1}. ' : '• '),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _blocks(context, item.nodes, depth + 1),
                      )),
                    ],
                  ),
                ),
          ],
        );
      case 'blockquote':
        return DecoratedBox(
          decoration: BoxDecoration(
            border:
                Border(left: BorderSide(color: context.accentColor, width: 3)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _blocks(context, node.nodes, depth + 1),
            ),
          ),
        );
      case 'pre':
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _paragraph(context, node.nodes,
                style: const TextStyle(fontFamily: 'monospace')),
          ),
        );
      case 'table':
        return _table(context, node);
      case 'hr':
        return const Divider();
      default:
        return _paragraph(context, name == 'a' ? [node] : node.nodes);
    }
  }

  Widget _table(BuildContext context, dom.Element node) {
    final rows = node.querySelectorAll('tr');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Row(
              children: [
                for (final cell in row.children)
                  if (cell.localName == 'td' || cell.localName == 'th')
                    Container(
                      width: 152,
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: _paragraph(context, cell.nodes,
                          style: TextStyle(
                            fontWeight:
                                cell.localName == 'th' ? FontWeight.bold : null,
                          )),
                    ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _paragraph(BuildContext context, List<dom.Node> nodes,
          {TextStyle? style}) =>
      Text.rich(
        TextSpan(children: [
          for (final node in nodes) _inline(context, node),
        ]),
        style: DefaultTextStyle.of(context)
            .style
            .copyWith(height: 1.45)
            .merge(style),
      );

  InlineSpan _inline(BuildContext context, dom.Node node, [int depth = 0]) {
    if (node is dom.Text) return TextSpan(text: node.data);
    if (node is! dom.Element || _forbidden.contains(node.localName)) {
      return const TextSpan();
    }
    if (depth >= 12) return TextSpan(text: node.text);
    final tag = node.localName;
    if (tag == 'br') return const TextSpan(text: '\n');
    if (tag == 'a') {
      final href = Uri.tryParse(node.attributes['href'] ?? '');
      if (href != null &&
          (href.scheme == 'https' || href.scheme == 'http') &&
          href.host.isNotEmpty &&
          href.userInfo.isEmpty) {
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Tooltip(
            message: 'Copiar endereço do link',
            child: TextButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: href.toString())),
              child: Text(node.text.isEmpty ? href.host : node.text),
            ),
          ),
        );
      }
    }
    final style = switch (tag) {
      'b' || 'strong' => const TextStyle(fontWeight: FontWeight.bold),
      'i' || 'em' => const TextStyle(fontStyle: FontStyle.italic),
      'u' => const TextStyle(decoration: TextDecoration.underline),
      's' || 'del' => const TextStyle(decoration: TextDecoration.lineThrough),
      'code' => const TextStyle(fontFamily: 'monospace'),
      _ => null,
    };
    return TextSpan(
      style: style,
      children: [
        for (final child in node.nodes) _inline(context, child, depth + 1)
      ],
    );
  }
}
