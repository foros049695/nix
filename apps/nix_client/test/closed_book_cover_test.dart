import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/cultural_item.dart';
import 'package:nix_client/core/models/cultural_tracking.dart';
import 'package:nix_client/features/profile/cultural_cover_art.dart';

void main() {
  testWidgets('CulturalCoverArt renderiza livros 2.5D fechados, mangá, vinil e pôster', (tester) async {
    final bookItem = CulturalItem(
      id: 'book_1',
      title: 'Anne of Green Gables',
      creatorOrYear: 'L. M. Montgomery (1908)',
      monogram: 'AG',
      category: CulturalCategory.books,
      tracking: const CulturalTracking(),
    );

    final mangaItem = CulturalItem(
      id: 'manga_1',
      title: 'Berserk',
      creatorOrYear: 'Kentaro Miura (1989)',
      monogram: 'BK',
      category: CulturalCategory.manga,
      tracking: const CulturalTracking(),
    );

    final vinylItem = CulturalItem(
      id: 'music_1',
      title: 'Dark Side of the Moon',
      creatorOrYear: 'Pink Floyd (1973)',
      monogram: 'PF',
      category: CulturalCategory.music,
      tracking: const CulturalTracking(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CulturalCoverArt(item: bookItem, width: 120),
              CulturalCoverArt(item: mangaItem, width: 120),
              CulturalCoverArt(item: vinylItem, width: 120),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CulturalCoverArt), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}
