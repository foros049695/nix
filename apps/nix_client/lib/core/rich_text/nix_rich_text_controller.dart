import 'dart:math';
import 'package:flutter/material.dart';

/// Tipos de blocos estruturais suportados pelo editor WYSIWYG.
enum RichBlockType {
  paragraph,
  h1,
  h2,
  h3,
  h4,
  h5,
  h6,
  blockquote,
  codeBlock,
  bulletList,
  numberedList,
  checklist,
  divider,
}

/// Metadados de formatação aplicados a um intervalo contínuo de caracteres.
class RichInlineSpan {
  int start;
  int end;
  bool bold;
  bool italic;
  bool underline;
  bool strikethrough;
  bool monospace;
  bool spoiler;
  bool quote;
  String? linkUrl;

  RichInlineSpan({
    required this.start,
    required this.end,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.monospace = false,
    this.spoiler = false,
    this.quote = false,
    this.linkUrl,
  });

  bool get hasAnyStyle =>
      bold || italic || underline || strikethrough || monospace || spoiler || quote || (linkUrl != null && linkUrl!.isNotEmpty);

  RichInlineSpan copyWith({
    int? start,
    int? end,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    bool? monospace,
    bool? spoiler,
    bool? quote,
    String? linkUrl,
    bool clearLink = false,
  }) {
    return RichInlineSpan(
      start: start ?? this.start,
      end: end ?? this.end,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strikethrough: strikethrough ?? this.strikethrough,
      monospace: monospace ?? this.monospace,
      spoiler: spoiler ?? this.spoiler,
      quote: quote ?? this.quote,
      linkUrl: clearLink ? null : (linkUrl ?? this.linkUrl),
    );
  }
}

/// Estilo aplicado a uma linha inteira do documento.
class RichLineBlock {
  RichBlockType type;
  TextAlign alignment;
  bool isChecked;

  RichLineBlock({
    this.type = RichBlockType.paragraph,
    this.alignment = TextAlign.left,
    this.isChecked = false,
  });

  RichLineBlock clone() => RichLineBlock(
        type: type,
        alignment: alignment,
        isChecked: isChecked,
      );
}

/// Controlador WYSIWYG Sovereign para o Nix Archive e Chats.
///
/// Apresenta o texto formatado visualmente em tempo real no campo de entrada
/// SEM expor delimitadores brutos de Markdown (**bold**, <u>underline</u>, etc.).
/// Serializa e desserializa de/para Markdown canônico preservando 100% de fidelidade
/// e assinaturas Ed25519.
class NixRichTextController extends TextEditingController {
  final List<RichInlineSpan> _spans = [];
  final List<RichLineBlock> _lineBlocks = [RichLineBlock()];

  // Estilos ativos para quando o usuário digita na posição atual com cursor colapsado
  bool activeBold = false;
  bool activeItalic = false;
  bool activeUnderline = false;
  bool activeStrikethrough = false;
  bool activeMonospace = false;
  bool activeSpoiler = false;
  bool activeQuote = false;
  String? activeLinkUrl;

  String _lastText = '';
  TextSelection _lastSelection = const TextSelection.collapsed(offset: -1);
  bool _isTogglingStyle = false;

  NixRichTextController({String? text}) : super(text: text) {
    _lastText = text ?? '';
    _lastSelection = selection;
    if (_lastText.isNotEmpty) {
      _recalculateLineBlocks();
    }
    addListener(_handleTextChanges);
  }

  /// Constrói o controlador a partir de um texto existente em Markdown/HTML.
  factory NixRichTextController.fromMarkdown(String markdown) {
    final controller = NixRichTextController();
    controller.loadMarkdown(markdown);
    return controller;
  }

  List<RichInlineSpan> get spans => List.unmodifiable(_spans);
  List<RichLineBlock> get lineBlocks => List.unmodifiable(_lineBlocks);

  void _recalculateLineBlocks() {
    final lines = text.split('\n');
    while (_lineBlocks.length < lines.length) {
      _lineBlocks.add(RichLineBlock());
    }
    while (_lineBlocks.length > lines.length) {
      _lineBlocks.removeLast();
    }
    String? fenceChar;
    var fenceLen = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (fenceChar != null) {
        if (_isClosingCodeFence(line, fenceChar, fenceLen)) {
          fenceChar = null;
          fenceLen = 0;
        }
        continue;
      }
      final openFence = _matchOpeningCodeFence(line);
      if (openFence != null) {
        fenceChar = openFence.$1;
        fenceLen = openFence.$2;
        continue;
      }
      final currentType = _lineBlocks[i].type;
      final isListOrParagraph = currentType == RichBlockType.paragraph ||
          currentType == RichBlockType.bulletList ||
          currentType == RichBlockType.numberedList ||
          currentType == RichBlockType.checklist;
      if (!isListOrParagraph) continue;

      if (line.startsWith('☐ ') || line.startsWith('☑ ')) {
        _lineBlocks[i].type = RichBlockType.checklist;
        _lineBlocks[i].isChecked = line.startsWith('☑ ');
      } else if (line.startsWith('• ') || line.startsWith('- ')) {
        _lineBlocks[i].type = RichBlockType.bulletList;
      } else if (_hasNumberedListPrefix(line)) {
        _lineBlocks[i].type = RichBlockType.numberedList;
      } else {
        _lineBlocks[i].type = RichBlockType.paragraph;
        _lineBlocks[i].isChecked = false;
      }
    }
  }

  void _handleTextChanges() {
    if (_isTogglingStyle) return;

    if (text == _lastText) {
      if (selection != _lastSelection) {
        _lastSelection = selection;
        _updateActiveStylesFromCursor();
      }
      return;
    }

    _lastSelection = selection;
    final oldText = _lastText;
    final newText = text;
    _lastText = newText;

    // Detecta inserção ou deleção
    if (newText.length > oldText.length) {
      // Inserção de caracteres
      final diff = newText.length - oldText.length;
      final changePos = _findFirstDiff(oldText, newText);

      // Desloca spans que começam após o ponto de inserção
      for (final span in _spans) {
        if (span.start >= changePos) {
          span.start += diff;
          span.end += diff;
        } else if (span.end > changePos) {
          // Span intercepta o ponto de inserção
          span.end += diff;
        }
      }

      // Se há estilos ativos aplicáveis, cria ou estende span para os novos caracteres
      // apenas se o span existente já não cobrir com o mesmo estilo
      if (_hasActiveStyles()) {
        final alreadyCovered = _spans.any((s) =>
            s.start <= changePos &&
            s.end >= changePos + diff &&
            s.bold == activeBold &&
            s.italic == activeItalic &&
            s.underline == activeUnderline &&
            s.strikethrough == activeStrikethrough &&
            s.monospace == activeMonospace &&
            s.spoiler == activeSpoiler &&
            s.quote == activeQuote &&
            s.linkUrl == activeLinkUrl);
        if (!alreadyCovered) {
          _spans.add(RichInlineSpan(
            start: changePos,
            end: changePos + diff,
            bold: activeBold,
            italic: activeItalic,
            underline: activeUnderline,
            strikethrough: activeStrikethrough,
            monospace: activeMonospace,
            spoiler: activeSpoiler,
            quote: activeQuote,
            linkUrl: activeLinkUrl,
          ));
        }
      }
    } else if (newText.length < oldText.length) {
      // Remoção de caracteres
      final diff = oldText.length - newText.length;
      final changePos = _findFirstDiff(oldText, newText);
      final changeEnd = changePos + diff;

      _spans.removeWhere((span) {
        if (span.start >= changePos && span.end <= changeEnd) {
          // Completamente deletado
          return true;
        }
        if (span.start >= changeEnd) {
          // Desloca para trás
          span.start -= diff;
          span.end -= diff;
        } else if (span.end > changePos) {
          // Encurta
          final deletedInside = min<int>(span.end, changeEnd) - max<int>(span.start, changePos);
          span.end -= deletedInside;
        }
        return span.start >= span.end;
      });
    }

    _recalculateLineBlocks();
    _normalizeSpans();
    _updateActiveStylesFromCursor();
  }

  int _findFirstDiff(String a, String b) {
    final len = min(a.length, b.length);
    for (var i = 0; i < len; i++) {
      if (a[i] != b[i]) return i;
    }
    return len;
  }

  bool _hasActiveStyles() =>
      activeBold ||
      activeItalic ||
      activeUnderline ||
      activeStrikethrough ||
      activeMonospace ||
      activeSpoiler ||
      activeQuote ||
      (activeLinkUrl != null && activeLinkUrl!.isNotEmpty);

  void _updateActiveStylesFromCursor() {
    final sel = selection;
    if (!sel.isValid || !sel.isCollapsed || sel.start < 0 || sel.start > text.length) {
      return;
    }
    final pos = sel.start;
    if (pos == 0) return;

    // Herda estilos do caractere imediatamente anterior
    final prevPos = pos - 1;
    bool b = false, it = false, u = false, st = false, mono = false, sp = false, q = false;
    String? lk;

    for (final s in _spans) {
      if (prevPos >= s.start && prevPos < s.end) {
        if (s.bold) b = true;
        if (s.italic) it = true;
        if (s.underline) u = true;
        if (s.strikethrough) st = true;
        if (s.monospace) mono = true;
        if (s.spoiler) sp = true;
        if (s.quote) q = true;
        if (s.linkUrl != null) lk = s.linkUrl;
      }
    }
    activeBold = b;
    activeItalic = it;
    activeUnderline = u;
    activeStrikethrough = st;
    activeMonospace = mono;
    activeSpoiler = sp;
    activeQuote = q;
    activeLinkUrl = lk;
  }

  void _normalizeSpans() {
    // 1. Remove spans inválidos ou vazios
    _spans.removeWhere((s) => s.start >= s.end || s.start < 0 || s.end > text.length || !s.hasAnyStyle);

    // 2. Ordena por início e término
    _spans.sort((a, b) {
      final c = a.start.compareTo(b.start);
      if (c != 0) return c;
      return a.end.compareTo(b.end);
    });

    // 3. Mescla spans contíguos ou sobrepostos com estilos idênticos
    var i = 0;
    while (i < _spans.length - 1) {
      final cur = _spans[i];
      final next = _spans[i + 1];

      if (cur.bold == next.bold &&
          cur.italic == next.italic &&
          cur.underline == next.underline &&
          cur.strikethrough == next.strikethrough &&
          cur.monospace == next.monospace &&
          cur.spoiler == next.spoiler &&
          cur.quote == next.quote &&
          cur.linkUrl == next.linkUrl &&
          cur.end >= next.start) {
        cur.end = max(cur.end, next.end);
        _spans.removeAt(i + 1);
      } else {
        i++;
      }
    }
  }

  // ==========================================
  // OPERAÇÕES VISUAIS INLINE (WYSIWYG)
  // ==========================================

  void toggleBold() {
    _toggleInlineStyle((s) => s.bold, (s, v) => s.bold = v, (v) => activeBold = v, activeBold);
  }

  void toggleItalic() {
    _toggleInlineStyle((s) => s.italic, (s, v) => s.italic = v, (v) => activeItalic = v, activeItalic);
  }

  void toggleUnderline() {
    _toggleInlineStyle((s) => s.underline, (s, v) => s.underline = v, (v) => activeUnderline = v, activeUnderline);
  }

  void toggleStrikethrough() {
    _toggleInlineStyle((s) => s.strikethrough, (s, v) => s.strikethrough = v, (v) => activeStrikethrough = v, activeStrikethrough);
  }

  void toggleMonospace() {
    _toggleInlineStyle((s) => s.monospace, (s, v) => s.monospace = v, (v) => activeMonospace = v, activeMonospace);
  }

  void toggleSpoiler() {
    _toggleInlineStyle((s) => s.spoiler, (s, v) => s.spoiler = v, (v) => activeSpoiler = v, activeSpoiler);
  }

  void toggleQuote() {
    _toggleInlineStyle((s) => s.quote, (s, v) => s.quote = v, (v) => activeQuote = v, activeQuote);
  }

  void setLink(String? url) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) {
      activeLinkUrl = url;
      notifyListeners();
      return;
    }
    final start = min(sel.start, sel.end);
    final end = max(sel.start, sel.end);

    _spans.add(RichInlineSpan(
      start: start,
      end: end,
      linkUrl: url,
    ));
    _normalizeSpans();
    notifyListeners();
  }

  void _toggleInlineStyle(
    bool Function(RichInlineSpan) getter,
    void Function(RichInlineSpan, bool) setter,
    void Function(bool) activeSetter,
    bool currentActive,
  ) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) {
      // Cursor colapsado: apenas ativa/desativa modo de digitação futura
      _isTogglingStyle = true;
      try {
        activeSetter(!currentActive);
        notifyListeners();
      } finally {
        _isTogglingStyle = false;
      }
      return;
    }

    final start = min(sel.start, sel.end);
    final end = max(sel.start, sel.end);

    // Verifica se a seleção já está totalmente com este estilo
    bool allStyled = true;
    for (var i = start; i < end; i++) {
      final isStyled = _spans.any((s) => i >= s.start && i < s.end && getter(s));
      if (!isStyled) {
        allStyled = false;
        break;
      }
    }

    final targetVal = !allStyled;

    if (targetVal) {
      // Adiciona o estilo na região
      final newSpan = RichInlineSpan(start: start, end: end);
      setter(newSpan, true);
      _spans.add(newSpan);
    } else {
      // Remove o estilo da região
      final toAdd = <RichInlineSpan>[];
      for (final s in _spans) {
        if (getter(s) && s.start < end && s.end > start) {
          // Intercepta a região a ser desestilizada
          if (s.start < start) {
            final left = s.copyWith(end: start);
            toAdd.add(left);
          }
          if (s.end > end) {
            final right = s.copyWith(start: end);
            toAdd.add(right);
          }
          setter(s, false);
        }
      }
      _spans.addAll(toAdd);
    }

    _normalizeSpans();
    notifyListeners();
  }

  // ==========================================
  // OPERAÇÕES VISUAIS DE BLOCO / LINHA
  // ==========================================

  int get currentLineIndex {
    final sel = selection;
    if (!sel.isValid) return 0;
    final pos = sel.start;
    final prefix = text.substring(0, min(pos, text.length));
    return prefix.split('\n').length - 1;
  }

  RichLineBlock get currentLineBlock {
    final idx = currentLineIndex;
    if (idx < _lineBlocks.length) {
      return _lineBlocks[idx];
    }
    return RichLineBlock();
  }

  void setBlockType(RichBlockType type) {
    final idx = currentLineIndex;
    if (idx < _lineBlocks.length) {
      _lineBlocks[idx].type = (_lineBlocks[idx].type == type) ? RichBlockType.paragraph : type;
      notifyListeners();
    }
  }

  void toggleHeading(int level) {
    switch (level) {
      case 1: setBlockType(RichBlockType.h1); break;
      case 2: setBlockType(RichBlockType.h2); break;
      case 3: setBlockType(RichBlockType.h3); break;
      case 4: setBlockType(RichBlockType.h4); break;
      case 5: setBlockType(RichBlockType.h5); break;
      case 6: setBlockType(RichBlockType.h6); break;
      default: setBlockType(RichBlockType.paragraph); break;
    }
  }

  void toggleBlockquote() => setBlockType(RichBlockType.blockquote);
  void toggleCodeBlock() => setBlockType(RichBlockType.codeBlock);
  void toggleBulletList() => _toggleLinePrefix('• ');
  void toggleNumberedList() => _toggleLinePrefix('1. ');
  void toggleChecklist() => _toggleLinePrefix('☐ ');

  void _toggleLinePrefix(String prefix) {
    final sel = selection;
    final pos = sel.isValid ? sel.start : text.length;
    final before = text.substring(0, pos);
    final lineStart = before.lastIndexOf('\n') + 1;
    final afterLineStart = text.substring(lineStart);
    final lineEndOffset = afterLineStart.indexOf('\n');
    final lineEnd = lineEndOffset == -1 ? text.length : lineStart + lineEndOffset;
    final line = text.substring(lineStart, lineEnd);

    String newLine;
    int shift;
    if (line.startsWith(prefix)) {
      newLine = line.substring(prefix.length);
      shift = -prefix.length;
    } else if (prefix == '☐ ' && line.startsWith('☑ ')) {
      newLine = line.substring(2);
      shift = -2;
    } else {
      var clean = line;
      var cleanShift = 0;
      for (final p in ['• ', '☐ ', '☑ ', '- ', '* ']) {
        if (clean.startsWith(p)) {
          clean = clean.substring(p.length);
          cleanShift = -p.length;
          break;
        }
      }
      newLine = '$prefix$clean';
      shift = prefix.length + cleanShift;
    }

    final newText = text.replaceRange(lineStart, lineEnd, newLine);
    _lastText = newText;
    text = newText;
    final newCursor = (pos + shift).clamp(0, newText.length);
    selection = TextSelection.collapsed(offset: newCursor);
    _recalculateLineBlocks();
    notifyListeners();
  }

  void toggleChecklistState([int? lineIdx]) {
    final sel = selection;
    final pos = sel.isValid ? sel.start : 0;
    final before = text.substring(0, pos);
    final lineStart = before.lastIndexOf('\n') + 1;
    final afterLineStart = text.substring(lineStart);
    final lineEndOffset = afterLineStart.indexOf('\n');
    final lineEnd = lineEndOffset == -1 ? text.length : lineStart + lineEndOffset;
    final line = text.substring(lineStart, lineEnd);

    if (line.startsWith('☐ ')) {
      final newLine = '☑ ${line.substring(2)}';
      text = text.replaceRange(lineStart, lineEnd, newLine);
      _lastText = text;
      notifyListeners();
    } else if (line.startsWith('☑ ')) {
      final newLine = '☐ ${line.substring(2)}';
      text = text.replaceRange(lineStart, lineEnd, newLine);
      _lastText = text;
      notifyListeners();
    }
  }

  void setAlignment(TextAlign align) {
    final idx = currentLineIndex;
    if (idx < _lineBlocks.length) {
      _lineBlocks[idx].alignment = align;
      notifyListeners();
    }
  }

  void insertDivider() {
    final sel = selection;
    final insertPos = sel.isValid ? sel.start : text.length;
    final prefix = text.substring(0, insertPos);
    final suffix = text.substring(insertPos);
    final sep = (prefix.isEmpty || prefix.endsWith('\n')) ? '' : '\n';
    text = '$prefix$sep---\n$suffix';
    selection = TextSelection.collapsed(offset: insertPos + sep.length + 4);
    _recalculateLineBlocks();
    notifyListeners();
  }

  void insertTable({int rows = 3, int cols = 2}) {
    final buf = StringBuffer('\n');
    buf.write('|');
    for (var c = 1; c <= cols; c++) {
      buf.write(' Coluna $c |');
    }
    buf.write('\n|');
    for (var c = 1; c <= cols; c++) {
      buf.write(' --- |');
    }
    buf.write('\n');
    for (var r = 1; r <= rows; r++) {
      buf.write('|');
      for (var c = 1; c <= cols; c++) {
        buf.write(' Valor $r,$c |');
      }
      buf.write('\n');
    }

    final sel = selection;
    final insertPos = sel.isValid ? sel.start : text.length;
    final prefix = text.substring(0, insertPos);
    final suffix = text.substring(insertPos);
    text = '$prefix${buf.toString()}$suffix';
    selection = TextSelection.collapsed(offset: insertPos + buf.length);
    _recalculateLineBlocks();
    notifyListeners();
  }

  // ==========================================
  // RENDERIZAÇÃO WYSIWYG REAL (buildTextSpan)
  // ==========================================

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ?? const TextStyle(color: Colors.white, fontSize: 14);
    if (text.isEmpty) {
      return TextSpan(style: baseStyle, text: '');
    }

    final lines = text.split('\n');
    final rootChildren = <InlineSpan>[];
    var globalOffset = 0;

    for (var lineIdx = 0; lineIdx < lines.length; lineIdx++) {
      final lineText = lines[lineIdx];
      final lineBlock = (lineIdx < _lineBlocks.length) ? _lineBlocks[lineIdx] : RichLineBlock();
      final lineLength = lineText.length;
      final lineEnd = globalOffset + lineLength;

      // Determina estilo do bloco de linha
      TextStyle lineStyle = baseStyle;

      switch (lineBlock.type) {
        case RichBlockType.h1:
          lineStyle = baseStyle.copyWith(
            fontSize: (baseStyle.fontSize ?? 14) * 1.8,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFE2E8F0),
            letterSpacing: -0.5,
          );
          break;
        case RichBlockType.h2:
          lineStyle = baseStyle.copyWith(
            fontSize: (baseStyle.fontSize ?? 14) * 1.5,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFCBD5E1),
          );
          break;
        case RichBlockType.h3:
          lineStyle = baseStyle.copyWith(
            fontSize: (baseStyle.fontSize ?? 14) * 1.25,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF94A3B8),
          );
          break;
        case RichBlockType.h4:
        case RichBlockType.h5:
        case RichBlockType.h6:
          lineStyle = baseStyle.copyWith(
            fontSize: (baseStyle.fontSize ?? 14) * 1.1,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF94A3B8),
          );
          break;
        case RichBlockType.blockquote:
          lineStyle = baseStyle.copyWith(
            fontStyle: FontStyle.italic,
            color: const Color(0xFF38BDF8),
            backgroundColor: const Color(0x2238BDF8),
          );
          break;
        case RichBlockType.codeBlock:
          lineStyle = baseStyle.copyWith(
            fontFamily: 'monospace',
            backgroundColor: const Color(0x33000000),
            color: const Color(0xFF38BDF8),
          );
          break;
        case RichBlockType.bulletList:
        case RichBlockType.numberedList:
        case RichBlockType.checklist:
        case RichBlockType.divider:
        case RichBlockType.paragraph:
          break;
      }

      final lineChildren = <InlineSpan>[];

      // Segmenta a linha conforme os spans inline
      if (lineLength > 0) {
        var currentPos = globalOffset;

        while (currentPos < lineEnd) {
          // Coleta estilos ativos na posição atual
          bool isBold = false;
          bool isItalic = false;
          bool isUnderline = false;
          bool isStrike = false;
          bool isMono = false;
          bool isSpoiler = false;
          bool isQuote = false;
          String? linkUrl;

          int nextBoundary = lineEnd;

          for (final s in _spans) {
            if (currentPos >= s.start && currentPos < s.end) {
              if (s.bold) isBold = true;
              if (s.italic) isItalic = true;
              if (s.underline) isUnderline = true;
              if (s.strikethrough) isStrike = true;
              if (s.monospace) isMono = true;
              if (s.spoiler) isSpoiler = true;
              if (s.quote) isQuote = true;
              if (s.linkUrl != null) linkUrl = s.linkUrl;
              nextBoundary = min<int>(nextBoundary, s.end);
            } else if (s.start > currentPos) {
              nextBoundary = min<int>(nextBoundary, s.start);
            }
          }

          final segmentLength = nextBoundary - currentPos;
          final segmentText = text.substring(currentPos, currentPos + segmentLength);

          TextStyle segStyle = lineStyle;
          if (lineText.trim().startsWith('|') && lineText.trim().endsWith('|')) {
            segStyle = segStyle.copyWith(
              fontFamily: 'monospace',
              color: const Color(0xFFE2E8F0),
              backgroundColor: const Color(0x1A64748B),
            );
          }
          if (isBold) {
            segStyle = segStyle.copyWith(fontWeight: FontWeight.bold);
          }
          if (isItalic) {
            segStyle = segStyle.copyWith(fontStyle: FontStyle.italic);
          }
          if (isUnderline && isStrike) {
            segStyle = segStyle.copyWith(
              decoration: TextDecoration.combine([TextDecoration.underline, TextDecoration.lineThrough]),
              decorationColor: const Color(0xFF64B5F6),
            );
          } else if (isUnderline) {
            segStyle = segStyle.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: const Color(0xFF64B5F6),
            );
          } else if (isStrike) {
            segStyle = segStyle.copyWith(decoration: TextDecoration.lineThrough);
          }
          if (isQuote) {
            segStyle = segStyle.copyWith(
              fontStyle: FontStyle.italic,
              color: const Color(0xFF38BDF8),
              backgroundColor: const Color(0x2238BDF8),
            );
          }
          if (isMono) {
            segStyle = segStyle.copyWith(
              fontFamily: 'monospace',
              backgroundColor: const Color(0x33A855F7),
              color: const Color(0xFFF472B6),
            );
          }
          if (isSpoiler) {
            segStyle = segStyle.copyWith(
              backgroundColor: const Color(0xFF1E293B),
              color: const Color(0xFF94A3B8),
            );
          }
          if (linkUrl != null && linkUrl.isNotEmpty) {
            segStyle = segStyle.copyWith(
              color: const Color(0xFF60A5FA),
              decoration: TextDecoration.underline,
            );
          }

          lineChildren.add(TextSpan(text: segmentText, style: segStyle));
          currentPos = nextBoundary;
        }
      }

      rootChildren.addAll(lineChildren);
      if (lineIdx < lines.length - 1) {
        rootChildren.add(const TextSpan(text: '\n'));
      }
      globalOffset = lineEnd + 1; // +1 para pular o caractere '\n'
    }

    return TextSpan(style: baseStyle, children: rootChildren);
  }

  // ==========================================
  // SERIALIZAÇÃO / DESSERIALIZAÇÃO MARKDOWN
  // ==========================================

  /// Serializa a representação visual WYSIWYG em Markdown padrão GitHub Flavored (GFM).
  String toMarkdown() {
    if (text.isEmpty) return '';

    final lines = text.split('\n');
    final out = StringBuffer();
    var globalOffset = 0;
    var firstSpanIdx = 0;
    String? fenceChar;
    var fenceLen = 0;

    for (var lineIdx = 0; lineIdx < lines.length; lineIdx++) {
      final lineText = lines[lineIdx];
      final lineBlock = (lineIdx < _lineBlocks.length) ? _lineBlocks[lineIdx] : RichLineBlock();
      final lineLength = lineText.length;
      final lineEnd = globalOffset + lineLength;

      var isFencedLine = false;
      if (lineBlock.type == RichBlockType.paragraph) {
        if (fenceChar != null) {
          isFencedLine = true;
          if (_isClosingCodeFence(lineText, fenceChar, fenceLen)) {
            fenceChar = null;
            fenceLen = 0;
          }
        } else {
          final openFence = _matchOpeningCodeFence(lineText);
          if (openFence != null) {
            isFencedLine = true;
            fenceChar = openFence.$1;
            fenceLen = openFence.$2;
          }
        }
      }

      if (isFencedLine && !_hasAnySpanInRange(globalOffset, lineEnd, firstSpanIdx)) {
        out.write(lineText);
        if (lineIdx < lines.length - 1) {
          out.write('\n');
        }
        globalOffset = lineEnd + 1;
        continue;
      }

      // Prefixo do bloco
      String prefix = '';
      String suffix = '';
      switch (lineBlock.type) {
        case RichBlockType.h1: prefix = '# '; break;
        case RichBlockType.h2: prefix = '## '; break;
        case RichBlockType.h3: prefix = '### '; break;
        case RichBlockType.h4: prefix = '#### '; break;
        case RichBlockType.h5: prefix = '##### '; break;
        case RichBlockType.h6: prefix = '###### '; break;
        case RichBlockType.blockquote: prefix = '> '; break;
        case RichBlockType.codeBlock: prefix = '```\n'; suffix = '\n```'; break;
        case RichBlockType.bulletList:
        case RichBlockType.numberedList:
        case RichBlockType.checklist: break;
        case RichBlockType.divider: prefix = '---'; break;
        case RichBlockType.paragraph: break;
      }

      out.write(prefix);

      if (lineLength > 0 && lineBlock.type != RichBlockType.divider) {
        var currentPos = globalOffset;

        while (currentPos < lineEnd) {
          while (firstSpanIdx < _spans.length && _spans[firstSpanIdx].end <= currentPos) {
            firstSpanIdx++;
          }

          bool isBold = false;
          bool isItalic = false;
          bool isUnderline = false;
          bool isStrike = false;
          bool isMono = false;
          bool isSpoiler = false;
          bool isQuote = false;
          String? linkUrl;

          int nextBoundary = lineEnd;

          for (var si = firstSpanIdx; si < _spans.length; si++) {
            final s = _spans[si];
            if (s.start >= nextBoundary) break;
            if (currentPos >= s.start && currentPos < s.end) {
              if (s.bold) isBold = true;
              if (s.italic) isItalic = true;
              if (s.underline) isUnderline = true;
              if (s.strikethrough) isStrike = true;
              if (s.monospace) isMono = true;
              if (s.spoiler) isSpoiler = true;
              if (s.quote) isQuote = true;
              if (s.linkUrl != null) linkUrl = s.linkUrl;
              nextBoundary = min<int>(nextBoundary, s.end);
            } else if (s.start > currentPos) {
              nextBoundary = min<int>(nextBoundary, s.start);
            }
          }

          final segmentLength = nextBoundary - currentPos;
          var seg = text.substring(currentPos, currentPos + segmentLength);

          if (!isFencedLine && currentPos == globalOffset) {
            if (seg.startsWith('• ')) {
              seg = '- ${seg.substring(2)}';
            } else if (seg.startsWith('☐ ')) {
              seg = '- [ ] ${seg.substring(2)}';
            } else if (seg.startsWith('☑ ')) {
              seg = '- [x] ${seg.substring(2)}';
            }
          }

          if (isBold) seg = '**$seg**';
          if (isItalic) seg = '*$seg*';
          if (isUnderline) seg = '<u>$seg</u>';
          if (isStrike) seg = '~~$seg~~';
          if (isQuote) seg = '<q>$seg</q>';
          if (isMono) seg = '`$seg`';
          if (isSpoiler) seg = '||$seg||';
          if (linkUrl != null && linkUrl.isNotEmpty) seg = '[$seg]($linkUrl)';

          out.write(seg);
          currentPos = nextBoundary;
        }
      }

      out.write(suffix);

      if (lineIdx < lines.length - 1) {
        out.write('\n');
      }
      globalOffset = lineEnd + 1;
    }

    return out.toString();
  }

  bool _hasAnySpanInRange(int start, int end, int fromSpanIdx) {
    for (var i = fromSpanIdx; i < _spans.length; i++) {
      final s = _spans[i];
      if (s.start >= end) return false;
      if (s.end > start) return true;
    }
    return false;
  }

  /// Carrega conteúdo Markdown/HTML existente para o editor WYSIWYG,
  /// convertendo os marcadores em spans visuais puros.
  void loadMarkdown(String markdown) {
    _spans.clear();
    _lineBlocks.clear();

    if (markdown.isEmpty) {
      text = '';
      _lastText = '';
      _lineBlocks.add(RichLineBlock());
      notifyListeners();
      return;
    }

    final rawLines = markdown.split('\n');
    final pendingNonFenced = <String>[];
    final finalChunks = <String>[];
    var currentOffset = 0;
    String? fenceChar;
    var fenceLen = 0;

    void flushNonFenced() {
      if (pendingNonFenced.isEmpty) return;
      final segment = pendingNonFenced.join('\n');
      pendingNonFenced.clear();
      final parsed = _parseInlineMarkdown(segment, currentOffset);
      _spans.addAll(parsed.spans);
      finalChunks.add(parsed.plainText);
      currentOffset += parsed.plainText.length + 1;
    }

    for (var i = 0; i < rawLines.length; i++) {
      var raw = rawLines[i];

      if (fenceChar != null) {
        _lineBlocks.add(RichLineBlock(type: RichBlockType.paragraph));
        finalChunks.add(raw);
        currentOffset += raw.length + 1;
        if (_isClosingCodeFence(raw, fenceChar, fenceLen)) {
          fenceChar = null;
          fenceLen = 0;
        }
        continue;
      }

      final openFence = _matchOpeningCodeFence(raw);
      if (openFence != null) {
        flushNonFenced();
        fenceChar = openFence.$1;
        fenceLen = openFence.$2;
        _lineBlocks.add(RichLineBlock(type: RichBlockType.paragraph));
        finalChunks.add(raw);
        currentOffset += raw.length + 1;
        continue;
      }

      var blockType = RichBlockType.paragraph;
      bool isChecked = false;

      // Detecção de blocos de cabeçalho e listas
      if (raw.startsWith('###### ')) {
        blockType = RichBlockType.h6;
        raw = raw.substring(7);
      } else if (raw.startsWith('##### ')) {
        blockType = RichBlockType.h5;
        raw = raw.substring(6);
      } else if (raw.startsWith('#### ')) {
        blockType = RichBlockType.h4;
        raw = raw.substring(5);
      } else if (raw.startsWith('### ')) {
        blockType = RichBlockType.h3;
        raw = raw.substring(4);
      } else if (raw.startsWith('## ')) {
        blockType = RichBlockType.h2;
        raw = raw.substring(3);
      } else if (raw.startsWith('# ')) {
        blockType = RichBlockType.h1;
        raw = raw.substring(2);
      } else if (raw.startsWith('>')) {
        blockType = RichBlockType.blockquote;
        raw = raw.replaceFirst(RegExp(r'^>\s*'), '');
      } else if (raw.startsWith('- [x] ') || raw.startsWith('- [X] ')) {
        blockType = RichBlockType.checklist;
        isChecked = true;
        raw = '☑ ${raw.substring(6)}';
      } else if (raw.startsWith('- [ ] ')) {
        blockType = RichBlockType.checklist;
        isChecked = false;
        raw = '☐ ${raw.substring(6)}';
      } else if (raw.startsWith('- ') || raw.startsWith('* ')) {
        blockType = RichBlockType.bulletList;
        raw = '• ${raw.substring(2)}';
      } else if (_hasNumberedListPrefix(raw)) {
        blockType = RichBlockType.numberedList;
      } else if (raw == '---' || raw == '***' || raw == '___') {
        flushNonFenced();
        _lineBlocks.add(RichLineBlock(type: RichBlockType.divider));
        const dividerVisual = '──────────';
        finalChunks.add(dividerVisual);
        currentOffset += dividerVisual.length + 1;
        continue;
      }

      _lineBlocks.add(RichLineBlock(type: blockType, isChecked: isChecked));
      pendingNonFenced.add(raw);
    }

    flushNonFenced();

    final newPlainText = finalChunks.join('\n');
    _lastText = newPlainText;
    value = TextEditingValue(
      text: newPlainText,
      selection: TextSelection.collapsed(offset: newPlainText.length),
    );
    _recalculateLineBlocks();
    _normalizeSpans();
    notifyListeners();
  }

  static final RegExp _nonAsciiWordCharRegex = RegExp(r'[\p{L}\p{N}]', unicode: true);

  static bool _hasNumberedListPrefix(String line) {
    var i = 0;
    while (i < line.length) {
      final c = line.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) break;
      i++;
    }
    return i > 0 &&
        i + 1 < line.length &&
        line.codeUnitAt(i) == 0x2E &&
        _isWhitespace(line, i + 1);
  }

  static (String, int)? _matchOpeningCodeFence(String line) {
    var i = 0;
    while (i < line.length && i < 3 && line.codeUnitAt(i) == 0x20) {
      i++;
    }
    if (i >= line.length) return null;
    final ch = line.codeUnitAt(i);
    if (ch != 0x60 && ch != 0x7E) return null; // '`' ou '~'
    final start = i;
    while (i < line.length && line.codeUnitAt(i) == ch) {
      i++;
    }
    final len = i - start;
    if (len < 3) return null;
    if (ch == 0x60 && line.indexOf('`', i) != -1) {
      return null;
    }
    return (ch == 0x60 ? '`' : '~', len);
  }

  static bool _isClosingCodeFence(String line, String fenceChar, int minLen) {
    var i = 0;
    while (i < line.length && i < 3 && line.codeUnitAt(i) == 0x20) {
      i++;
    }
    if (i >= line.length) return false;
    final expected = fenceChar.codeUnitAt(0);
    final start = i;
    while (i < line.length && line.codeUnitAt(i) == expected) {
      i++;
    }
    if (i - start < minLen) return false;
    while (i < line.length) {
      final c = line.codeUnitAt(i);
      if (c != 0x20 && c != 0x09) return false;
      i++;
    }
    return true;
  }

  static bool _isWhitespace(String s, int i) {
    if (i < 0 || i >= s.length) return false;
    final c = s.codeUnitAt(i);
    return c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
  }

  static bool _isWordChar(String s, int i) {
    if (i < 0 || i >= s.length) return false;
    final c = s.codeUnitAt(i);
    if (c < 0x80) {
      return (c >= 0x30 && c <= 0x39) ||
          (c >= 0x41 && c <= 0x5A) ||
          (c >= 0x61 && c <= 0x7A);
    }
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
      return _nonAsciiWordCharRegex.hasMatch(s.substring(i, i + 2));
    }
    if (c >= 0xDC00 && c <= 0xDFFF && i > 0) {
      return _nonAsciiWordCharRegex.hasMatch(s.substring(i - 1, i + 1));
    }
    return _nonAsciiWordCharRegex.hasMatch(s[i]);
  }

  static bool _startsWithAsciiIgnoreCase(String s, int index, String lowerPattern) {
    if (index + lowerPattern.length > s.length) return false;
    for (var i = 0; i < lowerPattern.length; i++) {
      var c = s.codeUnitAt(index + i);
      if (c >= 0x41 && c <= 0x5A) c += 0x20;
      if (c != lowerPattern.codeUnitAt(i)) return false;
    }
    return true;
  }

  static int _indexOfAsciiIgnoreCase(String s, String lowerPattern, int startIndex) {
    final maxIdx = s.length - lowerPattern.length;
    final first = lowerPattern.codeUnitAt(0);
    for (var i = startIndex; i <= maxIdx; i++) {
      var c = s.codeUnitAt(i);
      if (c >= 0x41 && c <= 0x5A) c += 0x20;
      if (c == first && _startsWithAsciiIgnoreCase(s, i, lowerPattern)) {
        return i;
      }
    }
    return -1;
  }

  static int _skipInlineCodeIfClosed(String input, int tickPos, int limit) {
    var endTicks = tickPos;
    while (endTicks < limit && input.codeUnitAt(endTicks) == 0x60) {
      endTicks++;
    }
    final tickLen = endTicks - tickPos;
    final closePos = _findClosingBackticks(input, endTicks, tickLen, limit);
    return closePos == -1 ? endTicks : closePos + tickLen;
  }

  static int _findClosingBackticks(String input, int searchStart, int tickLen, int limit) {
    var pos = searchStart;
    while (pos < limit) {
      if (input.codeUnitAt(pos) == 0x60) {
        var runEnd = pos;
        while (runEnd < limit && input.codeUnitAt(runEnd) == 0x60) {
          runEnd++;
        }
        if (runEnd - pos == tickLen) {
          return pos;
        }
        pos = runEnd;
        continue;
      }
      pos++;
    }
    return -1;
  }

  static int _findClosingAsteriskBold(
    String input,
    int searchStart,
    bool openedWithTriple,
    int limit,
  ) {
    final contentStart = openedWithTriple ? searchStart + 1 : searchStart;
    var pos = contentStart;
    while (pos < limit) {
      final cu = input.codeUnitAt(pos);
      if (cu == 0x60) {
        pos = _skipInlineCodeIfClosed(input, pos, limit);
        continue;
      }
      if (cu == 0x2A) {
        var runEnd = pos;
        while (runEnd < limit && input.codeUnitAt(runEnd) == 0x2A) {
          runEnd++;
        }
        final runLen = runEnd - pos;
        if (pos > contentStart && !_isWhitespace(input, pos - 1)) {
          if (runLen == 2) return pos;
          if (runLen == 3) return openedWithTriple ? pos + 1 : pos;
        }
        pos = runEnd;
        continue;
      }
      pos++;
    }
    return -1;
  }

  static int _findClosingDoubleChar(
    String input,
    int searchStart,
    int markerCu,
    int limit,
  ) {
    var pos = searchStart;
    while (pos < limit) {
      final cu = input.codeUnitAt(pos);
      if (cu == 0x60) {
        pos = _skipInlineCodeIfClosed(input, pos, limit);
        continue;
      }
      if (cu == markerCu) {
        var runEnd = pos;
        while (runEnd < limit && input.codeUnitAt(runEnd) == markerCu) {
          runEnd++;
        }
        if (runEnd - pos == 2 && pos > searchStart && !_isWhitespace(input, pos - 1)) {
          return pos;
        }
        pos = runEnd;
        continue;
      }
      pos++;
    }
    return -1;
  }

  static int _findClosingSingleEmphasis(
    String input,
    int searchStart,
    int markerCu,
    int limit,
  ) {
    var pos = searchStart;
    while (pos < limit) {
      final cu = input.codeUnitAt(pos);
      if (cu == 0x60) {
        pos = _skipInlineCodeIfClosed(input, pos, limit);
        continue;
      }
      if (cu == 0x5B) {
        // Pula links [texto](url) para não confundir marcadores na URL
        final linkEnd = _tryMatchMarkdownLinkEnd(input, pos, limit);
        if (linkEnd != -1) {
          pos = linkEnd;
          continue;
        }
      }
      if (cu == markerCu) {
        var runEnd = pos;
        while (runEnd < limit && input.codeUnitAt(runEnd) == markerCu) {
          runEnd++;
        }
        if (runEnd - pos == 1 &&
            pos > searchStart &&
            !_isWhitespace(input, pos - 1) &&
            !_isWordChar(input, pos + 1)) {
          return pos;
        }
        pos = runEnd;
        continue;
      }
      pos++;
    }
    return -1;
  }

  static int _tryMatchMarkdownLinkEnd(String input, int openBracket, int limit) {
    var b = openBracket + 1;
    while (b < limit && input.codeUnitAt(b) != 0x0A && input.codeUnitAt(b) != 0x5D) {
      b++;
    }
    if (b >= limit || b == openBracket + 1 || input.codeUnitAt(b) != 0x5D) {
      return -1;
    }
    if (b + 1 >= limit || input.codeUnitAt(b + 1) != 0x28) {
      return -1;
    }
    var p = b + 2;
    while (p < limit && input.codeUnitAt(p) != 0x0A && input.codeUnitAt(p) != 0x29) {
      p++;
    }
    if (p >= limit || p == b + 2 || input.codeUnitAt(p) != 0x29) {
      return -1;
    }
    return p + 1;
  }

  static int _scanBareUrlEnd(String input, int start) {
    var end = start;
    while (end < input.length) {
      final c = input.codeUnitAt(end);
      if (c == 0x20 ||
          c == 0x09 ||
          c == 0x0A ||
          c == 0x0D ||
          c == 0x3C ||
          c == 0x3E ||
          c == 0x60 ||
          c == 0x22 ||
          c == 0x27) {
        break;
      }
      if (input.startsWith('**', end) ||
          input.startsWith('~~', end) ||
          input.startsWith('||', end)) {
        break;
      }
      end++;
    }
    while (end > start) {
      final last = input.codeUnitAt(end - 1);
      if (last == 0x2E ||
          last == 0x2C ||
          last == 0x3B ||
          last == 0x3A ||
          last == 0x21 ||
          last == 0x3F ||
          last == 0x2A) {
        end--;
      } else {
        break;
      }
    }
    return end;
  }

  static _InlineParseResult _parseInlineMarkdown(String input, int startOffset) {
    final spans = <RichInlineSpan>[];
    final buffer = StringBuffer();
    final failedUntil = <String, int>{};
    var cachedParaBreak = -1;
    var cachedLineEnd = -1;
    var idx = 0;

    int paragraphEndFrom(int pos) {
      if (pos > cachedParaBreak) {
        final p = input.indexOf('\n\n', pos);
        cachedParaBreak = p == -1 ? input.length : p;
      }
      return cachedParaBreak;
    }

    int lineEndFrom(int pos) {
      if (pos > cachedLineEnd) {
        final nl = input.indexOf('\n', pos);
        cachedLineEnd = nl == -1 ? input.length : nl;
      }
      return cachedLineEnd;
    }

    while (idx < input.length) {
      final cu = input.codeUnitAt(idx);

      // URLs diretas: preserva sublinhados e asteriscos internos sem parsear como ênfase
      if ((cu == 0x68 || cu == 0x48) &&
          (_startsWithAsciiIgnoreCase(input, idx, 'https://') ||
              _startsWithAsciiIgnoreCase(input, idx, 'http://'))) {
        final schemeLen = (input.codeUnitAt(idx + 4) == 0x73 || input.codeUnitAt(idx + 4) == 0x53) ? 8 : 7;
        final urlEnd = _scanBareUrlEnd(input, idx + schemeLen);
        if (urlEnd > idx + schemeLen) {
          buffer.write(input.substring(idx, urlEnd));
          idx = urlEnd;
          continue;
        }
      }

      // Negrito / Itálico com asterisco (*texto*, **texto**, ***texto***)
      if (cu == 0x2A) {
        var runEnd = idx;
        while (runEnd < input.length && input.codeUnitAt(runEnd) == 0x2A) {
          runEnd++;
        }
        final runLen = runEnd - idx;

        if ((runLen == 2 || runLen == 3) &&
            runEnd < input.length &&
            !_isWhitespace(input, runEnd)) {
          final kind = runLen == 3 ? '***' : '**';
          final limit = paragraphEndFrom(idx + 2);
          if ((failedUntil[kind] ?? -1) < limit) {
            final closeIdx = _findClosingAsteriskBold(input, idx + 2, runLen == 3, limit);
            if (closeIdx != -1) {
              final content = input.substring(idx + 2, closeIdx);
              final s = startOffset + buffer.length;
              final sub = _parseInlineMarkdown(content, s);
              buffer.write(sub.plainText);
              final e = startOffset + buffer.length;
              if (e > s) {
                spans.add(RichInlineSpan(start: s, end: e, bold: true));
              }
              spans.addAll(sub.spans);
              idx = closeIdx + 2;
              continue;
            }
            failedUntil[kind] = limit;
          }
        } else if (runLen == 1 &&
            runEnd < input.length &&
            !_isWhitespace(input, runEnd) &&
            !_isWordChar(input, idx - 1)) {
          final limit = paragraphEndFrom(idx + 1);
          if ((failedUntil['*'] ?? -1) < limit) {
            final closeIdx = _findClosingSingleEmphasis(input, idx + 1, 0x2A, limit);
            if (closeIdx != -1) {
              final content = input.substring(idx + 1, closeIdx);
              final s = startOffset + buffer.length;
              final sub = _parseInlineMarkdown(content, s);
              buffer.write(sub.plainText);
              final e = startOffset + buffer.length;
              if (e > s) {
                spans.add(RichInlineSpan(start: s, end: e, italic: true));
              }
              spans.addAll(sub.spans);
              idx = closeIdx + 1;
              continue;
            }
            failedUntil['*'] = limit;
          }
        }

        buffer.write(input.substring(idx, runEnd));
        idx = runEnd;
        continue;
      }

      // Itálico com underscore (_texto_), ignorando underscores intrapalavra (ex: my_file_name.txt)
      if (cu == 0x5F) {
        var runEnd = idx;
        while (runEnd < input.length && input.codeUnitAt(runEnd) == 0x5F) {
          runEnd++;
        }
        final runLen = runEnd - idx;
        if (runLen == 1 &&
            runEnd < input.length &&
            !_isWhitespace(input, runEnd) &&
            !_isWordChar(input, idx - 1)) {
          final limit = paragraphEndFrom(idx + 1);
          if ((failedUntil['_'] ?? -1) < limit) {
            final closeIdx = _findClosingSingleEmphasis(input, idx + 1, 0x5F, limit);
            if (closeIdx != -1) {
              final content = input.substring(idx + 1, closeIdx);
              final s = startOffset + buffer.length;
              final sub = _parseInlineMarkdown(content, s);
              buffer.write(sub.plainText);
              final e = startOffset + buffer.length;
              if (e > s) {
                spans.add(RichInlineSpan(start: s, end: e, italic: true));
              }
              spans.addAll(sub.spans);
              idx = closeIdx + 1;
              continue;
            }
            failedUntil['_'] = limit;
          }
        }
        buffer.write(input.substring(idx, runEnd));
        idx = runEnd;
        continue;
      }

      // Tags HTML inline: <u>, <ins>, <q>, <quote> (case-insensitive, sem copiar a cauda)
      if (cu == 0x3C) {
        final isU = _startsWithAsciiIgnoreCase(input, idx, '<u>');
        final isIns = !isU && _startsWithAsciiIgnoreCase(input, idx, '<ins>');
        if (isU || isIns) {
          final openLen = isU ? 3 : 5;
          final closeTag = isU ? '</u>' : '</ins>';
          if ((failedUntil[closeTag] ?? -1) < input.length) {
            final closeIdx = _indexOfAsciiIgnoreCase(input, closeTag, idx + openLen);
            if (closeIdx != -1) {
              if (closeIdx > idx + openLen) {
                final content = input.substring(idx + openLen, closeIdx);
                final s = startOffset + buffer.length;
                final sub = _parseInlineMarkdown(content, s);
                buffer.write(sub.plainText);
                final e = startOffset + buffer.length;
                if (e > s) {
                  spans.add(RichInlineSpan(start: s, end: e, underline: true));
                }
                spans.addAll(sub.spans);
                idx = closeIdx + closeTag.length;
                continue;
              }
            } else {
              failedUntil[closeTag] = input.length;
            }
          }
        } else {
          final isQ = _startsWithAsciiIgnoreCase(input, idx, '<q>');
          final isQuote = !isQ && _startsWithAsciiIgnoreCase(input, idx, '<quote>');
          if (isQ || isQuote) {
            final openLen = isQ ? 3 : 7;
            final closeTag = isQ ? '</q>' : '</quote>';
            if ((failedUntil[closeTag] ?? -1) < input.length) {
              final closeIdx = _indexOfAsciiIgnoreCase(input, closeTag, idx + openLen);
              if (closeIdx != -1) {
                if (closeIdx > idx + openLen) {
                  final content = input.substring(idx + openLen, closeIdx);
                  final s = startOffset + buffer.length;
                  final sub = _parseInlineMarkdown(content, s);
                  buffer.write(sub.plainText);
                  final e = startOffset + buffer.length;
                  if (e > s) {
                    spans.add(RichInlineSpan(start: s, end: e, quote: true));
                  }
                  spans.addAll(sub.spans);
                  idx = closeIdx + closeTag.length;
                  continue;
                }
              } else {
                failedUntil[closeTag] = input.length;
              }
            }
          }
        }
      }

      // Tachado: ~~texto~~
      if (cu == 0x7E) {
        var runEnd = idx;
        while (runEnd < input.length && input.codeUnitAt(runEnd) == 0x7E) {
          runEnd++;
        }
        final runLen = runEnd - idx;
        if (runLen == 2 && runEnd < input.length && !_isWhitespace(input, runEnd)) {
          final limit = paragraphEndFrom(idx + 2);
          if ((failedUntil['~~'] ?? -1) < limit) {
            final closeIdx = _findClosingDoubleChar(input, idx + 2, 0x7E, limit);
            if (closeIdx != -1) {
              final content = input.substring(idx + 2, closeIdx);
              final s = startOffset + buffer.length;
              final sub = _parseInlineMarkdown(content, s);
              buffer.write(sub.plainText);
              final e = startOffset + buffer.length;
              if (e > s) {
                spans.add(RichInlineSpan(start: s, end: e, strikethrough: true));
              }
              spans.addAll(sub.spans);
              idx = closeIdx + 2;
              continue;
            }
            failedUntil['~~'] = limit;
          }
        }
        buffer.write(input.substring(idx, runEnd));
        idx = runEnd;
        continue;
      }

      // Spoiler: ||texto||
      if (cu == 0x7C) {
        var runEnd = idx;
        while (runEnd < input.length && input.codeUnitAt(runEnd) == 0x7C) {
          runEnd++;
        }
        final runLen = runEnd - idx;
        if (runLen == 2 && runEnd < input.length && !_isWhitespace(input, runEnd)) {
          final limit = paragraphEndFrom(idx + 2);
          if ((failedUntil['||'] ?? -1) < limit) {
            final closeIdx = _findClosingDoubleChar(input, idx + 2, 0x7C, limit);
            if (closeIdx != -1) {
              final content = input.substring(idx + 2, closeIdx);
              final s = startOffset + buffer.length;
              final sub = _parseInlineMarkdown(content, s);
              buffer.write(sub.plainText);
              final e = startOffset + buffer.length;
              if (e > s) {
                spans.add(RichInlineSpan(start: s, end: e, spoiler: true));
              }
              spans.addAll(sub.spans);
              idx = closeIdx + 2;
              continue;
            }
            failedUntil['||'] = limit;
          }
        }
        buffer.write(input.substring(idx, runEnd));
        idx = runEnd;
        continue;
      }

      // Código inline: `texto`
      if (cu == 0x60) {
        var runEnd = idx;
        while (runEnd < input.length && input.codeUnitAt(runEnd) == 0x60) {
          runEnd++;
        }
        final tickLen = runEnd - idx;
        final limit = paragraphEndFrom(runEnd);
        final key = '`$tickLen';
        if ((failedUntil[key] ?? -1) < limit) {
          final closeIdx = _findClosingBackticks(input, runEnd, tickLen, limit);
          if (closeIdx != -1) {
            if (closeIdx > runEnd && tickLen == 1) {
              final content = input.substring(runEnd, closeIdx);
              final s = startOffset + buffer.length;
              buffer.write(content);
              final e = startOffset + buffer.length;
              spans.add(RichInlineSpan(start: s, end: e, monospace: true));
              idx = closeIdx + tickLen;
              continue;
            } else if (closeIdx > runEnd) {
              // Preserva inline code multi-crase literalmente caso contenha crase interna
              final rawCode = input.substring(idx, closeIdx + tickLen);
              buffer.write(rawCode);
              idx = closeIdx + tickLen;
              continue;
            }
          } else {
            failedUntil[key] = limit;
          }
        }
        buffer.write(input.substring(idx, runEnd));
        idx = runEnd;
        continue;
      }

      // Links: [texto](url)
      if (cu == 0x5B) {
        final lineEnd = lineEndFrom(idx + 1);
        if ((failedUntil[']'] ?? -1) < lineEnd) {
          var bracketEnd = idx + 1;
          while (bracketEnd < lineEnd && input.codeUnitAt(bracketEnd) != 0x5D) {
            bracketEnd++;
          }
          if (bracketEnd >= lineEnd) {
            failedUntil[']'] = lineEnd;
          } else if (bracketEnd > idx + 1 &&
              bracketEnd + 1 < lineEnd &&
              input.codeUnitAt(bracketEnd + 1) == 0x28) {
            var parenEnd = bracketEnd + 2;
            while (parenEnd < lineEnd && input.codeUnitAt(parenEnd) != 0x29) {
              parenEnd++;
            }
            if (parenEnd < lineEnd && parenEnd > bracketEnd + 2) {
              final linkText = input.substring(idx + 1, bracketEnd);
              final linkUrl = input.substring(bracketEnd + 2, parenEnd);
              final s = startOffset + buffer.length;
              buffer.write(linkText);
              final e = startOffset + buffer.length;
              spans.add(RichInlineSpan(start: s, end: e, linkUrl: linkUrl));
              idx = parenEnd + 1;
              continue;
            }
          }
        }
      }

      // Caractere normal
      buffer.writeCharCode(cu);
      idx++;
    }

    return _InlineParseResult(buffer.toString(), spans);
  }
}

class _InlineParseResult {
  final String plainText;
  final List<RichInlineSpan> spans;
  _InlineParseResult(this.plainText, this.spans);
}
