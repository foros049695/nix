import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/pager_appearance.dart';
import 'package:nix_client/features/profile/pager_housing.dart';

/// Regressão: o tema do app usa superfícies opacas para hover/foco. Dentro do
/// LCD do pager isso escondia ícone e nome dos atalhos em hover.
void main() {
  for (final lcd in [PagerLcdColor.cyan, PagerLcdColor.black]) {
    testWidgets('LCD ${lcd.name}: cores de interação são a tinta translúcida',
        (tester) async {
      late ThemeData lcdTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            hoverColor: const Color(0xFF23262D),
            focusColor: const Color(0xFF23262D),
            highlightColor: const Color(0xFF23262D),
            splashColor: const Color(0xFF23262D),
          ),
          home: Scaffold(
            body: PagerHousing(
              reducedMotion: true,
              lcdColor: lcd,
              screen: Builder(builder: (context) {
                lcdTheme = Theme.of(context);
                return const SizedBox.expand();
              }),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ink = lcd.inkColor;
      for (final color in [
        lcdTheme.hoverColor,
        lcdTheme.focusColor,
        lcdTheme.highlightColor,
        lcdTheme.splashColor,
      ]) {
        expect(color.a, lessThan(0.25), reason: 'cor opaca cobriria o conteúdo');
        expect(color.withValues(alpha: 1), ink.withValues(alpha: 1));
      }
    });
  }
}
