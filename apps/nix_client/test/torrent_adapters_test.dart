import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/torrent_index/adapters/knaben_adapter.dart';
import 'package:nix_client/core/torrent_index/adapters/nyaa_rss_adapter.dart';
import 'package:nix_client/core/torrent_index/adapters/rss_index_adapter.dart';
import 'package:nix_client/core/torrent_index/adapters/thepiratebay_adapter.dart';
import 'package:nix_client/core/torrent_index/adapters/torrents_csv_adapter.dart';
import 'package:nix_client/core/torrent_index/adapters/torznab_adapter.dart';
import 'package:nix_client/core/torrent_index/adapters/tracker_1337x_adapter.dart';
import 'package:nix_client/core/torrent_index/adapters/yts_api_adapter.dart';
import 'package:nix_client/core/torrent_index/models/torrent_record.dart';

void main() {
  group('NyaaRssAdapter', () {
    test('Analisa feed RSS do Nyaa extraindo metadados reais, seeders e infoHash', () {
      const xmlFixture = '''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:nyaa="https://nyaa.si/xmlns/nyaa">
  <channel>
    <title>Nyaa - Torrents</title>
    <item>
      <title><![CDATA[[SubsPlease] Frieren - 28 (1080p) [ABCD1234].mkv]]></title>
      <link>https://nyaa.si/download/12345.torrent</link>
      <guid isPermaLink="true">https://nyaa.si/view/12345</guid>
      <pubDate>Mon, 23 Nov 2026 05:00:00 +0000</pubDate>
      <nyaa:seeders>245</nyaa:seeders>
      <nyaa:leechers>12</nyaa:leechers>
      <nyaa:downloads>5400</nyaa:downloads>
      <nyaa:infoHash>abcdef1234567890abcdef1234567890abcdef12</nyaa:infoHash>
      <nyaa:categoryId>1_2</nyaa:categoryId>
      <nyaa:size>1.4 GiB</nyaa:size>
    </item>
  </channel>
</rss>''';

      final adapter = NyaaRssAdapter();
      final records = adapter.parseRss(xmlFixture, 10);
      expect(records.length, equals(1));

      final rec = records.first;
      expect(rec.title, equals('[SubsPlease] Frieren - 28 (1080p) [ABCD1234].mkv'));
      expect(rec.seeders, equals(245));
      expect(rec.leechers, equals(12));
      expect(rec.infoHashV1, equals('abcdef1234567890abcdef1234567890abcdef12'));
      expect(rec.sizeBytes, isNotNull);
      expect(rec.sizeBytes!, greaterThan(1024 * 1024 * 1024)); // > 1 GB
      expect(rec.category, equals(TorrentCategory.anime));
      expect(rec.magnetUri, startsWith('magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12'));
    });
  });

  group('YtsApiAdapter', () {
    test('Analisa JSON da API do YTS extraindo filmes, hashes e seeds reais', () {
      const jsonFixture = '''{
  "status": "ok",
  "status_message": "Query was successful",
  "data": {
    "movie_count": 1,
    "limit": 20,
    "page_number": 1,
    "movies": [
      {
        "id": 54321,
        "url": "https://yts.mx/movies/solaris-1972",
        "title": "Solaris",
        "title_long": "Solaris (1972)",
        "year": 1972,
        "torrents": [
          {
            "url": "https://yts.mx/torrent/download/hash1",
            "hash": "1122334455667788990011223344556677889900",
            "quality": "1080p",
            "type": "bluray",
            "seeds": 88,
            "peers": 4,
            "size_bytes": 2840000000,
            "date_uploaded": "2026-11-20 12:00:00"
          }
        ]
      }
    ]
  }
}''';

      final adapter = YtsApiAdapter();
      final records = adapter.parseJson(jsonFixture, 10);
      expect(records.length, equals(1));

      final rec = records.first;
      expect(rec.title, equals('Solaris (1972) [1080p] [bluray]'));
      expect(rec.infoHashV1, equals('1122334455667788990011223344556677889900'));
      expect(rec.seeders, equals(88));
      expect(rec.leechers, equals(4));
      expect(rec.sizeBytes, equals(2840000000));
      expect(rec.category, equals(TorrentCategory.movies));
    });
  });

  group('TorznabAdapter', () {
    test('Analisa XML padrão Torznab com atributos customizados de seeders e magnet', () {
      const torznabXml = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:torznab="http://torznab.com/schemas/2015/feed">
  <channel>
    <title>Torznab Feed</title>
    <item>
      <title>Ubuntu 24.04 Desktop amd64</title>
      <guid>torznab_item_1</guid>
      <link>magnet:?xt=urn:btih:445566778899aabbccddeeff0011223344556677&amp;dn=Ubuntu</link>
      <pubDate>Sun, 22 Nov 2026 10:00:00 +0000</pubDate>
      <enclosure url="https://tracker.org/ubuntu.torrent" length="5000000000" type="application/x-bittorrent" />
      <torznab:attr name="seeders" value="150" />
      <torznab:attr name="peers" value="20" />
      <torznab:attr name="infohash" value="445566778899aabbccddeeff0011223344556677" />
      <torznab:attr name="category" value="4000" />
    </item>
  </channel>
</rss>''';

      const adapter = TorznabAdapter(url: 'http://127.0.0.1:9696');
      final records = adapter.parseXml(torznabXml, 10);
      expect(records.length, equals(1));

      final rec = records.first;
      expect(rec.title, equals('Ubuntu 24.04 Desktop amd64'));
      expect(rec.seeders, equals(150));
      expect(rec.leechers, equals(20));
      expect(rec.sizeBytes, equals(5000000000));
      expect(rec.category, equals(TorrentCategory.software));
      expect(rec.infoHashV1, equals('445566778899aabbccddeeff0011223344556677'));
    });
  });

  group('Tracker1337xAdapter', () {
    test('Detecta desafios Cloudflare / Turnstile e não tenta contornar proteções', () async {
      final challengeAdapter = Tracker1337xAdapter(
        mirrorUrl: 'https://1337x.to',
        requester: (method, uri, {headers, body, timeout}) async {
          return (
            statusCode: 403,
            body: '<html><title>Just a moment...</title><body>Checking your browser before accessing 1337x. Cloudflare Turnstile Challenge Platform</body></html>',
          );
        },
      );

      final ok = await challengeAdapter.testConnection();
      expect(ok, isFalse);
      expect(challengeAdapter.isAvailable, isFalse);
      expect(challengeAdapter.statusMessage, contains('Cloudflare'));
    });

    test('Analisa listagem HTML quando espelho autorizado responde com sucesso', () {
      const htmlFixture = '''
      <table>
        <tr>
          <td class="coll-1 name"><a href="/torrent/998877/Blender-4.2-LTS/">Blender 4.2 LTS Linux</a></td>
          <td class="coll-2 seeds">320</td>
          <td class="coll-3 leeches">45</td>
          <td class="coll-4 size">450 MB</td>
        </tr>
      </table>
      ''';

      final adapter = Tracker1337xAdapter();
      final records = adapter.parseHtml(htmlFixture, 10);
      expect(records.length, equals(1));

      final rec = records.first;
      expect(rec.title, equals('Blender 4.2 LTS Linux'));
      expect(rec.seeders, equals(320));
      expect(rec.leechers, equals(45));
      expect(rec.sizeBytes, isNotNull);
    });
  });

  group('RssIndexAdapter', () {
    test('Analisa feed RSS 2.0 genérico com enclosures e links magnet', () {
      const rssFixture = '''<?xml version="1.0"?>
<rss version="2.0">
  <channel>
    <title>Generic Torrents</title>
    <item>
      <title>Public Domain Book Audio</title>
      <link>magnet:?xt=urn:btih:9988776655443322110099887766554433221100&amp;dn=Book</link>
      <pubDate>Fri, 20 Nov 2026 15:30:00 GMT</pubDate>
      <enclosure url="http://archive.org/item.torrent" length="125000000" type="application/x-bittorrent" />
    </item>
  </channel>
</rss>''';

      const adapter = RssIndexAdapter(feedUrl: 'http://example.org/rss');
      final records = adapter.parseRss(rssFixture, 10);
      expect(records.length, equals(1));

      final rec = records.first;
      expect(rec.title, equals('Public Domain Book Audio'));
      expect(rec.infoHashV1, equals('9988776655443322110099887766554433221100'));
      expect(rec.sizeBytes, equals(125000000));
    });
  });

  group('ThePirateBayAdapter', () {
    test('Analisa JSON oficial da API apibay extraindo hashes, seeds e categorias', () {
      const tpbJson = '''[
        {
          "id": "7654321",
          "name": "Debian 12 Bookworm Netinst amd64",
          "info_hash": "2233445566778899001122334455667788990011",
          "leechers": "25",
          "seeders": "420",
          "size": "734003200",
          "added": "1690000000",
          "category": "300"
        }
      ]''';

      const adapter = ThePirateBayAdapter();
      final records = adapter.parseJson(tpbJson, 10);
      expect(records.length, equals(1));

      final rec = records.first;
      expect(rec.title, equals('Debian 12 Bookworm Netinst amd64'));
      expect(rec.infoHashV1, equals('2233445566778899001122334455667788990011'));
      expect(rec.seeders, equals(420));
      expect(rec.leechers, equals(25));
      expect(rec.sizeBytes, equals(734003200));
      expect(rec.category, equals(TorrentCategory.software));
      expect(rec.magnetUri, startsWith('magnet:?xt=urn:btih:2233445566778899001122334455667788990011'));
    });
  });

  group('TorrentsCsvAdapter', () {
    test('Analisa JSON do Torrents-CSV com tamanho e seeds reais', () {
      const csvJson = '''{
        "torrents": [
          {
            "infohash": "3344556677889900112233445566778899001122",
            "name": "Ubuntu.24.04.LTS.Desktop.iso",
            "size_bytes": 5242880000,
            "created_unix": 1714000000,
            "seeders": 1500,
            "leechers": 120
          }
        ]
      }''';

      const adapter = TorrentsCsvAdapter();
      final records = adapter.parseJson(csvJson, 10);
      expect(records.length, equals(1));

      final rec = records.first;
      expect(rec.title, equals('Ubuntu.24.04.LTS.Desktop.iso'));
      expect(rec.normalizedTitle, equals('Ubuntu 24 04 LTS Desktop iso'));
      expect(rec.infoHashV1, equals('3344556677889900112233445566778899001122'));
      expect(rec.seeders, equals(1500));
      expect(rec.sizeBytes, equals(5242880000));
    });
  });

  group('KnabenAdapter', () {
    test('Extrai magnets canônicos, seeds e bytes do HTML do Knaben', () {
      const knabenHtml = '''
      <table>
        <tr>
          <td class="text-wrap w-100">
            <a title="Arch Linux 2026.11 x86_64" href="magnet:?xt=urn:btih:4455667788990011223344556677889900112233&amp;dn=Arch+Linux">Arch Linux 2026.11 x86_64</a>
          </td>
          <td title="1073741824 Bytes">1.0 GB</td>
          <td title="2026-11-23 10:00:00">2026-11-23</td>
          <td>95</td>
        </tr>
      </table>
      ''';

      const adapter = KnabenAdapter();
      final records = adapter.parseHtml(knabenHtml, 10);
      expect(records.length, equals(1));

      final rec = records.first;
      expect(rec.title, equals('Arch Linux 2026.11 x86_64'));
      expect(rec.infoHashV1, equals('4455667788990011223344556677889900112233'));
      expect(rec.seeders, equals(95));
      expect(rec.sizeBytes, equals(1073741824));
    });
  });
}
