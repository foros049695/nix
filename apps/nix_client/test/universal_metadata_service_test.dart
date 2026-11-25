import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/media/universal_metadata_service.dart';
import 'package:nix_transport/nix_transport.dart';

void main() {
  group('UniversalMetadataService — Busca de Metadados Sem Chave de API', () {
    test('MusicBrainz parse recordings e associa Cover Art Archive', () async {
      const mbJson = '''
      {
        "recordings": [
          {
            "id": "rec-1234",
            "title": "So What",
            "artist-credit": [{"name": "Miles Davis"}],
            "releases": [
              {
                "title": "Kind of Blue",
                "date": "1959-08-17",
                "release-group": {"id": "rg-5678"}
              }
            ]
          }
        ]
      }
      ''';

      final service = UniversalMetadataService(
        httpRequester: ({required allowClearnet, body, headers, required method, required uri}) async {
          expect(uri.host, 'musicbrainz.org');
          return mbJson;
        },
      );

      final results = await service.searchMusic('Miles Davis', allowClearnet: true, isTorReady: false);
      expect(results.length, 1);
      final item = results.first;
      expect(item.id, 'nix:work:track:mb:rec-1234');
      expect(item.title, 'So What');
      expect(item.originalTitle, 'Kind of Blue');
      expect(item.creators, 'Miles Davis');
      expect(item.releaseYear, 1959);
      expect(item.kind, 'track');
      expect(item.coverUrl, 'https://coverartarchive.org/release-group/rg-5678/front-250');
      expect(item.sourceName, 'MusicBrainz');
    });

    test('TVmaze parse séries de TV com sinopse sanitizada e ano de estreia', () async {
      const tvmazeJson = '''
      [
        {
          "show": {
            "id": 139,
            "name": "Breaking Bad",
            "premiered": "2008-01-20",
            "genres": ["Drama", "Crime", "Thriller"],
            "summary": "<p>A high school chemistry teacher diagnosed with inoperable lung cancer turns to manufacturing and selling methamphetamine.</p>",
            "image": {"medium": "https://static.tvmaze.com/uploads/images/medium_portrait/0/2400.jpg"},
            "network": {"name": "AMC"}
          }
        }
      ]
      ''';

      final service = UniversalMetadataService(
        httpRequester: ({required allowClearnet, body, headers, required method, required uri}) async {
          expect(uri.host, 'api.tvmaze.com');
          return tvmazeJson;
        },
      );

      final results = await service.searchTvmaze('Breaking Bad', allowClearnet: true, isTorReady: false);
      expect(results.length, 1);
      final item = results.first;
      expect(item.id, 'nix:work:series:tvmaze:139');
      expect(item.title, 'Breaking Bad');
      expect(item.creators, 'AMC');
      expect(item.releaseYear, 2008);
      expect(item.genres, 'Drama, Crime, Thriller');
      expect(item.synopsis, contains('A high school chemistry teacher'));
      expect(item.synopsis, isNot(contains('<p>')));
      expect(item.coverUrl, 'https://static.tvmaze.com/uploads/images/medium_portrait/0/2400.jpg');
      expect(item.kind, 'series');
    });

    test('AniList parse animes e mangás via GraphQL', () async {
      const anilistJson = '''
      {
        "data": {
          "Page": {
            "media": [
              {
                "id": 1,
                "type": "ANIME",
                "title": {"romaji": "Cowboy Bebop", "english": "Cowboy Bebop", "native": "カウボーイビバップ"},
                "description": "Enter a world in the distant future...",
                "seasonYear": 1998,
                "genres": ["Action", "Sci-Fi"],
                "coverImage": {"large": "https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx1-1.jpg"}
              },
              {
                "id": 30002,
                "type": "MANGA",
                "title": {"romaji": "Berserk", "english": "Berserk", "native": "ベルセルク"},
                "description": "Guts is a wanderer and former mercenary...",
                "startDate": {"year": 1989},
                "genres": ["Action", "Dark Fantasy"],
                "coverImage": {"large": "https://s4.anilist.co/file/anilistcdn/media/manga/cover/large/bx30002-1.jpg"}
              }
            ]
          }
        }
      }
      ''';

      final service = UniversalMetadataService(
        httpRequester: ({required allowClearnet, body, headers, required method, required uri}) async {
          expect(method, 'POST');
          expect(uri.host, 'graphql.anilist.co');
          return anilistJson;
        },
      );

      final results = await service.searchAniList('Cowboy Bebop', allowClearnet: true, isTorReady: false);
      expect(results.length, 2);
      expect(results[0].kind, 'anime');
      expect(results[0].title, 'Cowboy Bebop');
      expect(results[0].originalTitle, 'カウボーイビバップ');
      expect(results[0].releaseYear, 1998);

      expect(results[1].kind, 'manga');
      expect(results[1].title, 'Berserk');
      expect(results[1].releaseYear, 1989);
    });

    test('Open Library parse livros com autor e capa', () async {
      const olJson = '''
      {
        "docs": [
          {
            "key": "/works/OL1168007W",
            "title": "Neuromancer",
            "author_name": ["William Gibson"],
            "first_publish_year": 1984,
            "cover_i": 8225261
          }
        ]
      }
      ''';

      final service = UniversalMetadataService(
        httpRequester: ({required allowClearnet, body, headers, required method, required uri}) async {
          expect(uri.host, 'openlibrary.org');
          return olJson;
        },
      );

      final results = await service.searchOpenLibrary('Neuromancer', allowClearnet: true, isTorReady: false);
      expect(results.length, 1);
      final item = results.first;
      expect(item.id, 'nix:work:book:openlibrary:OL1168007W');
      expect(item.title, 'Neuromancer');
      expect(item.creators, 'William Gibson');
      expect(item.releaseYear, 1984);
      expect(item.kind, 'book');
      expect(item.coverUrl, 'https://covers.openlibrary.org/b/id/8225261-M.jpg');
    });

    test('Fail-closed: bloqueia busca se Tor estiver inativo e clearnet for recusado', () async {
      final service = const UniversalMetadataService();
      expect(
        () => service.searchMusic('query', allowClearnet: false, isTorReady: false),
        throwsA(isA<TransportBlockedException>()),
      );
    });
  });
}
