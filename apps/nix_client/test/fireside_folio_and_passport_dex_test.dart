import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/cultural_item.dart';
import 'package:nix_client/features/media/passport_dex_sheet.dart';
import 'package:nix_client/state/nix_state.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fichas Técnicas Fireside Folio e Capas 3D PassportDex (Seções 13 e 14)', () {
    testWidgets('Livros exibem cabeçalho e seção editorial Fireside Folio completa', (tester) async {
      final state = NixState(loadMockData: false);

      const book = CulturalItem(
        id: 'book_asimov_01',
        title: 'Short Science Fiction Stories',
        creatorOrYear: 'Isaac Asimov, 1952',
        creator: 'Isaac Asimov',
        category: CulturalCategory.books,
        monogram: 'SF',
        releaseYear: 1952,
        language: 'Inglês',
        license: 'Domínio Público Verificado (Edição de 1952)',
        synopsis: 'Coletânea canônica de contos de ficção científica da era de ouro.',
        genres: ['Ficção Científica', 'Contos'],
        externalIds: {'ISBN': '978-0-123456-78-9', 'OpenLibrary': 'OL1234567M'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<NixState>.value(
            value: state,
            child: const Scaffold(
              body: PassportDexSheet(item: book),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Cabeçalho editorial
      expect(find.text('FICHA EDITORIAL · FIRESIDE FOLIO'), findsOneWidget);
      expect(find.text('Short Science Fiction Stories'), findsOneWidget);
      expect(find.text('Isaac Asimov, 1952'), findsOneWidget);

      // Seção editorial
      expect(find.text('Ficha Editorial · Fireside Folio'), findsOneWidget);
      expect(find.text('Isaac Asimov'), findsOneWidget);
      expect(find.text('Inglês'), findsOneWidget);
      expect(find.text('1952'), findsOneWidget);
      expect(find.text('Domínio Público Verificado (Edição de 1952)'), findsOneWidget);
      expect(find.text('ISBN: 978-0-123456-78-9 · OpenLibrary: OL1234567M'), findsOneWidget);

      // Sinopse e gêneros
      expect(find.text('Coletânea canônica de contos de ficção científica da era de ouro.'), findsOneWidget);
      expect(find.text('Ficção Científica'), findsOneWidget);
    });

    testWidgets('Filmes e animes exibem cabeçalho padrão de Acervo Cultural', (tester) async {
      final state = NixState(loadMockData: false);

      const movie = CulturalItem(
        id: 'movie_interstellar',
        title: 'Interstellar',
        creatorOrYear: 'Christopher Nolan, 2014',
        category: CulturalCategory.movies,
        monogram: 'IN',
        releaseYear: 2014,
        synopsis: 'Uma equipe de exploradores viaja através de um buraco de minhoca.',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<NixState>.value(
            value: state,
            child: const Scaffold(
              body: PassportDexSheet(item: movie),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('FICHA DA OBRA · ACERVO CULTURAL'), findsOneWidget);
      expect(find.text('Interstellar'), findsOneWidget);
      expect(find.text('Ficha Editorial · Fireside Folio'), findsNothing);
    });
  });
}
