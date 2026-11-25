import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/media/nix_music_player_controller.dart';
import 'package:nix_client/core/media/pager_playlist.dart';
import 'package:nix_client/features/media/lastwave_music_player_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Nix LastWave Music Player — Controlador & DSP Settings', () {
    late NixMusicPlayerController controller;

    setUp(() {
      controller = NixMusicPlayerController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('Inicialização contém playlist padrão de alta fidelidade e índice válido', () {
      expect(controller.playlist, isNotEmpty);
      expect(controller.currentIndex, 0);
      expect(controller.currentTrack, isNotNull);
      expect(controller.currentTrack!.name, 'Espresso');
      expect(controller.currentTrack!.artist, 'Sabrina Carpenter');
      expect(controller.isPlaying, isFalse);
    });

    test('PagerTrack calcula corretamente badges técnicas de qualidade de áudio', () {
      const hiResTrack = PagerTrack(
        uri: 'file:///sample.flac',
        name: 'Hi-Res Sample',
        audioFormat: 'FLAC',
        sampleRate: '96 kHz',
        bitDepth: '24-bit',
      );
      expect(hiResTrack.audioQualityBadge, contains('Hi-Res Lossless'));
      expect(hiResTrack.audioQualityBadge, contains('24-bit/96 kHz'));

      const standardFlac = PagerTrack(
        uri: 'file:///standard.flac',
        name: 'Standard Flac',
        audioFormat: 'FLAC',
        sampleRate: '44.1 kHz',
        bitDepth: '16-bit',
      );
      expect(standardFlac.audioQualityBadge, contains('Lossless'));

      const mp3Track = PagerTrack(
        uri: 'file:///track.mp3',
        name: 'MP3 Track',
        audioFormat: 'MP3',
        bitRateKbps: 320,
      );
      expect(mp3Track.audioQualityBadge, 'MP3 · 320 kbps');
    });

    test('Controles de transporte: play, pause, next, previous, shuffle e repeat', () {
      expect(controller.isPlaying, isFalse);
      controller.resume();
      expect(controller.isPlaying, isTrue);

      controller.pause();
      expect(controller.isPlaying, isFalse);

      final initialIdx = controller.currentIndex;
      controller.next();
      expect(controller.currentIndex, (initialIdx + 1) % controller.playlist.length);

      controller.previous();
      expect(controller.currentIndex, initialIdx);

      controller.toggleShuffle();
      expect(controller.isShuffle, isTrue);

      controller.toggleRepeat();
      expect(controller.isRepeat, isTrue);

      controller.setVolume(0.5);
      expect(controller.volume, 0.5);
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

  group('Nix LastWave Music Player — Telas Visuais (Now Playing, Biblioteca, AutoEQ)', () {
    late NixMusicPlayerController controller;

    setUp(() {
      controller = NixMusicPlayerController();
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('Renderiza as 3 abas e a visualização Now Playing por padrão', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LastWaveMusicPlayerScreen(controller: controller, initialTabIndex: 0),
        ),
      );
      await tester.pump();

      expect(find.text('Now Playing'), findsOneWidget);
      expect(find.text('Biblioteca'), findsOneWidget);
      expect(find.text('AutoEQ DSP'), findsOneWidget);

      // Metadados da faixa ativa
      expect(find.text('Espresso'), findsOneWidget);
      expect(find.textContaining('Sabrina Carpenter'), findsOneWidget);
      expect(find.textContaining('Hi-Res Lossless'), findsOneWidget);

      // Ícones dos controles
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
    });

    testWidgets('Navega para a aba Biblioteca e exibe lista de faixas e botão play cápsula', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LastWaveMusicPlayerScreen(controller: controller, initialTabIndex: 1),
        ),
      );
      await tester.pump();

      expect(find.text('Acervo Nix Soberano'), findsOneWidget);
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Faixas da Fila'), findsOneWidget);

      // Faixas na biblioteca
      expect(find.text('A Found Memory'), findsOneWidget);
      expect(find.text('Liminal0y1bg554'), findsOneWidget);
      expect(find.text('In the Clouds'), findsOneWidget);
    });

    testWidgets('Navega para a aba AutoEQ DSP e exibe curvas e equalizador', (tester) async {
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
      expect(find.textContaining('CMF by Nothing Buds Pro 2'), findsOneWidget);
      expect(find.textContaining('Resposta de Frequência'), findsOneWidget);
      expect(find.text('Curva Alvo (Target Curve)'), findsOneWidget);
      expect(find.text('Graves (Bass Gain)'), findsOneWidget);
      expect(find.text('Inclinação Tonal (Tilt)'), findsOneWidget);
    });
  });
}
