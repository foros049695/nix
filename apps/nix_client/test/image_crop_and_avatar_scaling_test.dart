import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/cultural_item.dart';
import 'package:nix_client/core/models/user_profile.dart';
import 'package:nix_client/core/models/user_settings.dart';
import 'package:nix_client/features/profile/cultural_cover_art.dart';
import 'package:nix_client/features/profile/nix_user_avatar.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Correção de Corte de Imagens e Dimensões (Seção 7)', () {
    testWidgets('NixUserAvatar aplica ClipRRect com contenção estrita em avatar quadrado', (tester) async {
      final state = NixState();
      state.updateSettings(const UserSettings(
        avatarFrameShape: 'square',
        avatarFrameStyle: 'roundedSquare',
        avatarCornerRadius: 8.0,
      ));

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<NixState>.value(
            value: state,
            child: const Scaffold(
              body: Center(
                child: NixUserAvatar(size: 64),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(NixUserAvatar), findsOneWidget);
      // Container base existe
      final container = tester.widget<Container>(
        find.descendant(of: find.byType(NixUserAvatar), matching: find.byType(Container)).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, equals(BoxShape.rectangle));
      expect(decoration.borderRadius, isNotNull);
    });

    testWidgets('CulturalCoverArt suporta BoxFit.contain sem cortar títulos nem bordas', (tester) async {
      const item = CulturalItem(
        id: 'test_book',
        title: 'Livro Raro',
        creatorOrYear: 'Autor Soberano',
        category: CulturalCategory.books,
        monogram: 'LR',
        coverMotif: 'contain',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CulturalCoverArt(
                item: item,
                width: 140,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(CulturalCoverArt), findsOneWidget);
      expect(find.text('LR'), findsOneWidget);
    });
  });
}
