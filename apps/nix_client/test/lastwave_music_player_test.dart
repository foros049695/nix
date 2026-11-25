import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/media/nix_music_player_controller.dart';
import 'package:nix_client/core/media/pager_playlist.dart';
import 'package:nix_client/features/media/lastwave_music_player_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Nix LastWave Music Player — Controlador & DSP Settings Soberanos', () {
    late NixMusicPlayerController controller;

    setUp(() {
      controller = NixMusicPlayerController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('Inicialização limpa sem músicas artificiais e estado vazio', () {
      expect(controller.playlist, isEmpty);
      expect(controller.currentIndex, -1);
      expect(controller.currentTrack, isNull);
      expect(controller.isPlaying, isFalse);
    });

    test('PagerTrack calcula corretamente badges técnicas de qualidade de áudio real', () {
      const hiResTrack = PagerTrack(
        uri: 'file:///sample.flac',
        name: 'Hi-Res Sample',
        audioFormat: 'FLAC',
        sampleRate: '96 kHz',
        bitDepth: '24-bit',
      );
      expect(hiResTrack.audioQualityBadge, contains('Hi-Res'));
      expect(hiResTrack.audioQualityBadge, contains('FLAC'));
      expect(hiResTrack.audioQualityBadge, contains('24-bit'));
      expect(hiResTrack.audioQualityBadge, contains('96 kHz'));

      const standardFlac = PagerTrack(
        uri: 'file:///standard.flac',
        name: 'Standard Flac',
        audioFormat: 'FLAC',
        sampleRate: '44.1 kHz',
        bitDepth: '16-bit',
      );
      expect(standardFlac.audioQualityBadge, contains('FLAC'));
      expect(standardFlac.audioQualityBadge, contains('16-bit'));

      const mp3Track = PagerTrack(
        uri: 'file:///track.mp3',
        name: 'MP3 Track',
        audioFormat: 'MP3',
        bitRateKbps: 320,
      );
      expect(mp3Track.audioQualityBadge, 'MP3 · 320 kbps');
    });

    test('Controles de transporte com faixas reais: play, pause, next, previous, shuffle e repeat', () {
      const trackA = PagerTrack(uri: 'file:///trackA.flac', name: 'Faixa A', durationSeconds: 120);
      const trackB = PagerTrack(uri: 'file:///trackB.flac', name: 'Faixa B', durationSeconds: 180);
      controller.setPlaylist([trackA, trackB]);

      expect(controller.playlist.length, 2);
      expect(controller.currentTrack?.name, 'Faixa A');
      expect(controller.isPlaying, isFalse);

      controller.resume();
      // O estado deve permanecer parado até o backend confirmar reprodução.
      // Um URI ausente não pode produzir um "tocando" fictício.
      expect(controller.isPlaying, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.isPlaying, isFalse);
      expect(controller.playbackError, isNotNull);

      controller.pause();
      expect(controller.isPlaying, isFalse);

      controller.next();
      expect(controller.currentTrack?.name, 'Faixa B');

      controller.previous();
      expect(controller.currentTrack?.name, 'Faixa A');

      controller.toggleShuffle();
      expect(controller.isShuffle, isTrue);

      controller.toggleRepeat();
      expect(controller.isRepeat, isTrue);

      controller.setVolume(0.5);
      expect(controller.volume, 0.5);
    });

    test('Seek não cria duração falsa quando metadados não possuem duração', () {
      const track = PagerTrack(
        uri: 'file:///nix-file-does-not-exist-test.mp3',
        name: 'Faixa sem duração',
      );
      controller.setPlaylist([track]);
      expect(controller.duration, Duration.zero);
      expect(controller.isPlaying, isFalse);
    });

    test('Configurações de DSP e AutoEQ atualizam reativamente', () {
      expect(controller.dspSettings.autoEqEnabled, isTrue);
      expect(controller.dspSettings.bassGainDb, 0.0);

      controller.updateDspSettings(
        controller.dspSettings.copyWith(
          autoEqEnabled: false,
          bassGainDb: 4.5,
          trebleGainDb: -2.0,
          tiltDbPerOct: 1.0,
          activeTarget: 'Harman In-Ear 2019v2',
        ),
      );

      expect(controller.dspSettings.autoEqEnabled, isFalse);
      expect(controller.dspSettings.bassGainDb, 4.5);
      expect(controller.dspSettings.trebleGainDb, -2.0);
      expect(controller.dspSettings.tiltDbPerOct, 1.0);
      expect(controller.dspSettings.activeTarget, 'Harman In-Ear 2019v2');
    });

    test('Equalizador de 15 bandas atualiza individualmente', () {
      expect(controller.dspSettings.graphicEq15Bands.length, 15);
      final updatedBands = List<double>.from(controller.dspSettings.graphicEq15Bands);
      updatedBands[0] = 6.0; // 25 Hz
      updatedBands[14] = -4.0; // 16 kHz

      controller.updateDspSettings(
        controller.dspSettings.copyWith(graphicEq15Bands: updatedBands),
      );

      expect(controller.dspSettings.graphicEq15Bands[0], 6.0);
      expect(controller.dspSettings.graphicEq15Bands[14], -4.0);
    });
  });

  group('Nix LastWave Music Player — Telas Visuais Sem Dados Falsos', () {
    late NixMusicPlayerController controller;

    setUp(() {
      controller = NixMusicPlayerController();
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('Now Playing exibe mensagem de biblioteca vazia quando não há faixas', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LastWaveMusicPlayerScreen(controller: controller, initialTabIndex: 0),
        ),
      );
      await tester.pump();

      expect(find.text('Now Playing'), findsOneWidget);
      expect(find.text('Biblioteca'), findsOneWidget);
      expect(find.text('AutoEQ DSP'), findsOneWidget);

      // Não exibe faixas falsas como Sabrina Carpenter
      expect(find.text('Espresso'), findsNothing);
      expect(find.textContaining('Sabrina Carpenter'), findsNothing);

      // Exibe estado vazio real
      expect(find.textContaining('Nenhuma música adicionada'), findsOneWidget);
    });

    testWidgets('Biblioteca exibe botões reais de importar e escanear quando vazia', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LastWaveMusicPlayerScreen(controller: controller, initialTabIndex: 1),
        ),
      );
      await tester.pump();

      expect(find.text('Biblioteca Musical Local'), findsOneWidget);
      expect(find.textContaining('0 faixas disponíveis'), findsOneWidget);
      expect(find.text('Importar Áudio'), findsOneWidget);
      expect(find.text('Escanear Pasta'), findsOneWidget);

      // Não exibe músicas fictícias na fila
      expect(find.text('A Found Memory'), findsNothing);
      expect(find.text('Liminal0y1bg554'), findsNothing);
      expect(find.text('In the Clouds'), findsNothing);
    });

    testWidgets('Aba AutoEQ DSP exibe Saída Padrão sem fones de ouvido artificiais', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: LastWaveMusicPlayerScreen(controller: controller, initialTabIndex: 2),
        ),
      );
      await tester.pump();

      expect(find.text('Motor AutoEQ / DSP'), findsOneWidget);
      expect(find.text('AutoEQ / PEQ'), findsOneWidget);
      expect(find.text('15-Band Graphic'), findsOneWidget);

      // Não exibe fones inexistentes como CMF Nothing Buds
      expect(find.textContaining('CMF by Nothing Buds Pro 2'), findsNothing);
      expect(find.text('Saída Padrão do Sistema'), findsOneWidget);

      expect(find.textContaining('Resposta de Frequência'), findsOneWidget);
      expect(find.text('Curva Alvo (Target Curve)'), findsOneWidget);
      expect(find.text('Graves (Bass Gain)'), findsOneWidget);
      expect(find.text('Inclinação Tonal (Tilt)'), findsOneWidget);
    });
  });
}
