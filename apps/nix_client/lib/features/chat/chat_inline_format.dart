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

  static final _urlRegex = RegExp(
    r'(https?://[^\s<>]+|[a-z0-9]{16,56}\.onion(/[^\s<>]*)?)',
    caseSensitive: false,
  );
  static final _underlineRegex = RegExp(r'<(u|ins)>(.*?)</\1>', caseSensitive: false, dotAll: true);
  static final _spoilerRegex = RegExp(r'\|\|(.*?)\|\|', dotAll: true);

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

  static List<InlineSpan> _parseUnderlines(BuildContext context, String text, [TextStyle? baseStyle]) {
    final spans = <InlineSpan>[];
    final matches = _underlineRegex.allMatches(text);
    if (matches.isEmpty) {
      return _parseUrlsOnly(context, text, baseStyle);
    }

    var lastIndex = 0;
    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.addAll(_parseUrlsOnly(context, text.substring(lastIndex, match.start), baseStyle));
      }
      final inner = match.group(2) ?? '';
      final underStyle = (baseStyle ?? const TextStyle()).copyWith(
        decoration: TextDecoration.underline,
        decorationColor: baseStyle?.color ?? Colors.white,
      );
      spans.addAll(_parseUrlsOnly(context, inner, underStyle));
      lastIndex = match.end;
    }
    if (lastIndex < text.length) {
      spans.addAll(_parseUrlsOnly(context, text.substring(lastIndex), baseStyle));
    }
    return spans;
  }

  static List<InlineSpan> _parseTextWithUrls(BuildContext context, String text, [TextStyle? baseStyle]) {
    final spans = <InlineSpan>[];

    // 1. Spoilers inline
    final spoilerMatches = _spoilerRegex.allMatches(text);
    if (spoilerMatches.isNotEmpty) {
      var lastSpoilerIdx = 0;
      for (final sm in spoilerMatches) {
        if (sm.start > lastSpoilerIdx) {
          spans.addAll(_parseUnderlines(context, text.substring(lastSpoilerIdx, sm.start), baseStyle));
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
        spans.addAll(_parseUnderlines(context, text.substring(lastSpoilerIdx), baseStyle));
      }
      return spans;
    }

    return _parseUnderlines(context, text, baseStyle);
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
        'code' => const TextStyle(fontFamily: 'monospace', backgroundColor: Color(0x33A855F7), color: Color(0xFFF472B6)),
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

  static List<InlineSpan> _parseInlineContent(BuildContext context, String content, TextStyle baseStyle) {
    final doc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored, encodeHtml: false);
    final nodes = doc.parseInline(content);
    return _spans(context, nodes, baseStyle) ?? [TextSpan(text: content, style: baseStyle)];
  }

  @override
  Widget build(BuildContext context) {
    if (source.length > 16000) {
      return Text(source, style: style);
    }

    final doc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored, encodeHtml: false);
    final probeNodes = doc.parseInline(source);
    if (probeNodes.any((node) => node is md.Element && node.tag == 'img')) {
      return Text(source, style: style);
    }

    // Detecta se a mensagem possui linhas de citação (> texto ou | texto)
    final lines = source.split('\n');
    final hasQuoteLines = lines.any((l) => l.trimLeft().startsWith('>') || l.trimLeft().startsWith('| '));

    if (!hasQuoteLines) {
      final spans = _parseInlineContent(context, source, style);
      return Text.rich(TextSpan(children: spans), style: style);
    }

    // Agrupa linhas em blocos: texto comum vs bloco de citação estilizado
    final widgets = <Widget>[];
    final currentTextLines = <String>[];
    final currentQuoteLines = <String>[];

    void flushText() {
      if (currentTextLines.isNotEmpty) {
        final textBlock = currentTextLines.join('\n');
        final spans = _parseInlineContent(context, textBlock, style);
        widgets.add(Text.rich(TextSpan(children: spans), style: style));
        currentTextLines.clear();
      }
    }

    void flushQuote() {
      if (currentQuoteLines.isNotEmpty) {
        final quoteBody = currentQuoteLines.join('\n');
        final quoteSpans = _parseInlineContent(
          context,
          quoteBody,
          style.copyWith(
            color: const Color(0xFFCBD5E1),
            fontStyle: FontStyle.italic,
          ),
        );

        widgets.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(6),
              border: const Border(
                left: BorderSide(color: Color(0xFF38BDF8), width: 3.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.format_quote_rounded, size: 14, color: Color(0xFF38BDF8)),
                    SizedBox(width: 4),
                    Text(
                      'Citação',
                      style: TextStyle(
                        color: Color(0xFF38BDF8),
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.normal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text.rich(TextSpan(children: quoteSpans), style: style),
              ],
            ),
          ),
        );
        currentQuoteLines.clear();
      }
    }

    for (final line in lines) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('>')) {
        flushText();
        var clean = trimmed.substring(1);
        if (clean.startsWith(' ')) clean = clean.substring(1);
        currentQuoteLines.add(clean);
      } else if (trimmed.startsWith('| ')) {
        flushText();
        currentQuoteLines.add(trimmed.substring(2));
      } else {
        if (currentQuoteLines.isNotEmpty) {
          flushQuote();
        }
        currentTextLines.add(line);
      }
    }
    flushText();
    flushQuote();

    if (widgets.length == 1) {
      return widgets.first;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }
}
