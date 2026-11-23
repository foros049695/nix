import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/media/collection_importer.dart';
import 'package:nix_client/core/models/cultural_item.dart';
import 'package:nix_client/state/nix_state.dart';

void main() {
  group('CollectionImporter Unit & Security Tests', () {
    test('parses Letterboxd CSV export accurately', () {
      const csv = '''Date,Name,Year,Letterboxd URI,Rating,Rewatch,Tags,Watched Date
2026-01-10,Blade Runner 2049,2017,https://boxd.it/test,4.5,No,cyberpunk,2026-01-10
2026-02-15,Solaris,1972,https://boxd.it/sol,5.0,No,sci-fi,2026-02-15
''';
      final preview = CollectionImporter.parse(
        rawContent: csv,
        fileName: 'diary.csv',
      );

      expect(preview.sourceType, CollectionSourceType.letterboxd);
      expect(preview.items.length, 2);
      expect(preview.items[0].title, 'Blade Runner 2049');
      expect(preview.items[0].category, CulturalCategory.movies);
      expect(preview.items[0].rating, '9.0'); // 4.5 * 2
      expect(preview.items[1].title, 'Solaris');
      expect(preview.items[1].rating, '10.0'); // 5.0 * 2
    });

    test('parses Goodreads CSV export with pages and author', () {
      const csv = '''Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,Publisher,Binding,Number of Pages,Year Published,Original Publication Year,Date Read,Date Added,Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,Private Notes,Read Count,Recommended For,Recommended By,Owned Copies
123,"Neuromancer","William Gibson","Gibson, William",,="0441569595",="9780441569595",5,3.91,Ace,Paperback,271,2000,1984,2026/01/01,2026/01/01,"read, sci-fi","read (#1), sci-fi (#1)",read,"Masterpiece of cyberpunk",,,,1,,,0
''';
      final preview = CollectionImporter.parse(
        rawContent: csv,
        fileName: 'goodreads_library_export.csv',
      );

      expect(preview.sourceType, CollectionSourceType.goodreads);
      expect(preview.items.length, 1);
      expect(preview.items[0].title, 'Neuromancer');
      expect(preview.items[0].category, CulturalCategory.books);
      expect(preview.items[0].total, 271);
      expect(preview.items[0].review, 'Masterpiece of cyberpunk');
    });

    test('parses MyAnimeList XML/HTML export without executing scripts', () {
      const html = '''
<?xml version="1.0" encoding="UTF-8" ?>
<myanimelist>
<myinfo><user_name>test</user_name></myinfo>
<script>alert("malicious")</script>
<anime>
  <series_animedb_id>1</series_animedb_id>
  <series_title>Cowboy Bebop</series_title>
  <series_type>TV</series_type>
  <series_episodes>26</series_episodes>
  <my_watched_episodes>26</my_watched_episodes>
  <my_score>10</my_score>
  <my_status>Completed</my_status>
</anime>
</myanimelist>
''';
      final preview = CollectionImporter.parse(
        rawContent: html,
        fileName: 'animelist.xml',
      );

      expect(preview.sourceType, CollectionSourceType.myanimelist);
      expect(preview.items.length, 1);
      expect(preview.items[0].title, 'Cowboy Bebop');
      expect(preview.items[0].category, CulturalCategory.anime);
      expect(preview.items[0].current, 26);
      expect(preview.items[0].total, 26);
      expect(preview.items[0].rating, '10');
    });

    test('detects duplicates against existing Acervo items', () {
      const csv = '''Name,Year,Letterboxd URI,Rating
Stalker,1979,https://boxd.it/stk,5.0
''';
      const existingItem = CulturalItem(
        id: 'existing_stalker',
        title: 'Stalker',
        creatorOrYear: '1979',
        category: CulturalCategory.movies,
        monogram: 'S',
      );

      final preview = CollectionImporter.parse(
        rawContent: csv,
        fileName: 'export.csv',
        existingItems: [existingItem],
      );

      expect(preview.items.length, 1);
      expect(preview.items[0].isPotentialDuplicate, isTrue);
      expect(preview.duplicateCount, 1);
    });

    test('imports collection into NixState transactionally', () {
      final state = NixState(loadMockData: true);
      const csv = '''Title,Author,Type,Rating
Dune,Frank Herbert,Book,9.5
''';
      final preview = CollectionImporter.parse(
        rawContent: csv,
        fileName: 'generic.csv',
        existingItems: state.userProfile.culturalItems,
      );

      final count = state.importCulturalItems(
        preview.items.map((i) => i.toCulturalItem()).toList(),
      );

      expect(count, 1);
      expect(state.userProfile.culturalItems.any((i) => i.title == 'Dune'), isTrue);
    });
  });
}
