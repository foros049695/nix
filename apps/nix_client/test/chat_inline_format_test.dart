import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/features/chat/chat_inline_format.dart';

void main() {
  test('formatação seleciona o conteúdo e mantém espaços e emoji', () {
    const value = TextEditingValue(
      text: ' oi 🙂 fim',
      selection: TextSelection(baseOffset: 0, extentOffset: 7),
    );
    final formatted = ChatInlineFormat.bold.apply(value)!;
    expect(formatted.text, ' **oi 🙂** fim');
    expect(formatted.selection.textInside(formatted.text), 'oi 🙂');
    expect(
      ChatInlineFormat.italic.apply(const TextEditingValue(text: 'texto')),
      isNull,
    );
  });

  testWidgets('texto formatado usa spans e links externos ficam literais',
      (tester) async {
    Future<void> show(String text) => tester.pumpWidget(MaterialApp(
          home: ChatInlineText(text, style: const TextStyle()),
        ));
    await show('**negrito** e ~~riscado~~');
    final text = tester.widget<Text>(find.byType(Text).last);
    final spans = (text.textSpan as TextSpan).children!.cast<TextSpan>();
    expect(spans[0].style!.fontWeight, FontWeight.bold);
    expect(spans[2].style!.decoration, TextDecoration.lineThrough);
    const link = '**negrito** ![img](https://example.test/a.png)';
    await show(link);
    expect(find.text(link), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('ChatInlineText renderiza sublinhado e spoiler interativo tap-to-reveal estilo Telegram', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ChatInlineText('Mensagem com <u>sublinhado</u> e ||segredo confidencial||', style: TextStyle()),
      ),
    ));

    await tester.pumpAndSettle();

    // Encontra o widget de spoiler
    expect(find.byType(ChatSpoilerText), findsOneWidget);
    // Antes do toque, texto do segredo está oculto em '•'
    expect(find.text('segredo confidencial'), findsNothing);

    // Toca no spoiler para revelar
    await tester.tap(find.byType(ChatSpoilerText));
    await tester.pumpAndSettle();

    // Agora o texto revelado está visível
    expect(find.text('segredo confidencial'), findsOneWidget);
  });
}
