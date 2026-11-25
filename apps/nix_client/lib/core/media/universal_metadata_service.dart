import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:nix_transport/nix_transport.dart';
import '../security/fail_closed_http_overrides.dart';
import 'catalog_database.dart';

enum MetadataSourceKind {
  all('Todas as fontes'),
  musicBrainz('MusicBrainz (Música)'),
  tvmaze('TVmaze (Séries & TV)'),
  anilist('AniList (Animes & Mangás)'),
  openLibrary('Open Library (Livros)'),
  wikidata('Wikidata (Geral)'),
  onionSources('Fontes .onion');

  final String label;
  const MetadataSourceKind(this.label);
}

class UniversalMetadataItem {
  final String id;
  final String title;
  final String? originalTitle;
  final String? creators;
  final int? releaseYear;
  final String kind; // 'movie', 'series', 'anime', 'manga', 'book', 'album', 'track'
  final String? genres;
  final String? synopsis;
  final String? coverUrl;
  final String sourceName;
  final Map<String, dynamic> externalIds;

  const UniversalMetadataItem({
    required this.id,
    required this.title,
    this.originalTitle,
    this.creators,
    this.releaseYear,
    required this.kind,
    this.genres,
    this.synopsis,
    this.coverUrl,
    required this.sourceName,
    this.externalIds = const {},
  });

  CatalogWork toCatalogWork() => CatalogWork(
        id: id,
        kind: kind,
        title: title,
        originalTitle: originalTitle,
        creators: creators,
        releaseYear: releaseYear,
        genres: genres,
        summary: synopsis,
        coverThumb: coverUrl,
        externalIds: externalIds,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
}

typedef MetadataHttpRequester = Future<String> Function({
  required String method,
  required Uri uri,
  Map<String, String>? headers,
  String? body,
  required bool allowClearnet,
});

/// Buscador Online Universal de Metadados Públicos sem exigência de chave de API privada.
/// Suporta MusicBrainz + Cover Art Archive, TVmaze, AniList GraphQL, Open Library, Wikidata e Onion v3.
class UniversalMetadataService {
  final MetadataHttpRequester? _httpRequester;

  const UniversalMetadataService({MetadataHttpRequester? httpRequester})
      : _httpRequester = httpRequester;

  static String _generateCircuitIsolation() {
    final random = Random.secure();
    final bytes = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<String> _request({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    String? body,
    required bool allowClearnet,
    required bool isTorReady,
    int socksPort = 9050,
  }) async {
    if (_httpRequester != null) {
      return _httpRequester!(
        method: method,
        uri: uri,
        headers: headers,
        body: body,
        allowClearnet: allowClearnet,
      );
    }

    final reqHeaders = <String, String>{
      'User-Agent': 'NixUniversalMetadata/1.0 ( privacy@projetonix.org )',
      'Accept': 'application/json',
      if (headers != null) ...headers,
    };

    if (allowClearnet && !uri.host.endsWith('.onion')) {
      // Conexão direta HTTPS (Clearnet)
      return NixFailClosedHttpOverrides.runWithExplicitClearnetDownload(action: () async {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 15);
        try {
          final req = method == 'POST'
              ? await client.postUrl(uri)
              : await client.getUrl(uri);
          reqHeaders.forEach((k, v) => req.headers.set(k, v));
          if (body != null) {
            req.headers.contentType = ContentType.json;
            req.write(body);
          }
          final res = await req.close().timeout(const Duration(seconds: 20));
          return await res.transform(utf8.decoder).join();
        } finally {
          client.close();
        }
      });
    }

    // Transporte via Tor SOCKS5 isolado
    if (!isTorReady) {
      throw const TransportBlockedException(
        'Transporte Tor seguro inativo: busca bloqueada (fail-closed).',
      );
    }

    final isolation = _generateCircuitIsolation();
    final connector = Socks5Connector(
      proxyHost: '127.0.0.1',
      proxyPort: socksPort,
      username: isolation,
      password: isolation,
    );

    final res = await connector.httpRequest(
      method,
      uri,
      headers: reqHeaders,
      body: body,
      requireOnionV3: uri.host.endsWith('.onion'),
      timeout: const Duration(seconds: 25),
    );
    return res.body;
  }

  /// Baixa os bytes reais de uma capa através do perfil de transporte configurado (Tor SOCKS5 ou Clearnet).
  Future<Uint8List?> downloadImageBytes(
    String url, {
    required bool allowClearnet,
    required bool isTorReady,
    int socksPort = 9050,
  }) async {
    try {
      final uri = Uri.parse(url);
      final reqHeaders = <String, String>{
        'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      };

      if (allowClearnet && !uri.host.endsWith('.onion')) {
        return await NixFailClosedHttpOverrides.runWithExplicitClearnetDownload(action: () async {
          final client = HttpClient();
          client.connectionTimeout = const Duration(seconds: 15);
          try {
            final req = await client.getUrl(uri);
            reqHeaders.forEach((k, v) => req.headers.set(k, v));
            final res = await req.close().timeout(const Duration(seconds: 25));
            if (res.statusCode >= 200 && res.statusCode < 300) {
              final bytesBuilder = BytesBuilder();
              await for (final chunk in res) {
                bytesBuilder.add(chunk);
              }
              return bytesBuilder.toBytes();
            }
            return null;
          } finally {
            client.close();
          }
        });
      }

      if (!isTorReady) return null;

      final isolation = _generateCircuitIsolation();
      final connector = Socks5Connector(
        proxyHost: '127.0.0.1',
        proxyPort: socksPort,
        username: isolation,
        password: isolation,
      );

      final res = await connector.httpRequest(
        'GET',
        uri,
        headers: reqHeaders,
        requireOnionV3: uri.host.endsWith('.onion'),
        timeout: const Duration(seconds: 25),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return res.bodyBytes;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Busca universal agregada ou específica por fonte.
  Future<List<UniversalMetadataItem>> search({
    required String query,
    required MetadataSourceKind source,
    required bool allowClearnet,
    required bool isTorReady,
    int socksPort = 9050,
    String? customOnionUrl,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];

    final results = <UniversalMetadataItem>[];

    Future<void> runSource(Future<List<UniversalMetadataItem>> Function() fn) async {
      try {
        final items = await fn();
        results.addAll(items);
      } catch (_) {
        // Falha isolada em uma fonte não interrompe as demais na busca agregada
      }
    }

    switch (source) {
      case MetadataSourceKind.all:
        await Future.wait([
          runSource(() => searchMusic(clean, allowClearnet: allowClearnet, isTorReady: isTorReady, socksPort: socksPort)),
          runSource(() => searchTvmaze(clean, allowClearnet: allowClearnet, isTorReady: isTorReady, socksPort: socksPort)),
          runSource(() => searchAniList(clean, allowClearnet: allowClearnet, isTorReady: isTorReady, socksPort: socksPort)),
          runSource(() => searchOpenLibrary(clean, allowClearnet: allowClearnet, isTorReady: isTorReady, socksPort: socksPort)),
          runSource(() => searchWikidata(clean, allowClearnet: allowClearnet, isTorReady: isTorReady, socksPort: socksPort)),
          if (customOnionUrl != null && customOnionUrl.isNotEmpty)
            runSource(() => searchOnion(clean, customOnionUrl: customOnionUrl, isTorReady: isTorReady, socksPort: socksPort)),
        ]);
        break;
      case MetadataSourceKind.musicBrainz:
        return searchMusic(clean, allowClearnet: allowClearnet, isTorReady: isTorReady, socksPort: socksPort);
      case MetadataSourceKind.tvmaze:
        return searchTvmaze(clean, allowClearnet: allowClearnet, isTorReady: isTorReady, socksPort: socksPort);
      case MetadataSourceKind.anilist:
        return searchAniList(clean, allowClearnet: allowClearnet, isTorReady: isTorReady, socksPort: socksPort);
      case MetadataSourceKind.openLibrary:
        return searchOpenLibrary(clean, allowClearnet: allowClearnet, isTorReady: isTorReady, socksPort: socksPort);
      case MetadataSourceKind.wikidata:
        return searchWikidata(clean, allowClearnet: allowClearnet, isTorReady: isTorReady, socksPort: socksPort);
      case MetadataSourceKind.onionSources:
        if (customOnionUrl != null && customOnionUrl.isNotEmpty) {
          return searchOnion(clean, customOnionUrl: customOnionUrl, isTorReady: isTorReady, socksPort: socksPort);
        }
        return const [];
    }

    return results;
  }

  /// Busca de Músicas no MusicBrainz (faixas e álbuns) + Cover Art Archive.
  Future<List<UniversalMetadataItem>> searchMusic(
    String query, {
    required bool allowClearnet,
    required bool isTorReady,
    int socksPort = 9050,
  }) async {
    final encoded = Uri.encodeQueryComponent(query);
    final uri = Uri.parse('https://musicbrainz.org/ws/2/recording?query=$encoded&fmt=json&limit=15');
    final raw = await _request(
      method: 'GET',
      uri: uri,
      allowClearnet: allowClearnet,
      isTorReady: isTorReady,
      socksPort: socksPort,
    );
    return parseMusicBrainzRecordings(raw);
  }

  static List<UniversalMetadataItem> parseMusicBrainzRecordings(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return const [];
      final recordings = decoded['recordings'];
      if (recordings is! List) return const [];

      final list = <UniversalMetadataItem>[];
      for (final rec in recordings) {
        if (rec is! Map) continue;
        final id = rec['id']?.toString() ?? '';
        final title = rec['title']?.toString() ?? 'Sem título';
        final artistCredits = rec['artist-credit'];
        String creators = 'Artista Desconhecido';
        if (artistCredits is List && artistCredits.isNotEmpty) {
          creators = artistCredits
              .map((a) => (a is Map) ? (a['name']?.toString() ?? '') : '')
              .where((s) => s.isNotEmpty)
              .join(', ');
        }
        final releases = rec['releases'];
        String? albumTitle;
        String? rgId;
        int? releaseYear;
        if (releases is List && releases.isNotEmpty) {
          final firstRel = releases.first;
          if (firstRel is Map) {
            albumTitle = firstRel['title']?.toString();
            final date = firstRel['date']?.toString();
            if (date != null && date.length >= 4) {
              releaseYear = int.tryParse(date.substring(0, 4));
            }
            final rg = firstRel['release-group'];
            if (rg is Map) rgId = rg['id']?.toString();
          }
        }
        final coverUrl = rgId != null ? 'https://coverartarchive.org/release-group/$rgId/front-250' : null;

        list.add(UniversalMetadataItem(
          id: 'nix:work:track:mb:$id',
          title: title,
          originalTitle: albumTitle,
          creators: creators,
          releaseYear: releaseYear,
          kind: 'track',
          coverUrl: coverUrl,
          sourceName: 'MusicBrainz',
          externalIds: {
            'musicbrainz_recording': id,
            if (rgId != null) 'musicbrainz_release_group': rgId,
          },
        ));
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// Busca de Séries de TV via TVmaze API.
  Future<List<UniversalMetadataItem>> searchTvmaze(
    String query, {
    required bool allowClearnet,
    required bool isTorReady,
    int socksPort = 9050,
  }) async {
    final encoded = Uri.encodeQueryComponent(query);
    final uri = Uri.parse('https://api.tvmaze.com/search/shows?q=$encoded');
    final raw = await _request(
      method: 'GET',
      uri: uri,
      allowClearnet: allowClearnet,
      isTorReady: isTorReady,
      socksPort: socksPort,
    );
    return parseTvmazeResponse(raw);
  }

  static List<UniversalMetadataItem> parseTvmazeResponse(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) return const [];
      final list = <UniversalMetadataItem>[];
      final tagExp = RegExp(r'<[^>]*>');

      for (final item in decoded) {
        if (item is! Map) continue;
        final show = item['show'];
        if (show is! Map) continue;

        final id = show['id']?.toString() ?? '';
        final title = show['name']?.toString() ?? 'Sem título';
        final premiered = show['premiered']?.toString();
        int? releaseYear;
        if (premiered != null && premiered.length >= 4) {
          releaseYear = int.tryParse(premiered.substring(0, 4));
        }
        final genresList = show['genres'];
        String? genres;
        if (genresList is List && genresList.isNotEmpty) {
          genres = genresList.join(', ');
        }
        final rawSummary = show['summary']?.toString() ?? '';
        final cleanSummary = rawSummary.replaceAll(tagExp, '').trim();

        String? coverUrl;
        final image = show['image'];
        if (image is Map) {
          coverUrl = image['medium']?.toString() ?? image['original']?.toString();
        }

        final network = show['network']?['name']?.toString() ?? show['webChannel']?['name']?.toString();

        list.add(UniversalMetadataItem(
          id: 'nix:work:series:tvmaze:$id',
          title: title,
          creators: network,
          releaseYear: releaseYear,
          kind: 'series',
          genres: genres,
          synopsis: cleanSummary.isNotEmpty ? cleanSummary : null,
          coverUrl: coverUrl,
          sourceName: 'TVmaze',
          externalIds: {'tvmaze_id': id},
        ));
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// Busca de Animes e Mangás via AniList GraphQL.
  Future<List<UniversalMetadataItem>> searchAniList(
    String query, {
    required bool allowClearnet,
    required bool isTorReady,
    int socksPort = 9050,
  }) async {
    const gql = r'''
query ($search: String) {
  Page(page: 1, perPage: 12) {
    media(search: $search) {
      id
      type
      title { romaji english native }
      description(asHtml: false)
      seasonYear
      startDate { year }
      genres
      coverImage { large medium }
      format
    }
  }
}
''';
    final body = jsonEncode({
      'query': gql,
      'variables': {'search': query},
    });

    final uri = Uri.parse('https://graphql.anilist.co');
    final raw = await _request(
      method: 'POST',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: body,
      allowClearnet: allowClearnet,
      isTorReady: isTorReady,
      socksPort: socksPort,
    );
    return parseAniListResponse(raw);
  }

  static List<UniversalMetadataItem> parseAniListResponse(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return const [];
      final media = decoded['data']?['Page']?['media'];
      if (media is! List) return const [];

      final list = <UniversalMetadataItem>[];
      for (final m in media) {
        if (m is! Map) continue;
        final id = m['id']?.toString() ?? '';
        final type = m['type']?.toString().toUpperCase();
        final kind = type == 'MANGA' ? 'manga' : 'anime';

        final titles = m['title'];
        String title = 'Sem título';
        String? originalTitle;
        if (titles is Map) {
          title = titles['romaji']?.toString() ?? titles['english']?.toString() ?? titles['native']?.toString() ?? 'Sem título';
          originalTitle = titles['native']?.toString();
        }

        final releaseYear = m['seasonYear'] as int? ?? m['startDate']?['year'] as int?;
        final genresList = m['genres'];
        String? genres;
        if (genresList is List && genresList.isNotEmpty) {
          genres = genresList.join(', ');
        }
        final synopsis = m['description']?.toString();
        final coverUrl = m['coverImage']?['large']?.toString() ?? m['coverImage']?['medium']?.toString();

        list.add(UniversalMetadataItem(
          id: 'nix:work:$kind:anilist:$id',
          title: title,
          originalTitle: originalTitle,
          releaseYear: releaseYear,
          kind: kind,
          genres: genres,
          synopsis: synopsis,
          coverUrl: coverUrl,
          sourceName: 'AniList',
          externalIds: {'anilist_id': id},
        ));
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// Busca de Livros via Open Library API.
  Future<List<UniversalMetadataItem>> searchOpenLibrary(
    String query, {
    required bool allowClearnet,
    required bool isTorReady,
    int socksPort = 9050,
  }) async {
    final encoded = Uri.encodeQueryComponent(query);
    final uri = Uri.parse('https://openlibrary.org/search.json?q=$encoded&limit=15');
    final raw = await _request(
      method: 'GET',
      uri: uri,
      allowClearnet: allowClearnet,
      isTorReady: isTorReady,
      socksPort: socksPort,
    );
    return parseOpenLibraryResponse(raw);
  }

  static List<UniversalMetadataItem> parseOpenLibraryResponse(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return const [];
      final docs = decoded['docs'];
      if (docs is! List) return const [];

      final list = <UniversalMetadataItem>[];
      for (final doc in docs) {
        if (doc is! Map) continue;
        final key = doc['key']?.toString() ?? '';
        final title = doc['title']?.toString() ?? 'Sem título';
        final authors = doc['author_name'];
        String? creators;
        if (authors is List && authors.isNotEmpty) {
          creators = authors.join(', ');
        }
        final releaseYear = doc['first_publish_year'] as int?;
        final coverI = doc['cover_i'];
        final coverUrl = coverI != null ? 'https://covers.openlibrary.org/b/id/$coverI-M.jpg' : null;

        list.add(UniversalMetadataItem(
          id: 'nix:work:book:openlibrary:${key.replaceAll('/works/', '')}',
          title: title,
          creators: creators,
          releaseYear: releaseYear,
          kind: 'book',
          coverUrl: coverUrl,
          sourceName: 'Open Library',
          externalIds: {'openlibrary_key': key},
        ));
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// Busca Geral no Wikidata.
  Future<List<UniversalMetadataItem>> searchWikidata(
    String query, {
    required bool allowClearnet,
    required bool isTorReady,
    int socksPort = 9050,
  }) async {
    final encoded = Uri.encodeQueryComponent(query);
    final uri = Uri.parse('https://www.wikidata.org/w/api.php?action=wbsearchentities&search=$encoded&language=pt&format=json&limit=10');
    final raw = await _request(
      method: 'GET',
      uri: uri,
      allowClearnet: allowClearnet,
      isTorReady: isTorReady,
      socksPort: socksPort,
    );
    return parseWikidataResponse(raw);
  }

  static List<UniversalMetadataItem> parseWikidataResponse(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return const [];
      final search = decoded['search'];
      if (search is! List) return const [];

      final list = <UniversalMetadataItem>[];
      for (final item in search) {
        if (item is! Map) continue;
        final qid = item['id']?.toString() ?? '';
        final label = item['label']?.toString() ?? 'Sem título';
        final description = item['description']?.toString();

        list.add(UniversalMetadataItem(
          id: 'nix:work:wikidata:$qid',
          title: label,
          synopsis: description,
          kind: 'movie', // Categoria padrão adaptável
          sourceName: 'Wikidata',
          externalIds: {'wikidata_id': qid},
        ));
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// Busca em fontes Onion customizadas pelo usuário.
  Future<List<UniversalMetadataItem>> searchOnion(
    String query, {
    required String customOnionUrl,
    required bool isTorReady,
    int socksPort = 9050,
  }) async {
    final baseUri = Uri.parse(customOnionUrl);
    final uri = baseUri.replace(
      queryParameters: {...baseUri.queryParameters, 'q': query},
    );
    final raw = await _request(
      method: 'GET',
      uri: uri,
      allowClearnet: false,
      isTorReady: isTorReady,
      socksPort: socksPort,
    );
    return parseOnionCatalogResponse(raw);
  }

  static List<UniversalMetadataItem> parseOnionCatalogResponse(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) return const [];
      final list = <UniversalMetadataItem>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        list.add(UniversalMetadataItem(
          id: item['id']?.toString() ?? 'nix:onion:${DateTime.now().microsecondsSinceEpoch}',
          title: item['title']?.toString() ?? 'Sem título',
          originalTitle: item['original_title']?.toString(),
          creators: item['creators']?.toString(),
          releaseYear: item['release_year'] as int?,
          kind: item['kind']?.toString() ?? 'movie',
          genres: item['genres']?.toString(),
          synopsis: item['synopsis']?.toString(),
          coverUrl: item['cover_thumb']?.toString(),
          sourceName: 'Onion Source',
        ));
      }
      return list;
    } catch (_) {
      return const [];
    }
  }
}
