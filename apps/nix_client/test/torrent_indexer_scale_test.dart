import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/torrent_index/adapters/indexer_sources_manager.dart';
import 'package:nix_client/core/torrent_index/api/nix_online_search_api.dart';
import 'package:nix_client/core/torrent_index/database/torrent_index_database.dart';
import 'package:nix_client/core/torrent_index/models/torrent_record.dart';

void main() {
  group('Nix Torrent Index — Testes Sintéticos de Escala e Concorrência', () {
    late TorrentIndexDatabase db;
    late IndexerSourcesManager sourcesManager;
    late NixOnlineSearchApi api;
    int mockUpstreamCalls = 0;

    setUp(() async {
      mockUpstreamCalls = 0;
      db = await TorrentIndexDatabase.open(inMemory: true);

      // Semeia registros no banco local
      final now = DateTime.now();
      final seeded = List.generate(
        100,
        (i) => TorrentIndexRecord(
          id: 'seed_$i',
          sourceId: 'nyaa',
          sourceName: 'Nyaa.si',
          title: 'Anime Release Episódio $i [1080p]',
          normalizedTitle: 'Anime Release Episodio $i 1080p',
          category: TorrentCategory.anime,
          sizeBytes: 1400000000 + i * 10000,
          seeders: 50 + (i % 200),
          leechers: 5 + (i % 20),
          infoHashV1: '11223344556677889900112233445566778899${i.toString().padLeft(2, "0")}',
          indexedAt: now,
          lastSeenAt: now,
        ),
      );
      await db.upsertRecords(seeded);

      // Adaptador mock com contagem de requisições upstream
      final mockRequester = (String method, Uri uri, {Map<String, String>? headers, String? body, Duration? timeout}) async {
        mockUpstreamCalls++;
        await Future.delayed(const Duration(milliseconds: 10)); // Simula latência de rede
        const xml = '''<rss version="2.0" xmlns:nyaa="https://nyaa.si/xmlns/nyaa">
          <channel>
            <item>
              <title>Live Upstream Match</title>
              <guid>live_1</guid>
              <nyaa:infoHash>abcdef1234567890abcdef1234567890abcdef12</nyaa:infoHash>
              <nyaa:seeders>150</nyaa:seeders>
              <nyaa:size>2.0 GiB</nyaa:size>
            </item>
          </channel>
        </rss>''';
        return (statusCode: 200, body: xml);
      };

      sourcesManager = IndexerSourcesManager(requester: mockRequester);
      // Mantém apenas o adaptador nyaa ativo no teste de escala para contagem determinística
      sourcesManager.setSourceEnabled('yts', false);
      sourcesManager.setSourceEnabled('1337x', false);
      sourcesManager.setSourceEnabled('binsearch', false);

      api = NixOnlineSearchApi(
        database: db,
        sourcesManager: sourcesManager,
        cacheTtl: const Duration(minutes: 10),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('Consolidação em voo: 50 usuários simultâneos pesquisando o mesmo termo geram apenas 1 requisição upstream', () async {
      // 50 requisições disparadas exatamente ao mesmo tempo para busca ao vivo
      final futures = List.generate(
        50,
        (_) => api.handleRequest(
          'POST',
          '/v1/index/live-search',
          jsonBody: {'query': 'Ubuntu Linux'},
        ),
      );

      final results = await Future.wait(futures);
      expect(results.length, equals(50));
      for (final r in results) {
        expect(r.statusCode, equals(200));
        expect(r.body['records'], isNotEmpty);
      }

      // Requisições consolidadas pelo In-Flight Coalescing
      expect(mockUpstreamCalls, equals(1));
      expect(api.metrics.cacheHits, equals(49));
    });

    test('Escala de 500 clientes concorrentes consultando termos variados', () async {
      final terms = ['Episodio', 'Anime', '1080p', 'Release', 'Desconhecido'];
      final totalWallClock = Stopwatch()..start();
      final futures = List.generate(500, (i) {
        final term = terms[i % terms.length];
        return api.handleRequest(
          'GET',
          '/v1/index/search',
          queryParams: {'query': term, 'page': '1', 'page_size': '20'},
        );
      });

      final results = await Future.wait(futures);
      totalWallClock.stop();
      expect(results.length, equals(500));
      for (final r in results) {
        expect(r.statusCode, equals(200));
      }

      expect(api.metrics.totalQueries, greaterThanOrEqualTo(500));
      // 500 consultas processadas em menos de 5 segundos no SQLite FTS5
      expect(totalWallClock.elapsedMilliseconds, lessThan(5000));
    });

    test('Simulação de 1.000 consultas repetidas: taxa de cache superior a 80%', () async {
      final terms = ['Frieren', 'Solaris', 'Cowboy Bebop', 'Debian', 'Blender'];
      final random = Random(42);

      for (var i = 0; i < 1000; i++) {
        final term = terms[random.nextInt(terms.length)];
        await api.handleRequest(
          'POST',
          '/v1/index/live-search',
          jsonBody: {'query': term},
        );
      }

      expect(api.metrics.totalQueries, equals(1000));
      // Com apenas 5 termos e 1000 consultas, as 5 primeiras foram upstream e as outras 995 foram cache
      expect(api.metrics.cacheHitRatio, greaterThan(0.95));
      expect(mockUpstreamCalls, lessThanOrEqualTo(5));
    });

    test('Simulação massiva sintética de 10.000 requisições locais imediatas', () async {
      api.metrics.reset();
      final stopwatch = Stopwatch()..start();

      for (var i = 0; i < 10000; i++) {
        await api.handleRequest(
          'GET',
          '/v1/index/search',
          queryParams: {'query': 'Episódio', 'page': '1', 'page_size': '10'},
        );
      }
      stopwatch.stop();

      expect(api.metrics.totalQueries, equals(10000));
      expect(stopwatch.elapsedMilliseconds, lessThan(35000)); // Processa 10.000 em menos de 35 segundos sob concorrência total de testes
    });
  });
}
