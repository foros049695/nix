import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/archive/archive_markdown.dart';
import 'package:nix_client/core/rich_text/nix_rich_text_controller.dart';

String _roundtrip(String markdown) {
  final controller = NixRichTextController();
  controller.loadMarkdown(markdown);
  return controller.toMarkdown();
}

void main() {
  group('NixRichTextController — Roundtrip sem perda (Probe)', () {
    test('preserva underscore e asterisco intrapalavra e em URLs', () {
      const cases = [
        'arquivo my_file_name.txt',
        'https://example.org/a_b_c/d_e',
        'https://example.org/_init_/__main__',
        'expressão foo*bar*baz e 2*3*4',
      ];

      for (final input in cases) {
        final out1 = _roundtrip(input);
        final out2 = _roundtrip(out1);
        expect(out1, equals(input), reason: 'falha no 1º ciclo para: $input');
        expect(out2, equals(input), reason: 'falha no 2º ciclo para: $input');
      }

      final spacedMath = NixRichTextController()..loadMarkdown('2 * 3 * 4 = 24');
      expect(spacedMath.spans, isEmpty);
      expect(spacedMath.toMarkdown(), equals('2 * 3 * 4 = 24'));
    });

    test('preserva marcadores sem fechamento literalmente', () {
      const cases = [
        '2**10 = 1024',
        'preço ~~ aproximado',
        'preço ~~aproximado',
        'nota *sem fechamento',
        'nota _sem fechamento',
      ];

      for (final input in cases) {
        final out1 = _roundtrip(input);
        final out2 = _roundtrip(out1);
        expect(out1, equals(input), reason: 'falha no 1º ciclo para: $input');
        expect(out2, equals(input), reason: 'falha no 2º ciclo para: $input');
      }
    });

    test('preserva listas numeradas em múltiplos ciclos', () {
      const simple = '1. primeiro\n2. segundo';
      expect(_roundtrip(simple), equals(simple));
      expect(_roundtrip(_roundtrip(simple)), equals(simple));

      const styled = '1. **primeiro**\n2. *segundo*\n10. décimo';
      expect(_roundtrip(styled), equals(styled));
      expect(_roundtrip(_roundtrip(styled)), equals(styled));

      const headingWithNumber = '# 1. Introdução\n> 2. Citação numerada';
      expect(_roundtrip(headingWithNumber), equals(headingWithNumber));
    });

    test('preserva blocos de código cercados verbatim sem parsear ênfase interna', () {
      const cases = [
        '```\nfinal a_b = c_d;\n```',
        '```dart\n# comentario\n- item\n1. passo\n---\nfinal p = 2**10;\nfinal s = a_b * c_d;\n```',
        '~~~\nbloco tilde com _sub_ e **ast**\n~~~',
      ];

      for (final input in cases) {
        final controller = NixRichTextController()..loadMarkdown(input);
        expect(controller.spans, isEmpty);
        final out1 = controller.toMarkdown();
        final out2 = _roundtrip(out1);
        expect(out1, equals(input));
        expect(out2, equals(input));
      }
    });

    test('não duplica linhas em branco após divisor horizontal ---', () {
      const cases = [
        '---\nfim',
        'inicio\n---\nfim',
        '---',
      ];

      for (final input in cases) {
        final out1 = _roundtrip(input);
        final out2 = _roundtrip(out1);
        expect(out1, equals(input), reason: 'falha no 1º ciclo para: $input');
        expect(out2, equals(input), reason: 'falha no 2º ciclo para: $input');
      }
    });

    test('mantém formatação válida e compilação canônica do Archive inalteradas', () {
      const doc = '# Título\n\n'
          'Texto com **negrito**, *itálico*, ***ambos***, <u>sublinhado</u>, '
          '~~tachado~~, <q>citação</q>, ||spoiler||, `código` e '
          '[link_a](https://example.org/a_b).\n\n'
          '> Bloco citado\n'
          '- Item A\n'
          '- [x] Feito\n'
          '- [ ] Pendente';

      final loaded = NixRichTextController.fromMarkdown(doc);
      expect(loaded.text, isNot(contains('***')));
      final out = loaded.toMarkdown();
      expect(out, equals(doc));
      expect(compileArchiveMarkdown(out), equals(compileArchiveMarkdown(doc)));

      expect(_roundtrip('um _destaque_ válido'), equals('um *destaque* válido'));
    });

    test('fuzz determinístico: nunca lança exceção em combinações arbitrárias', () {
      final rng = Random(7);
      const alphabet = [
        '*', '_', '`', '|', '~', '[', ']', '(', ')',
        '<u>', '</u>', '<q>', '</q>', '<ins>', '\n',
        '# ', '- ', '> ', 'a', ' ', '1. ', '- [x] ',
        '---', '```', '☐ ', '\u{1F600}',
      ];

      for (var i = 0; i < 2000; i++) {
        final sample = List.generate(
          1 + rng.nextInt(30),
          (_) => alphabet[rng.nextInt(alphabet.length)],
        ).join();
        final controller = NixRichTextController();
        controller.loadMarkdown(sample);
        controller.toMarkdown();
        if (controller.text.isNotEmpty) {
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          );
          controller.toggleBold();
          controller.toMarkdown();
        }
      }
    });

    test('carrega entrada grande (~120k caracteres) em tempo linear sem cópia quadrática da cauda', () {
      final large = List.filled(12000, 'palavra a_b').join(' ');
      expect(large.length, greaterThan(120000));

      final sw = Stopwatch()..start();
      final controller = NixRichTextController()..loadMarkdown(large);
      sw.stop();

      expect(controller.toMarkdown(), equals(large));
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });
}
