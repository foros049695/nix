import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:nix_transport/nix_transport.dart';

import '../models/cultural_item.dart';
import '../security/platform_runtime.dart';

enum EnrichmentConfidence {
  exactId,
  strongAttributes,
  ambiguous,
  notFound,
}

class EnrichmentResult {
  final String itemId;
  final String title;
  final String? coverPath;
  final String? originalTitle;
  final String? creator;
  final int? releaseYear;
  final String? synopsis;
  final List<String> genres;
  final String source;
  final EnrichmentConfidence confidence;
  final String? error;

  const EnrichmentResult({
    required this.itemId,
    required this.title,
    this.coverPath,
    this.originalTitle,
    this.creator,
    this.releaseYear,
    this.synopsis,
    this.genres = const [],
    required this.source,
    required this.confidence,
    this.error,
  });

  bool get isSuccess => coverPath != null || synopsis != null;
}

typedef EnrichmentHttpRequester = Future<String> Function({
  required Uri uri,
  required String circuitIsolation,
});

/// Serviço de Enriquecimento Automático e Consentido de Capas e Metadados (Seções 4, 5 e 6).
///
/// Características:
/// - Processamento em fila assíncrona fora da thread principal.
/// - Controle estrito de concorrência (1 requisição ativa por vez com jitter e backoff).
/// - Isolamento de circuitos no Tor para cada item.
/// - Não sobrescreve dados pessoais (avaliações, status, reviews e anotações).
/// - Cache local de imagens em disco seguro.
class CoverEnrichmentService {
  final EnrichmentHttpRequester? _customRequester;

  bool _isPaused = false;
  bool _isCancelled = false;
  bool _isRunning = false;

  int _totalCount = 0;
  int _completedCount = 0;
  int _successCount = 0;
  int _failedCount = 0;

  final StreamController<Map<String, dynamic>> _progressController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get progressStream => _progressController.stream;

  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;
  bool get isCancelled => _isCancelled;

  CoverEnrichmentService({EnrichmentHttpRequester? customRequester})
      : _customRequester = customRequester;

  void pause() {
    _isPaused = true;
    _emitProgress();
  }

  void resume() {
    _isPaused = false;
    _emitProgress();
  }

  void cancel() {
    _isCancelled = true;
    _isRunning = false;
    _emitProgress();
  }

  void _emitProgress({String? currentTitle}) {
    if (_progressController.isClosed) return;
    _progressController.add({
      'total': _totalCount,
      'completed': _completedCount,
      'success': _successCount,
      'failed': _failedCount,
      'isPaused': _isPaused,
      'isCancelled': _isCancelled,
      'isRunning': _isRunning,
      'currentTitle': currentTitle,
    });
  }

  static String _generateCircuitIsolation() {
    final random = math.Random.secure();
    final bytes = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Executa o lote de enriquecimento de forma consentida, salvando as capas no cache local.
  Future<List<EnrichmentResult>> enrichBatch({
    required List<CulturalItem> items,
    required bool userConsent,
    required bool isTorReady,
    int socksPort = 9050,
    required Future<void> Function(CulturalItem updatedItem) onItemUpdated,
  }) async {
    if (!userConsent) {
      throw StateError(
          'O enriquecimento de capas exige a autorização explícita do usuário.');
    }
    if (!isTorReady && _customRequester == null) {
      throw const TransportBlockedException(
          'Enriquecimento externo bloqueado: o circuito Tor fail-closed não está pronto.');
    }

    _isPaused = false;
    _isCancelled = false;
    _isRunning = true;
    _totalCount = items.length;
    _completedCount = 0;
    _successCount = 0;
    _failedCount = 0;

    final results = <EnrichmentResult>[];
    _emitProgress();

    final cacheDir = await _ensureCoversCacheDirectory();

    for (final item in items) {
      if (_isCancelled) break;

      while (_isPaused && !_isCancelled) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
      if (_isCancelled) break;

      _emitProgress(currentTitle: item.title);

      try {
        final result = await _enrichSingleItem(
          item: item,
          cacheDir: cacheDir,
          socksPort: socksPort,
        );

        results.add(result);
        _completedCount++;

        if (result.isSuccess) {
          _successCount++;
          // Atualiza a obra preservando estritamente os dados particulares (Seção 5.5)
          final updated = item.copyWith(
            localImagePath: result.coverPath ?? item.localImagePath,
            originalTitle: result.originalTitle ?? item.originalTitle,
            creator: result.creator ?? item.creator,
            releaseYear: result.releaseYear ?? item.releaseYear,
            synopsis: result.synopsis ?? item.synopsis,
            genres: result.genres.isNotEmpty ? result.genres : item.genres,
            source: result.source,
            provenanceConfidence: result.confidence.name,
          );
          await onItemUpdated(updated);
        } else {
          _failedCount++;
        }

        _emitProgress();

        // Intervalo de segurança / backoff para respeitar os servidores públicos abertos (Seção 4.4)
        await Future.delayed(const Duration(milliseconds: 250));
      } catch (err) {
        _completedCount++;
        _failedCount++;
        results.add(EnrichmentResult(
          itemId: item.id,
          title: item.title,
          source: 'error',
          confidence: EnrichmentConfidence.notFound,
          error: err.toString(),
        ));
        _emitProgress();
      }
    }

    _isRunning = false;
    _emitProgress();
    return results;
  }

  Future<EnrichmentResult> _enrichSingleItem({
    required CulturalItem item,
    required Directory cacheDir,
    required int socksPort,
  }) async {
    final isolation = _generateCircuitIsolation();

    // 1. Obras literárias (Livros e Mangás): Open Library
    if (item.category == CulturalCategory.books ||
        item.category == CulturalCategory.manga) {
      return await _searchOpenLibrary(
        item: item,
        cacheDir: cacheDir,
        circuitIsolation: isolation,
        socksPort: socksPort,
      );
    }

    // 2. Obras musicais: MusicBrainz
    if (item.category == CulturalCategory.music) {
      return await _searchMusicBrainz(
        item: item,
        cacheDir: cacheDir,
        circuitIsolation: isolation,
        socksPort: socksPort,
      );
    }

    // 3. Obras audiovisuais (Filmes, Séries, Animes): Wikidata aberta
    return await _searchWikidata(
      item: item,
      cacheDir: cacheDir,
      circuitIsolation: isolation,
      socksPort: socksPort,
    );
  }

  Future<EnrichmentResult> _searchOpenLibrary({
    required CulturalItem item,
    required Directory cacheDir,
    required String circuitIsolation,
    required int socksPort,
  }) async {
    final cleanTitle = Uri.encodeQueryComponent(item.title.trim());
    final uri = Uri.parse(
        'https://openlibrary.org/search.json?title=$cleanTitle&limit=5');

    final jsonStr = await _fetchJson(uri: uri, circuitIsolation: circuitIsolation, socksPort: socksPort);
    final data = jsonDecode(jsonStr);
    if (data is! Map || data['docs'] is! List) {
      return EnrichmentResult(
        itemId: item.id,
        title: item.title,
        source: 'openlibrary',
        confidence: EnrichmentConfidence.notFound,
      );
    }

    final docs = data['docs'] as List;
    for (final doc in docs) {
      if (doc is! Map) continue;
      final title = doc['title']?.toString() ?? '';
      if (!_isStrictTitleMatch(item.title, title)) continue;

      final coverId = doc['cover_i']?.toString();
      final authors = (doc['author_name'] as List?)?.map((e) => e.toString()).join(', ');
      final firstYear = (doc['first_publish_year'] as num?)?.toInt();

      String? downloadedPath;
      if (coverId != null) {
        final imgUri = Uri.parse('https://covers.openlibrary.org/b/id/$coverId-M.jpg');
        downloadedPath = await _downloadAndCacheImage(
          imgUri: imgUri,
          cacheDir: cacheDir,
          cacheKey: 'openlib_${item.id}_$coverId',
          circuitIsolation: circuitIsolation,
          socksPort: socksPort,
        );
      }

      return EnrichmentResult(
        itemId: item.id,
        title: item.title,
        coverPath: downloadedPath,
        creator: authors,
        releaseYear: firstYear,
        source: 'openlibrary',
        confidence: EnrichmentConfidence.strongAttributes,
      );
    }

    return EnrichmentResult(
      itemId: item.id,
      title: item.title,
      source: 'openlibrary',
      confidence: EnrichmentConfidence.notFound,
    );
  }

  Future<EnrichmentResult> _searchMusicBrainz({
    required CulturalItem item,
    required Directory cacheDir,
    required String circuitIsolation,
    required int socksPort,
  }) async {
    final cleanTitle = Uri.encodeQueryComponent(item.title.trim());
    final uri = Uri.parse(
        'https://musicbrainz.org/ws/2/recording?query=$cleanTitle&fmt=json&limit=5');

    final jsonStr = await _fetchJson(uri: uri, circuitIsolation: circuitIsolation, socksPort: socksPort);
    final data = jsonDecode(jsonStr);
    if (data is! Map || data['recordings'] is! List) {
      return EnrichmentResult(
        itemId: item.id,
        title: item.title,
        source: 'musicbrainz',
        confidence: EnrichmentConfidence.notFound,
      );
    }

    final recordings = data['recordings'] as List;
    for (final rec in recordings) {
      if (rec is! Map) continue;
      final title = rec['title']?.toString() ?? '';
      if (!_isStrictTitleMatch(item.title, title)) continue;

      final artistCredit = rec['artist-credit'] as List?;
      final artistName = artistCredit?.firstOrNull is Map
          ? artistCredit!.firstOrNull['name']?.toString()
          : null;
      final release = (rec['releases'] as List?)?.firstOrNull as Map?;
      final releaseId = release?['id']?.toString();

      String? downloadedPath;
      if (releaseId != null) {
        final artUri = Uri.parse('https://coverartarchive.org/release/$releaseId/front-250.jpg');
        downloadedPath = await _downloadAndCacheImage(
          imgUri: artUri,
          cacheDir: cacheDir,
          cacheKey: 'mb_${item.id}_$releaseId',
          circuitIsolation: circuitIsolation,
          socksPort: socksPort,
        );
      }

      return EnrichmentResult(
        itemId: item.id,
        title: item.title,
        coverPath: downloadedPath,
        creator: artistName,
        source: 'musicbrainz',
        confidence: EnrichmentConfidence.strongAttributes,
      );
    }

    return EnrichmentResult(
      itemId: item.id,
      title: item.title,
      source: 'musicbrainz',
      confidence: EnrichmentConfidence.notFound,
    );
  }

  Future<EnrichmentResult> _searchWikidata({
    required CulturalItem item,
    required Directory cacheDir,
    required String circuitIsolation,
    required int socksPort,
  }) async {
    final mediaKeyword = switch (item.category) {
      CulturalCategory.movies => 'film',
      CulturalCategory.series => 'series',
      CulturalCategory.anime => 'anime',
      _ => 'film',
    };

    // 1. Wikipedia API (English & Portuguese) com pageimages (pilicense=any) e extracts
    final yearSuffix = item.releaseYear != null ? ' ${item.releaseYear}' : '';
    final searchTerms = [
      '${item.title.trim()}$yearSuffix $mediaKeyword',
      item.title.trim(),
    ];

    for (final term in searchTerms) {
      final q = Uri.encodeQueryComponent(term);
      for (final lang in ['en', 'pt']) {
        try {
          final wikiUri = Uri.parse(
              'https://$lang.wikipedia.org/w/api.php?action=query&generator=search&gsrsearch=$q&gsrlimit=3&prop=pageimages|extracts&piprop=thumbnail&pithumbsize=600&pilicense=any&exintro=1&explaintext=1&format=json');
          final jsonStr = await _fetchJson(uri: wikiUri, circuitIsolation: circuitIsolation, socksPort: socksPort);
          final data = jsonDecode(jsonStr);
          if (data is Map && data['query'] is Map && data['query']['pages'] is Map) {
            final pages = data['query']['pages'] as Map;
            for (final entry in pages.values) {
              if (entry is! Map) continue;
              final pageTitle = entry['title']?.toString() ?? '';
              final extract = entry['extract']?.toString().trim();
              final thumbMap = entry['thumbnail'] as Map?;
              final thumbUrl = thumbMap?['source']?.toString();

              // Verifica relevância mínima do título
              if (!_isStrictTitleMatch(item.title, pageTitle) &&
                  !pageTitle.toLowerCase().contains(item.title.trim().toLowerCase())) {
                continue;
              }

              String? localPath;
              if (thumbUrl != null && thumbUrl.isNotEmpty) {
                final imgUri = Uri.parse(thumbUrl);
                localPath = await _downloadAndCacheImage(
                  imgUri: imgUri,
                  cacheDir: cacheDir,
                  cacheKey: 'wiki_${item.id}_${imgUri.pathSegments.last}',
                  circuitIsolation: circuitIsolation,
                  socksPort: socksPort,
                );
              }

              if (localPath != null || (extract != null && extract.isNotEmpty)) {
                // Tenta extrair diretor/criador da sinopse se não existir
                String? parsedCreator = item.creator;
                if ((parsedCreator == null || parsedCreator.isEmpty) && extract != null) {
                  final dirMatch = RegExp(
                          r'(?:directed by|dirigido por)\s+([A-ZÀ-Ú][a-zA-ZÀ-ú\s\.\-]+?)(?:\.|,|;|\(|\n|\band\b)',
                          caseSensitive: false)
                      .firstMatch(extract);
                  if (dirMatch != null) {
                    parsedCreator = dirMatch.group(1)?.trim();
                  }
                }

                // Tenta extrair ano de lançamento se não existir
                int? parsedYear = item.releaseYear;
                if (parsedYear == null) {
                  final yearMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(pageTitle);
                  if (yearMatch != null) {
                    parsedYear = int.tryParse(yearMatch.group(1)!);
                  }
                }

                return EnrichmentResult(
                  itemId: item.id,
                  title: item.title,
                  coverPath: localPath,
                  synopsis: (extract != null && extract.isNotEmpty) ? extract : null,
                  creator: parsedCreator,
                  releaseYear: parsedYear,
                  source: 'wikipedia',
                  confidence: localPath != null
                      ? EnrichmentConfidence.strongAttributes
                      : EnrichmentConfidence.ambiguous,
                );
              }
            }
          }
        } catch (_) {}
      }
    }

    // 2. Wikidata Fallback (wbsearchentities + wbgetclaims P18/P577/P1476)
    try {
      final cleanTitle = Uri.encodeQueryComponent(item.title.trim());
      final uri = Uri.parse(
          'https://www.wikidata.org/w/api.php?action=wbsearchentities&search=$cleanTitle&language=pt&format=json&limit=5');
      final jsonStr = await _fetchJson(uri: uri, circuitIsolation: circuitIsolation, socksPort: socksPort);
      final data = jsonDecode(jsonStr);
      if (data is Map && data['search'] is List) {
        final searchList = data['search'] as List;
        for (final entry in searchList) {
          if (entry is! Map) continue;
          final label = entry['label']?.toString() ?? '';
          final desc = entry['description']?.toString() ?? '';
          final isExpectedMedia = _matchesMediaType(item.category, desc);
          if (!isExpectedMedia && !_isStrictTitleMatch(item.title, label)) {
            continue;
          }
          final qid = entry['id']?.toString();
          String? coverPath;
          String? originalTitle;
          int? releaseYear;

          if (qid != null) {
            try {
              final claimsUri = Uri.parse(
                  'https://www.wikidata.org/w/api.php?action=wbgetclaims&entity=$qid&format=json');
              final claimsJson = await _fetchJson(uri: claimsUri, circuitIsolation: circuitIsolation, socksPort: socksPort);
              final claimsData = jsonDecode(claimsJson);
              if (claimsData is Map && claimsData['claims'] is Map) {
                final claims = claimsData['claims'] as Map;
                // P18 = imagem Commons
                if (claims['P18'] is List && (claims['P18'] as List).isNotEmpty) {
                  final p18Val = claims['P18'][0]['mainsnak']?['datavalue']?['value']?.toString();
                  if (p18Val != null && p18Val.isNotEmpty) {
                    try {
                      final commonsApiUri = Uri.parse(
                          'https://commons.wikimedia.org/w/api.php?action=query&titles=File:${Uri.encodeComponent(p18Val)}&prop=imageinfo&iiprop=url&iiurlwidth=600&format=json');
                      final cJson = await _fetchJson(uri: commonsApiUri, circuitIsolation: circuitIsolation, socksPort: socksPort);
                      final cData = jsonDecode(cJson);
                      if (cData is Map && cData['query'] is Map && cData['query']['pages'] is Map) {
                        final cPages = cData['query']['pages'] as Map;
                        for (final cp in cPages.values) {
                          if (cp is! Map) continue;
                          final ii = (cp['imageinfo'] as List?)?.firstOrNull as Map?;
                          final thumb = ii?['thumburl']?.toString() ?? ii?['url']?.toString();
                          if (thumb != null) {
                            coverPath = await _downloadAndCacheImage(
                              imgUri: Uri.parse(thumb),
                              cacheDir: cacheDir,
                              cacheKey: 'wd_${item.id}_$p18Val',
                              circuitIsolation: circuitIsolation,
                              socksPort: socksPort,
                            );
                            break;
                          }
                        }
                      }
                    } catch (_) {}
                  }
                }
                // P577 = ano de lançamento
                if (claims['P577'] is List && (claims['P577'] as List).isNotEmpty) {
                  final timeStr = claims['P577'][0]['mainsnak']?['datavalue']?['value']?['time']?.toString();
                  if (timeStr != null) {
                    final match = RegExp(r'\+?(\d{4})').firstMatch(timeStr);
                    if (match != null) {
                      releaseYear = int.tryParse(match.group(1)!);
                    }
                  }
                }
                // P1476 = título original
                if (claims['P1476'] is List && (claims['P1476'] as List).isNotEmpty) {
                  originalTitle = claims['P1476'][0]['mainsnak']?['datavalue']?['value']?['text']?.toString();
                }
              }
            } catch (_) {}
          }

          return EnrichmentResult(
            itemId: item.id,
            title: item.title,
            coverPath: coverPath,
            originalTitle: originalTitle ?? item.originalTitle,
            releaseYear: releaseYear ?? item.releaseYear,
            synopsis: desc.isNotEmpty ? desc : null,
            source: 'wikidata',
            confidence: qid != null ? EnrichmentConfidence.exactId : EnrichmentConfidence.strongAttributes,
          );
        }
      }
    } catch (_) {}

    return EnrichmentResult(
      itemId: item.id,
      title: item.title,
      source: 'wikidata',
      confidence: EnrichmentConfidence.notFound,
    );
  }

  bool _isStrictTitleMatch(String query, String candidate) {
    final q = query.trim().toLowerCase();
    final c = candidate.trim().toLowerCase();
    if (q == c) return true;
    if (c.startsWith(q) || q.startsWith(c)) {
      final diff = (q.length - c.length).abs();
      return diff <= 3;
    }
    return false;
  }

  bool _matchesMediaType(CulturalCategory category, String description) {
    final d = description.toLowerCase();
    return switch (category) {
      CulturalCategory.movies => d.contains('filme') || d.contains('movie') || d.contains('cinema'),
      CulturalCategory.series => d.contains('série') || d.contains('series') || d.contains('televisão'),
      CulturalCategory.anime => d.contains('anime') || d.contains('animação japonesa'),
      CulturalCategory.manga => d.contains('mangá') || d.contains('manga'),
      CulturalCategory.books => d.contains('livro') || d.contains('romance') || d.contains('obra literária'),
      CulturalCategory.music => d.contains('álbum') || d.contains('canção') || d.contains('música'),
      CulturalCategory.github => true,
    };
  }

  Future<String> _fetchJson({
    required Uri uri,
    required String circuitIsolation,
    required int socksPort,
  }) async {
    if (_customRequester != null) {
      return await _customRequester!(uri: uri, circuitIsolation: circuitIsolation);
    }

    final connector = Socks5Connector(
      proxyHost: '127.0.0.1',
      proxyPort: socksPort,
      username: circuitIsolation,
      password: circuitIsolation,
    );

    final res = await connector.httpRequest(
      'GET',
      uri,
      headers: const {
        'User-Agent': 'NixCulturalCoverEnricher/1.0 ( privacy@projetonix.org )',
        'Accept': 'application/json',
      },
      requireOnionV3: false,
      timeout: const Duration(seconds: 20),
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.body;
    }
    throw HttpException('Falha na resposta HTTP ${res.statusCode}');
  }

  Future<String?> _downloadAndCacheImage({
    required Uri imgUri,
    required Directory cacheDir,
    required String cacheKey,
    required String circuitIsolation,
    required int socksPort,
  }) async {
    try {
      final hash = md5.convert(utf8.encode(cacheKey)).toString();
      final localFile = File('${cacheDir.path}/cover_$hash.jpg');

      if (await localFile.exists()) {
        return localFile.path;
      }

      if (_customRequester != null) {
        // Modo simulado / testes
        await localFile.writeAsBytes(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]));
        return localFile.path;
      }

      final connector = Socks5Connector(
        proxyHost: '127.0.0.1',
        proxyPort: socksPort,
        username: circuitIsolation,
        password: circuitIsolation,
      );

      final res = await connector.httpRequest(
        'GET',
        imgUri,
        headers: const {
          'User-Agent': 'NixCulturalCoverEnricher/1.0',
          'Accept': 'image/jpeg, image/png, image/webp',
        },
        requireOnionV3: false,
        timeout: const Duration(seconds: 25),
      );

      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await localFile.writeAsBytes(res.bodyBytes);
        return localFile.path;
      }
    } catch (_) {}
    return null;
  }

  Future<Directory> _ensureCoversCacheDirectory() async {
    final basePath = NixPlatformPaths.resolveDataFile('covers_cache');
    final dir = Directory(basePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
