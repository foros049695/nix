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
    this.linkUrl,
  });

  bool get hasAnyStyle =>
      bold || italic || underline || strikethrough || monospace || spoiler || (linkUrl != null && linkUrl!.isNotEmpty);

  RichInlineSpan copyWith({
    int? start,
    int? end,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    bool? monospace,
    bool? spoiler,
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
      if (_hasActiveStyles()) {
        _spans.add(RichInlineSpan(
          start: changePos,
          end: changePos + diff,
          bold: activeBold,
          italic: activeItalic,
          underline: activeUnderline,
          strikethrough: activeStrikethrough,
          monospace: activeMonospace,
          spoiler: activeSpoiler,
          linkUrl: activeLinkUrl,
        ));
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
    bool b = false, it = false, u = false, st = false, mono = false, sp = false;
    String? lk;

    for (final s in _spans) {
      if (prevPos >= s.start && prevPos < s.end) {
        if (s.bold) b = true;
        if (s.italic) it = true;
        if (s.underline) u = true;
        if (s.strikethrough) st = true;
        if (s.monospace) mono = true;
        if (s.spoiler) sp = true;
        if (s.linkUrl != null) lk = s.linkUrl;
      }
    }
    activeBold = b;
    activeItalic = it;
    activeUnderline = u;
    activeStrikethrough = st;
    activeMonospace = mono;
    activeSpoiler = sp;
    activeLinkUrl = lk;
  }

  void _normalizeSpans() {
    // Remove spans inválidos ou vazios
    _spans.removeWhere((s) => s.start >= s.end || s.start < 0 || s.end > text.length || !s.hasAnyStyle);
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
  void toggleBulletList() => setBlockType(RichBlockType.bulletList);
  void toggleNumberedList() => setBlockType(RichBlockType.numberedList);
  void toggleChecklist() => setBlockType(RichBlockType.checklist);

  void toggleChecklistState([int? lineIdx]) {
    final idx = lineIdx ?? currentLineIndex;
    if (idx < _lineBlocks.length && _lineBlocks[idx].type == RichBlockType.checklist) {
      _lineBlocks[idx].isChecked = !_lineBlocks[idx].isChecked;
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
      String linePrefix = '';

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
            color: const Color(0xFFCBD5E1),
          );
          linePrefix = '❝ ';
          break;
        case RichBlockType.codeBlock:
          lineStyle = baseStyle.copyWith(
            fontFamily: 'monospace',
            backgroundColor: const Color(0x33000000),
            color: const Color(0xFF38BDF8),
          );
          break;
        case RichBlockType.bulletList:
          linePrefix = '• ';
          break;
        case RichBlockType.numberedList:
          linePrefix = '${lineIdx + 1}. ';
          break;
        case RichBlockType.checklist:
          linePrefix = lineBlock.isChecked ? '☑ ' : '☐ ';
          if (lineBlock.isChecked) {
            lineStyle = baseStyle.copyWith(
              decoration: TextDecoration.lineThrough,
              color: const Color(0xFF64748B),
            );
          }
          break;
        case RichBlockType.divider:
          lineStyle = baseStyle.copyWith(
            color: const Color(0xFF475569),
            fontWeight: FontWeight.bold,
          );
          break;
        case RichBlockType.paragraph:
          break;
      }

      final lineChildren = <InlineSpan>[];
      if (linePrefix.isNotEmpty) {
        lineChildren.add(TextSpan(
          text: linePrefix,
          style: lineStyle.copyWith(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF7C3AED), // Nix Purple Accent
          ),
        ));
      }

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
              if (s.linkUrl != null) linkUrl = s.linkUrl;
              nextBoundary = min<int>(nextBoundary, s.end);
            } else if (s.start > currentPos) {
              nextBoundary = min<int>(nextBoundary, s.start);
            }
          }

          final segmentLength = nextBoundary - currentPos;
          final segmentText = text.substring(currentPos, currentPos + segmentLength);

          TextStyle segStyle = lineStyle;
          if (isBold) {
            segStyle = segStyle.copyWith(fontWeight: FontWeight.bold);
          }
          if (isItalic) {
            segStyle = segStyle.copyWith(fontStyle: FontStyle.italic);
          }
          if (isUnderline && isStrike) {
            segStyle = segStyle.copyWith(decoration: TextDecoration.combine([TextDecoration.underline, TextDecoration.lineThrough]));
          } else if (isUnderline) {
            segStyle = segStyle.copyWith(decoration: TextDecoration.underline);
          } else if (isStrike) {
            segStyle = segStyle.copyWith(decoration: TextDecoration.lineThrough);
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

    for (var lineIdx = 0; lineIdx < lines.length; lineIdx++) {
      final lineText = lines[lineIdx];
      final lineBlock = (lineIdx < _lineBlocks.length) ? _lineBlocks[lineIdx] : RichLineBlock();
      final lineLength = lineText.length;
      final lineEnd = globalOffset + lineLength;

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
        case RichBlockType.bulletList: prefix = '- '; break;
        case RichBlockType.numberedList: prefix = '${lineIdx + 1}. '; break;
        case RichBlockType.checklist: prefix = lineBlock.isChecked ? '- [x] ' : '- [ ] '; break;
        case RichBlockType.divider: prefix = '---\n'; break;
        case RichBlockType.paragraph: break;
      }

      out.write(prefix);

      if (lineLength > 0 && lineBlock.type != RichBlockType.divider) {
        var currentPos = globalOffset;

        while (currentPos < lineEnd) {
          bool isBold = false;
          bool isItalic = false;
          bool isUnderline = false;
          bool isStrike = false;
          bool isMono = false;
          bool isSpoiler = false;
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
              if (s.linkUrl != null) linkUrl = s.linkUrl;
              nextBoundary = min<int>(nextBoundary, s.end);
            } else if (s.start > currentPos) {
              nextBoundary = min<int>(nextBoundary, s.start);
            }
          }

          final segmentLength = nextBoundary - currentPos;
          var seg = text.substring(currentPos, currentPos + segmentLength);

          if (isBold) seg = '**$seg**';
          if (isItalic) seg = '*$seg*';
          if (isUnderline) seg = '<u>$seg</u>';
          if (isStrike) seg = '~~$seg~~';
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
    final plainLines = <String>[];
    var globalCharCount = 0;

    for (var i = 0; i < rawLines.length; i++) {
      var raw = rawLines[i];
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
      } else if (raw.startsWith('> ')) {
        blockType = RichBlockType.blockquote;
        raw = raw.substring(2);
      } else if (raw.startsWith('- [x] ') || raw.startsWith('- [X] ')) {
        blockType = RichBlockType.checklist;
        isChecked = true;
        raw = raw.substring(6);
      } else if (raw.startsWith('- [ ] ')) {
        blockType = RichBlockType.checklist;
        isChecked = false;
        raw = raw.substring(6);
      } else if (raw.startsWith('- ') || raw.startsWith('* ')) {
        blockType = RichBlockType.bulletList;
        raw = raw.substring(2);
      } else if (RegExp(r'^\d+\.\s').hasMatch(raw)) {
        blockType = RichBlockType.numberedList;
        final match = RegExp(r'^\d+\.\s').firstMatch(raw)!;
        raw = raw.substring(match.end);
      } else if (raw == '---' || raw == '***' || raw == '___') {
        blockType = RichBlockType.divider;
        raw = '──────────';
      }

      _lineBlocks.add(RichLineBlock(type: blockType, isChecked: isChecked));

      // Parsing de formatações inline nesta linha
      final parsed = _parseInlineMarkdown(raw, globalCharCount);
      plainLines.add(parsed.plainText);
      _spans.addAll(parsed.spans);

      globalCharCount += parsed.plainText.length + 1; // +1 para \n
    }

    final newPlainText = plainLines.join('\n');
    _lastText = newPlainText;
    value = TextEditingValue(
      text: newPlainText,
      selection: TextSelection.collapsed(offset: newPlainText.length),
    );
    _normalizeSpans();
    notifyListeners();
  }

  static _InlineParseResult _parseInlineMarkdown(String input, int startOffset) {
    final spans = <RichInlineSpan>[];
    final buffer = StringBuffer();
    var idx = 0;

    while (idx < input.length) {
      // Negrito: **texto**
      if (input.startsWith('**', idx)) {
        final closeIdx = input.indexOf('**', idx + 2);
        if (closeIdx != -1) {
          final content = input.substring(idx + 2, closeIdx);
          final s = startOffset + buffer.length;
          final sub = _parseInlineMarkdown(content, s);
          buffer.write(sub.plainText);
          final e = startOffset + buffer.length;
          spans.add(RichInlineSpan(start: s, end: e, bold: true));
          spans.addAll(sub.spans);
          idx = closeIdx + 2;
          continue;
        }
      }

      // Sublinhado: <u>texto</u>
      if (input.startsWith('<u>', idx)) {
        final closeIdx = input.indexOf('</u>', idx + 3);
        if (closeIdx != -1) {
          final content = input.substring(idx + 3, closeIdx);
          final s = startOffset + buffer.length;
          final sub = _parseInlineMarkdown(content, s);
          buffer.write(sub.plainText);
          final e = startOffset + buffer.length;
          spans.add(RichInlineSpan(start: s, end: e, underline: true));
          spans.addAll(sub.spans);
          idx = closeIdx + 4;
          continue;
        }
      }

      // Tachado: ~~texto~~
      if (input.startsWith('~~', idx)) {
        final closeIdx = input.indexOf('~~', idx + 2);
        if (closeIdx != -1) {
          final content = input.substring(idx + 2, closeIdx);
          final s = startOffset + buffer.length;
          final sub = _parseInlineMarkdown(content, s);
          buffer.write(sub.plainText);
          final e = startOffset + buffer.length;
          spans.add(RichInlineSpan(start: s, end: e, strikethrough: true));
          spans.addAll(sub.spans);
          idx = closeIdx + 2;
          continue;
        }
      }

      // Spoiler: ||texto||
      if (input.startsWith('||', idx)) {
        final closeIdx = input.indexOf('||', idx + 2);
        if (closeIdx != -1) {
          final content = input.substring(idx + 2, closeIdx);
          final s = startOffset + buffer.length;
          final sub = _parseInlineMarkdown(content, s);
          buffer.write(sub.plainText);
          final e = startOffset + buffer.length;
          spans.add(RichInlineSpan(start: s, end: e, spoiler: true));
          spans.addAll(sub.spans);
          idx = closeIdx + 2;
          continue;
        }
      }

      // Código inline: `texto`
      if (input.startsWith('`', idx)) {
        final closeIdx = input.indexOf('`', idx + 1);
        if (closeIdx != -1) {
          final content = input.substring(idx + 1, closeIdx);
          final s = startOffset + buffer.length;
          buffer.write(content);
          final e = startOffset + buffer.length;
          spans.add(RichInlineSpan(start: s, end: e, monospace: true));
          idx = closeIdx + 1;
          continue;
        }
      }

      // Itálico: *texto* ou _texto_
      if ((input[idx] == '*' || input[idx] == '_') && (idx + 1 < input.length)) {
        final marker = input[idx];
        final closeIdx = input.indexOf(marker, idx + 1);
        if (closeIdx != -1) {
          final content = input.substring(idx + 1, closeIdx);
          final s = startOffset + buffer.length;
          final sub = _parseInlineMarkdown(content, s);
          buffer.write(sub.plainText);
          final e = startOffset + buffer.length;
          spans.add(RichInlineSpan(start: s, end: e, italic: true));
          spans.addAll(sub.spans);
          idx = closeIdx + 1;
          continue;
        }
      }

      // Links: [texto](url)
      if (input[idx] == '[') {
        final bracketEnd = input.indexOf(']', idx + 1);
        if (bracketEnd != -1 && bracketEnd + 1 < input.length && input[bracketEnd + 1] == '(') {
          final parenEnd = input.indexOf(')', bracketEnd + 2);
          if (parenEnd != -1) {
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

      // Caractere normal
      buffer.write(input[idx]);
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
