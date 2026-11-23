import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:nix_transport/nix_transport.dart';
import 'dart:io';
import 'catalog_database.dart';

typedef OnlineMusicQueryHandler = Future<String> Function({
  required String query,
  required String circuitIsolation,
});

/// Serviço de busca online consentida de metadados musicais via Tor (SOCKS5 fail-closed).
/// Preserva a privacidade estrita do usuário, rejeita clearnet sem Tor e nunca realiza
/// streaming ou download de áudio remoto — apenas metadados são recuperados para vinculação local.
class MusicOnlineMetadataService {
  final OnlineMusicQueryHandler? _queryHandler;

  const MusicOnlineMetadataService() : _queryHandler = null;

  MusicOnlineMetadataService.withQuery(OnlineMusicQueryHandler handler)
      : _queryHandler = handler;

  static String _generateCircuitIsolation() {
    final random = Random.secure();
    final bytes = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Realiza a busca de metadados de faixas e álbuns de fontes abertas via Tor.
  /// Rejeita fail-closed caso o consentimento do usuário não seja fornecido
  /// ou o Tor não esteja pronto.
  Future<List<CatalogWork>> searchMusicOnline({
    required String query,
    required bool userConsent,
    required bool isTorReady,
    int socksPort = 9050,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    if (!userConsent) {
      throw StateError(
        'A busca online de metadados exige o consentimento prévio e explícito do usuário.',
      );
    }

    if (!isTorReady) {
      throw const TransportBlockedException(
        'Busca musical externa bloqueada: o circuito Tor seguro não está ativo (fail-closed).',
      );
    }

    final isolation = _generateCircuitIsolation();

    String rawResponse;
    if (_queryHandler != null) {
      rawResponse = await _queryHandler!(query: cleanQuery, circuitIsolation: isolation);
    } else {
      // Em produção real, consulta a API aberta do MusicBrainz via Tor SOCKS5
      final connector = Socks5Connector(
        proxyHost: '127.0.0.1',
        proxyPort: socksPort,
        username: isolation,
        password: isolation,
      );
      const host = 'musicbrainz.org';
      final encodedQuery = Uri.encodeQueryComponent(cleanQuery);
      final uri = Uri.parse('https://$host/ws/2/recording?query=$encodedQuery&fmt=json&limit=20');
      final res = await connector.httpRequest(
        'GET',
        uri,
        headers: const {
          'User-Agent': 'NixMusicMetadata/1.0 ( privacy@projetonix.org )',
          'Accept': 'application/json',
        },
        requireOnionV3: false,
        timeout: const Duration(seconds: 25),
      );
      rawResponse = res.body;
    }

    return _parseMusicBrainzResponse(rawResponse);
  }

  static List<CatalogWork> _parseMusicBrainzResponse(String responseJson) {
    try {
      final decoded = jsonDecode(responseJson);
      if (decoded is! Map) return const [];
      final recordings = decoded['recordings'];
      if (recordings is! List) return const [];

      final results = <CatalogWork>[];
      final now = DateTime.now().millisecondsSinceEpoch;

      for (final rec in recordings) {
        if (rec is! Map) continue;
        final id = rec['id']?.toString() ?? '';
        final title = rec['title']?.toString() ?? '';
        if (id.isEmpty || title.isEmpty) continue;

        String artist = '';
        final artistCredits = rec['artist-credit'];
        if (artistCredits is List && artistCredits.isNotEmpty) {
          final first = artistCredits.first;
          if (first is Map && first['name'] != null) {
            artist = first['name'].toString();
          }
        }

        String album = '';
        int? releaseYear;
        final releases = rec['releases'];
        if (releases is List && releases.isNotEmpty) {
          final rel = releases.first;
          if (rel is Map) {
            album = rel['title']?.toString() ?? '';
            final date = rel['date']?.toString() ?? '';
            if (date.length >= 4) {
              releaseYear = int.tryParse(date.substring(0, 4));
            }
          }
        }

        results.add(CatalogWork(
          id: 'mb_rec_$id',
          kind: 'track',
          title: title,
          originalTitle: album.isNotEmpty ? album : null,
          creators: artist.isNotEmpty ? artist : null,
          genres: 'Music',
          releaseYear: releaseYear,
          summary: 'Metadado obtido sob consentimento via MusicBrainz (Tor).',
          coverThumb: null,
          externalIds: {'musicbrainz': id},
          updatedAt: now,
        ));
      }

      return results;
    } catch (_) {
      return const [];
    }
  }
}
