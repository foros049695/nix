import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/models/cultural_item.dart';
import 'package:nix_client/core/network/transport_profile.dart';
import 'package:nix_client/core/media/catalog_diagnostics.dart';
import 'package:nix_client/core/downloads/models/download_task.dart';

void main() {
  group('Perfis de Transporte & Privacidade (Seção 5)', () {
    test('Configura perfis independentes por módulo e preserva integridade', () {
      var prefs = const ModuleTransportPreferences();

      // Padrão: todos em Tor SOCKS5
      expect(prefs.getProfile(TransportModule.downloads), equals(TransportProfileType.torSocks5));
      expect(prefs.getProfile(TransportModule.torrents), equals(TransportProfileType.torSocks5));
      expect(prefs.getProfile(TransportModule.catalog), equals(TransportProfileType.torSocks5));
      expect(prefs.getProfile(TransportModule.music), equals(TransportProfileType.torSocks5));
      expect(prefs.isClearnetAuthorized(TransportModule.downloads), isFalse);

      // Altera módulo Downloads para directHttps (Perfil D)
      prefs = prefs.setModuleProfile(TransportModule.downloads, TransportProfileType.directHttps);
      expect(prefs.getProfile(TransportModule.downloads), equals(TransportProfileType.directHttps));
      expect(prefs.isClearnetAuthorized(TransportModule.downloads), isTrue);

      // Os outros módulos continuam estritamente em Tor SOCKS5
      expect(prefs.getProfile(TransportModule.torrents), equals(TransportProfileType.torSocks5));
      expect(prefs.isClearnetAuthorized(TransportModule.torrents), isFalse);
      expect(prefs.getProfile(TransportModule.catalog), equals(TransportProfileType.torSocks5));
      expect(prefs.getProfile(TransportModule.music), equals(TransportProfileType.torSocks5));

      // Altera Catálogo para Onion v3 Estrito (Perfil A)
      prefs = prefs.setModuleProfile(TransportModule.catalog, TransportProfileType.onionV3Strict);
      expect(prefs.getProfile(TransportModule.catalog), equals(TransportProfileType.onionV3Strict));

      // Serialização JSON e restauração completa
      final json = prefs.toJson();
      final restored = ModuleTransportPreferences.fromJson(json);

      expect(restored.getProfile(TransportModule.downloads), equals(TransportProfileType.directHttps));
      expect(restored.getProfile(TransportModule.torrents), equals(TransportProfileType.torSocks5));
      expect(restored.getProfile(TransportModule.catalog), equals(TransportProfileType.onionV3Strict));
      expect(restored.getProfile(TransportModule.music), equals(TransportProfileType.torSocks5));
    });

    test('GlobalTransportRegistry sincroniza e reflete perfis em tempo de execução', () {
      final initial = const ModuleTransportPreferences();
      GlobalTransportRegistry.update(initial);
      expect(GlobalTransportRegistry.current.getProfile(TransportModule.torrents), equals(TransportProfileType.torSocks5));

      final updated = initial.setModuleProfile(TransportModule.torrents, TransportProfileType.onionV3Strict);
      GlobalTransportRegistry.update(updated);
      expect(GlobalTransportRegistry.current.getProfile(TransportModule.torrents), equals(TransportProfileType.onionV3Strict));
    });
  });

  group('Integração Acervo Cultural <-> Torrent Index (Seção 6)', () {
    test('Formata termo de busca contextualmente por tipo de mídia sem vazar dados privados', () {
      // 1. Filme: <Título> <Ano>
      const movie = CulturalItem(
        id: 'mv_1',
        title: 'Interestelar',
        creatorOrYear: '2014',
        category: CulturalCategory.movies,
        monogram: 'IN',
        releaseYear: 2014,
        rating: '10.0', // Dado privado do usuário
      );
      expect(movie.torrentSearchQuery, equals('Interestelar 2014'));
      expect(movie.torrentSearchQuery.contains('10.0'), isFalse);

      // 2. Série: <Título>
      const series = CulturalItem(
        id: 'sr_1',
        title: 'Dark',
        creatorOrYear: 'Baran bo Odar',
        category: CulturalCategory.series,
        monogram: 'DK',
      );
      expect(series.torrentSearchQuery, equals('Dark'));

      // 3. Anime: <Título original> (ou título principal)
      const anime = CulturalItem(
        id: 'an_1',
        title: 'Attack on Titan',
        originalTitle: 'Shingeki no Kyojin',
        creatorOrYear: 'Hajime Isayama',
        category: CulturalCategory.anime,
        monogram: 'SNK',
      );
      expect(anime.torrentSearchQuery, equals('Shingeki no Kyojin'));

      // 4. Livro / Mangá: <Título> <Autor>
      const book = CulturalItem(
        id: 'bk_1',
        title: '1984',
        creator: 'George Orwell',
        creatorOrYear: 'George Orwell',
        category: CulturalCategory.books,
        monogram: '19',
      );
      expect(book.torrentSearchQuery, equals('1984 George Orwell'));

      // 5. Música: <Artista> <Título>
      const music = CulturalItem(
        id: 'ms_1',
        title: 'Veigh',
        creator: 'Veigh',
        creatorOrYear: 'Veigh',
        category: CulturalCategory.music,
        monogram: 'VG',
      );
      expect(music.torrentSearchQuery, equals('Veigh Veigh'));
    });
  });

  group('Diagnóstico em Camadas do Catálogo & Serviços Onion (Seção 4)', () {
    test('Identifica placeholder de demonstração nixcatalog234567...onion com clareza', () async {
      final placeholderUri = Uri.parse('http://${CatalogDiagnostics.knownPlaceholderOnion}/manifest.json');
      final report = await CatalogDiagnostics.runDiagnostics(
        manifestUri: placeholderUri,
        socksPort: 9050,
      );

      expect(report.isPlaceholderOnion, isTrue);
      expect(report.remoteOnion, equals(DiagnosticStatus.warning));
      expect(report.remoteOnionDetails, contains('Endereço padrão de demonstração'));
      expect(report.toSanitizedSummary(), contains('DIAGNÓSTICO EM CAMADAS'));
    });
  });

  group('Máquina de Estados de Downloads & Métricas Transparentes (Seção 1 & 2)', () {
    test('Valida transições da máquina de estados explícita', () {
      expect(DownloadStatus.queued.canTransitionTo(DownloadStatus.starting), isTrue);
      expect(DownloadStatus.starting.canTransitionTo(DownloadStatus.downloading), isTrue);
      expect(DownloadStatus.downloading.canTransitionTo(DownloadStatus.pausing), isTrue);
      expect(DownloadStatus.pausing.canTransitionTo(DownloadStatus.paused), isTrue);
      expect(DownloadStatus.paused.canTransitionTo(DownloadStatus.resuming), isTrue);
      expect(DownloadStatus.resuming.canTransitionTo(DownloadStatus.downloading), isTrue);
      expect(DownloadStatus.downloading.canTransitionTo(DownloadStatus.finalizing), isTrue);
      expect(DownloadStatus.finalizing.canTransitionTo(DownloadStatus.completed), isTrue);

      // Transições inválidas são rejeitadas
      expect(DownloadStatus.completed.canTransitionTo(DownloadStatus.downloading), isFalse);
      expect(DownloadStatus.queued.canTransitionTo(DownloadStatus.finalizing), isFalse);
    });

    test('Métricas de velocidade média e segmentos formatam adequadamente', () {
      final task = DownloadTask(
        id: 'test_task',
        url: 'http://example.org/debian.iso',
        destinationPath: '/tmp/debian.iso',
        fileName: 'debian.iso',
        createdAt: DateTime(2026, 1, 1),
        status: DownloadStatus.downloading,
        speedBytesPerSec: 1048576, // 1 MB/s
        averageSpeedBytesPerSec: 524288, // 512 KB/s
        activeSegments: 6,
        splitCount: 6,
        downloadEngine: 'aria2 RPC',
      );

      expect(task.formattedSpeed, equals('1.00 MB/s'));
      expect(task.formattedAverageSpeed, equals('512 KB/s'));
      expect(task.activeSegments, equals(6));
      expect(task.downloadEngine, equals('aria2 RPC'));
    });
  });
}
