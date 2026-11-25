import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/archive/archive_markdown.dart';
import 'package:nix_client/core/rich_text/nix_rich_text_controller.dart';

void main() {
  group('NixRichTextController WYSIWYG Tests', () {
    test('Aplica Negrito visual sem inserir asteriscos brutos no campo de texto', () {
      final controller = NixRichTextController(text: 'Palavra de teste');
      expect(controller.text, 'Palavra de teste');

      // Seleciona "Palavra" (0..7)
      controller.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
      controller.toggleBold();

      // O texto exibido continua limpo, sem asteriscos
      expect(controller.text, 'Palavra de teste');
      expect(controller.spans.length, 1);
      expect(controller.spans.first.bold, isTrue);
      expect(controller.spans.first.start, 0);
      expect(controller.spans.first.end, 7);

      // Serializa canonicamente para Markdown
      final md = controller.toMarkdown();
      expect(md, '**Palavra** de teste');

      // Remove negrito
      controller.toggleBold();
      expect(controller.toMarkdown(), 'Palavra de teste');
    });

    test('Ativa modo itálico com cursor colapsado e aplica aos próximos caracteres digitados', () {
      final controller = NixRichTextController(text: 'Olá ');
      controller.selection = const TextSelection.collapsed(offset: 4);

      // Ativa itálico sem seleção
      controller.toggleItalic();
      expect(controller.activeItalic, isTrue);

      // Simula digitação de "Mundo"
      controller.text = 'Olá Mundo';
      expect(controller.text, 'Olá Mundo');

      // O trecho digitado "Mundo" (4..9) herda o itálico
      final md = controller.toMarkdown();
      expect(md, 'Olá *Mundo*');
    });

    test('Suporta Sublinhado, Tachado, Código inline e Links sem expor tags', () {
      final controller = NixRichTextController(text: 'Sublinhado e Código');

      controller.selection = const TextSelection(baseOffset: 0, extentOffset: 10);
      controller.toggleUnderline();

      controller.selection = const TextSelection(baseOffset: 13, extentOffset: 19);
      controller.toggleMonospace();

      expect(controller.text, 'Sublinhado e Código');
      final md = controller.toMarkdown();
      expect(md, '<u>Sublinhado</u> e `Código`');

      // Compilação com sanitização para o Archive Ed25519
      final html = compileArchiveMarkdown(md);
      expect(html, contains('<u>Sublinhado</u>'));
      expect(html, contains('<code>Código</code>'));
    });

    test('Suporta cabeçalhos H1..H6, Citações e Checklists', () {
      final controller = NixRichTextController(text: 'Título Principal\nItem da lista');
      controller.selection = const TextSelection.collapsed(offset: 2); // Linha 0
      controller.toggleHeading(1);

      controller.selection = const TextSelection.collapsed(offset: 20); // Linha 1
      controller.toggleChecklist();

      expect(controller.currentLineBlock.type, RichBlockType.checklist);

      final md = controller.toMarkdown();
      expect(md, '# Título Principal\n- [ ] Item da lista');

      // Marca a tarefa como concluída
      controller.toggleChecklistState(1);
      final mdChecked = controller.toMarkdown();
      expect(mdChecked, '# Título Principal\n- [x] Item da lista');
    });

    test('fromMarkdown carrega artigos legados e preserva conteúdo e formatação', () {
      const legacyArticle = '# Artigo Científico\n\nEste é um **estudo** com *destaque* e `código`.\n\n- [ ] Tarefa 1';
      final controller = NixRichTextController.fromMarkdown(legacyArticle);

      // O texto no editor visual deve estar limpo de marcadores
      expect(controller.text, isNot(contains('**')));
      expect(controller.text, isNot(contains('# ')));
      expect(controller.text, contains('Artigo Científico'));
      expect(controller.text, contains('estudo'));

      // E ao serializar de volta, reproduz o Markdown canônico idêntico
      final serialized = controller.toMarkdown();
      expect(serialized, contains('# Artigo Científico'));
      expect(serialized, contains('**estudo**'));
      expect(serialized, contains('*destaque*'));
      expect(serialized, contains('`código`'));
      expect(serialized, contains('- [ ] Tarefa 1'));
    });

    test('Insere tabela Markdown editável', () {
      final controller = NixRichTextController(text: 'Dados:\n');
      controller.selection = const TextSelection.collapsed(offset: 7);
      controller.insertTable(rows: 2, cols: 2);

      expect(controller.text, contains('Coluna 1'));
      expect(controller.text, contains('Valor 1,1'));
      final md = controller.toMarkdown();
      expect(md, contains('| Coluna 1 | Coluna 2 |'));
      expect(md, contains('| --- | --- |'));
    });
  });
}
