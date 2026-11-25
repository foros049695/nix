import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/pager_appearance.dart';
import 'package:nix_client/features/profile/pager_housing.dart';

void main() {
  group('Pager Assistant Contrast on Black LCD', () {
    testWidgets('Visor preto aplica alto contraste prateado (#F1F5F9) e BlendMode.srcIn na assistente', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PagerHousing(
              reducedMotion: false,
              lcdColor: PagerLcdColor.black,
              screen: const PagerGuide(
                message: 'Status do Pager',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images.isNotEmpty, isTrue);

      final assistantImage = images.firstWhere(
        (img) => (img.image as AssetImage).assetName == 'assets/images/pager_assistant.png',
      );

      expect(assistantImage.color, const Color(0xFFF1F5F9));
      expect(assistantImage.colorBlendMode, BlendMode.srcIn);
    });

    testWidgets('Visor ciano mantém linhas naturais sem forçar tintura prateada', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PagerHousing(
              reducedMotion: false,
              lcdColor: PagerLcdColor.cyan,
              screen: const PagerGuide(
                message: 'Status do Pager',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      final assistantImage = images.firstWhere(
        (img) => (img.image as AssetImage).assetName == 'assets/images/pager_assistant.png',
      );

      expect(assistantImage.color, isNull);
      expect(assistantImage.colorBlendMode, isNull);
    });
  });
}
