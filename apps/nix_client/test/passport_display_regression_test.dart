import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/media/catalog_database.dart';
import 'package:nix_client/core/models/cultural_item.dart';
import 'package:nix_client/core/models/user_settings.dart';
import 'package:nix_client/core/security/local_image_helper.dart';
import 'package:nix_client/core/theme.dart';
import 'package:nix_client/core/theme/nix_palette.dart';
import 'package:nix_client/features/explore/explore_spaces_view.dart';
import 'package:nix_client/features/navigation/app_shell.dart';
import 'package:nix_client/features/profile/cultural_cover_art.dart';
import 'package:nix_client/features/profile/cultural_showcase.dart';
import 'package:nix_client/features/profile/pager_profile.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:provider/provider.dart';

class _LocalCatalog implements CatalogDatabase {
  String? lastQuery;

  @override
  Future<List<CatalogWork>> searchWorks(
      {required String query,
      String? kind,
      String? genre,
      int? releaseYear,
      int limit = 50,
      int offset = 0}) async {
    lastQuery = query;
    return [
      if (query == 'Duna')
        const CatalogWork(
            id: 'duna',
            kind: 'book',
            title: 'Duna',
            creators: 'Frank Herbert',
            releaseYear: 1965,
            coverThumb: 'placeholder:sandworm_dune',
            updatedAt: 0)
    ];
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
      'Capas do catálogo aceitam miniatura embutida e ignoram referências externas',
      () async {
    final png = await File('assets/images/pager_assistant.png').readAsBytes();
    expect(
        LocalImageHelper.readCatalogThumbnail(
                'data:image/png;base64,${base64Encode(png)}')
            ?.bytes
            .length,
        greaterThan(0));
    expect(
        LocalImageHelper.readCatalogThumbnail(
            'https://example.invalid/cover.png'),
        isNull);
    expect(LocalImageHelper.readCatalogThumbnail('file:///etc/passwd'), isNull);
    expect(LocalImageHelper.readCatalogThumbnail('data:image/png;base64,AA=='),
        isNull);
  });

  testWidgets('Passaporte importa ficha local e exibe as três formas de capa',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 790));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = NixState(loadMockData: false);
    addTearDown(state.dispose);
    final db = _LocalCatalog();
    state.setCatalogDatabase(db);
    for (final category in [CulturalCategory.music, CulturalCategory.anime]) {
      state.addCulturalItem(CulturalItem(
          id: category.name,
          title: category.label,
          creatorOrYear: '',
          category: category,
          monogram: 'NX'));
    }
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(
          home:
              Scaffold(body: SingleChildScrollView(child: CulturalShowcase()))),
    ));
    await tester.tap(find.byKey(const Key('passport_search_catalog')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('passport_catalog_query')), 'Duna');
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pumpAndSettle();
    expect(db.lastQuery, 'Duna');
    await tester.tap(find.widgetWithText(ListTile, 'Duna'));
    await tester.pumpAndSettle();
    expect(find.text('Frank Herbert · 1965'), findsOneWidget);
    await tester.tap(find.text('Salvar no Acervo'));
    await tester.pumpAndSettle();
    final book = state.userProfile.culturalItems
        .firstWhere((item) => item.title == 'Duna');
    expect(book.category, CulturalCategory.books);
    expect(book.coverMotif, 'placeholder:sandworm_dune');
    expect(book.isPublicInCardId, isFalse);
    final covers =
        tester.widgetList<CulturalCoverArt>(find.byType(CulturalCoverArt));
    expect(
        covers.map((cover) => cover.item.category),
        containsAll([
          CulturalCategory.music,
          CulturalCategory.books,
          CulturalCategory.anime
        ]));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Contemplação permite arrastar o avatar e preserva escala e posição',
      (tester) async {
    final state = NixState();
    addTearDown(state.dispose);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: Scaffold(body: PagerProfile())),
    ));
    await tester.tap(find.byTooltip('Próxima tela'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Próxima tela'));
    await tester.pumpAndSettle();
    final avatar = find.byKey(const Key('pager_contemplation_avatar'));
    final before = tester.getRect(avatar);
    await tester.drag(avatar, const Offset(25, 45));
    await tester.pumpAndSettle();
    expect(tester.getCenter(avatar).dy, greaterThan(before.center.dy));
    state.updateSettings(state.settings.copyWith(pagerAvatarScale: .52));
    await tester.pumpAndSettle();
    expect(tester.getSize(avatar).width, greaterThan(before.width));
    final restored = UserSettings.fromJson(state.settings.toJson());
    expect(restored.pagerAvatarY, greaterThan(0));
    expect(restored.pagerAvatarScale, .52);
  });

  testWidgets(
      'Explorar cabe em 320 dp com texto ampliado no tema branco e amarelo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = NixState(loadMockData: true);
    addTearDown(state.dispose);
    state.updateThemeMode(NixThemeMode.lightYellow);
    state.updatePalette(NixPaletteType.yellow);
    state.openExploreArea();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        theme: NixTheme.lightYellowTheme,
        home: const AppShell(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.35)),
            child: child!),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ExploreSpacesView), findsOneWidget);
    expect(find.byKey(const Key('floating_mobile_header')), findsOneWidget);
    expect(find.text('Comunidades e canais públicos'), findsOneWidget);
    final before = state.exploreSortAscending;
    await tester.tap(find.byTooltip(
        before ? 'Menos populosos primeiro' : 'Mais populosos primeiro'));
    await tester.pumpAndSettle();
    expect(state.exploreSortAscending, !before);
    expect(tester.takeException(), isNull);
  });
}
