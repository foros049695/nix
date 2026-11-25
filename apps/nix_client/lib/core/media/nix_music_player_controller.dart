import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'pager_playlist.dart';

/// Configurações do processador de sinal digital (DSP) e AutoEQ do Nix.
class AudioDspSettings {
  final bool autoEqEnabled;
  final String activeTarget; // 'Harman In-Ear', 'Harman Over-Ear', 'Flat / Studio', 'Bass Boost'
  final double bassGainDb; // -12.0 a +12.0 dB
  final double trebleGainDb; // -12.0 a +12.0 dB
  final double tiltDbPerOct; // -3.0 a +3.0 dB/oct
  final double preampDb; // -12.0 a 0.0 dB
  final bool volumeNormalization;
  final List<double> graphicEq15Bands; // Ganhos nas 15 frequências padrão
  final String outputDevice;

  const AudioDspSettings({
    this.autoEqEnabled = true,
    this.activeTarget = 'Harman-style Target (AutoEQ default)',
    this.bassGainDb = 0.0,
    this.trebleGainDb = 0.0,
    this.tiltDbPerOct = 0.0,
    this.preampDb = 0.0,
    this.volumeNormalization = true,
    this.graphicEq15Bands = const [
      0.0, 0.0, 0.0, 0.0, 0.0,
      0.0, 0.0, 0.0, 0.0, 0.0,
      0.0, 0.0, 0.0, 0.0, 0.0,
    ],
    this.outputDevice = 'Padrão do Sistema (PipeWire / PulseAudio)',
  });

  static const List<int> bandFrequenciesHz = [
    25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000
  ];

  AudioDspSettings copyWith({
    bool? autoEqEnabled,
    String? activeTarget,
    double? bassGainDb,
    double? trebleGainDb,
    double? tiltDbPerOct,
    double? preampDb,
    bool? volumeNormalization,
    List<double>? graphicEq15Bands,
    String? outputDevice,
  }) {
    return AudioDspSettings(
      autoEqEnabled: autoEqEnabled ?? this.autoEqEnabled,
      activeTarget: activeTarget ?? this.activeTarget,
      bassGainDb: bassGainDb ?? this.bassGainDb,
      trebleGainDb: trebleGainDb ?? this.trebleGainDb,
      tiltDbPerOct: tiltDbPerOct ?? this.tiltDbPerOct,
      preampDb: preampDb ?? this.preampDb,
      volumeNormalization: volumeNormalization ?? this.volumeNormalization,
      graphicEq15Bands: graphicEq15Bands ?? this.graphicEq15Bands,
      outputDevice: outputDevice ?? this.outputDevice,
    );
  }
}

/// Controlador central unificado de reprodução musical do Nix, compartilhado entre
/// Pager, Acervo Musical, Media Index e a nova interface LastWave (Seção 15).
class NixMusicPlayerController extends ChangeNotifier {
  List<PagerTrack> _playlist = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  bool _isShuffle = false;
  bool _isRepeat = false;
  double _volume = 0.85;

  Duration _position = Duration.zero;
  Timer? _playbackTicker;
  Duration? _backendDuration;
  int _session = 0;
  bool _androidPrepared = false;
  bool _pollingAndroid = false;
  String? _playbackError;
  static const MethodChannel _androidAudio = MethodChannel('com.projetonix.nix/pager_audio');

  AudioDspSettings _dspSettings = const AudioDspSettings();
  Process? _activeAudioProcess;

  NixMusicPlayerController() {
    _playlist = [];
    _currentIndex = -1;
  }

  List<PagerTrack> get playlist => List.unmodifiable(_playlist);
  int get currentIndex => _currentIndex;
  PagerTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _playlist.length)
          ? _playlist[_currentIndex]
          : null;

  bool get isPlaying => _isPlaying;
  bool get isShuffle => _isShuffle;
  bool get isRepeat => _isRepeat;
  double get volume => _volume;

  Duration get position => _position;
  Duration get duration => _backendDuration ??
      (currentTrack != null && currentTrack!.durationSeconds > 0
          ? Duration(seconds: currentTrack!.durationSeconds)
          : Duration.zero);
  String? get playbackError => _playbackError;

  AudioDspSettings get dspSettings => _dspSettings;

  void setPlaylist(List<PagerTrack> tracks, {int startIndex = 0}) {
    _session++;
    _playbackTicker?.cancel();
    _stopNativeProcess();
    if (Platform.isAndroid) unawaited(_androidAudio.invokeMethod<void>('stop').catchError((Object _) {}));
    _androidPrepared = false;
    _isPlaying = false;
    _backendDuration = null;
    _playlist = List.of(tracks);
    _currentIndex = tracks.isNotEmpty ? startIndex.clamp(0, tracks.length - 1) : -1;
    _position = Duration.zero;
    notifyListeners();
  }

  void addTrack(PagerTrack track) {
    _playlist.add(track);
    if (_currentIndex == -1) _currentIndex = 0;
    notifyListeners();
  }

  void removeTrackAt(int index) {
    if (index < 0 || index >= _playlist.length) return;
    if (_currentIndex == index) {
      pause();
      if (Platform.isAndroid) unawaited(_androidAudio.invokeMethod<void>('stop').catchError((Object _) {}));
      _androidPrepared = false;
      _session++;
    }
    _playlist.removeAt(index);
    if (_currentIndex >= _playlist.length) {
      _currentIndex = _playlist.length - 1;
    }
    notifyListeners();
  }

  Future<void> playTrack(PagerTrack track) async {
    final idx = _playlist.indexWhere((t) => t.uri == track.uri);
    if (idx != -1) {
      _currentIndex = idx;
    } else {
      _playlist.add(track);
      _currentIndex = _playlist.length - 1;
    }
    _position = Duration.zero;
    _startPlayback();
  }

  void togglePlayPause() {
    if (_isPlaying) {
      pause();
    } else {
      resume();
    }
  }

  void pause() {
    if (Platform.isAndroid && _androidPrepared) {
      unawaited(_setAndroidPaused(true));
      return;
    }
    _isPlaying = false;
    _playbackTicker?.cancel();
    _stopNativeProcess();
    notifyListeners();
  }

  void resume() {
    if (_currentIndex == -1 && _playlist.isNotEmpty) _currentIndex = 0;
    if (_currentIndex == -1) return;
    if (Platform.isAndroid && _androidPrepared) {
      unawaited(_setAndroidPaused(false));
    } else {
      _startPlayback();
    }
  }

  void next() {
    if (_playlist.isEmpty) return;
    if (_isShuffle) {
      _currentIndex = Random().nextInt(_playlist.length);
    } else {
      _currentIndex = (_currentIndex + 1) % _playlist.length;
    }
    _position = Duration.zero;
    _startPlayback();
  }

  void previous() {
    if (_playlist.isEmpty) return;
    if (_position.inSeconds > 3) {
      seek(Duration.zero);
      return;
    }
    _currentIndex = (_currentIndex - 1 + _playlist.length) % _playlist.length;
    _position = Duration.zero;
    _startPlayback();
  }

  void seek(Duration newPosition) {
    final pos = newPosition < Duration.zero ? Duration.zero :
        (duration > Duration.zero && newPosition > duration ? duration : newPosition);
    if (Platform.isAndroid && _androidPrepared) {
      unawaited(_seekAndroid(pos));
      return;
    }
    _position = pos;
    if (_isPlaying && (Platform.isLinux || Platform.isWindows)) _startPlayback();
    notifyListeners();
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    notifyListeners();
  }

  void toggleRepeat() {
    _isRepeat = !_isRepeat;
    notifyListeners();
  }

  void setVolume(double val) {
    _volume = val.clamp(0.0, 1.0);
    if (Platform.isAndroid && _androidPrepared) {
      unawaited(_androidAudio.invokeMethod<void>('volume', {'value': _volume})
          .catchError((Object _) {}));
    } else if (_isPlaying && (Platform.isLinux || Platform.isWindows)) {
      _startPlayback();
    }
    notifyListeners();
  }

  void updateDspSettings(AudioDspSettings settings) {
    _dspSettings = settings;
    notifyListeners();
    // Aplica alterações de DSP ao pipeline de áudio ativo
    if (_isPlaying) {
      _applyDspToActivePlayback();
    }
  }

  void _startPlayback() {
    final session = ++_session;
    _playbackTicker?.cancel();
    _stopNativeProcess();
    _androidPrepared = false;
    _playbackError = null;
    _isPlaying = false;
    notifyListeners();
    unawaited(_spawnNativePlayback(session));
  }

  Future<void> _spawnNativePlayback(int session) async {
    try {
      final track = currentTrack;
      if (track == null) throw StateError('Nenhuma faixa selecionada.');
      final uri = Uri.tryParse(track.uri);
      if (uri == null) throw StateError('URI de áudio inválida.');
      if (Platform.isAndroid) {
        if (uri.scheme != 'content') {
          throw StateError('Selecione um arquivo local com o seletor de áudio do Android.');
        }
        await _androidAudio.invokeMethod<void>('play', {'uri': track.uri});
        if (session != _session) {
          await _androidAudio.invokeMethod<void>('stop');
          return;
        }
        _androidPrepared = true;
        await _androidAudio.invokeMethod<void>('volume', {'value': _volume});
        await _pollAndroid(session);
        _playbackTicker = Timer.periodic(
          const Duration(milliseconds: 500),
          (_) => unawaited(_pollAndroid(session)),
        );
        return;
      }

      if (!Platform.isLinux && !Platform.isWindows) {
        throw UnsupportedError('Reprodução não suportada nesta plataforma.');
      }
      if (uri.scheme != 'file') {
        throw StateError('É necessário um arquivo local válido para reprodução desktop.');
      }
      final file = File.fromUri(uri);
      if (!await file.exists()) throw StateError('Arquivo de música não encontrado.');
      final args = <String>[
        '--no-video',
        '--no-terminal',
        '--volume=' + (_volume * 100).round().toString(),
        if (_position > Duration.zero) '--start=' + (_position.inMilliseconds / 1000).toStringAsFixed(3),
      ];
      if (_dspSettings.autoEqEnabled && Platform.isLinux) {
        final bass = _dspSettings.bassGainDb;
        final treble = _dspSettings.trebleGainDb;
        args.add('--af=lavfi=[equalizer=f=100:t=q:w=1:g=' +
            bass.toString() +
            ',equalizer=f=10000:t=q:w=1:g=' +
            treble.toString() + ']');
      }
      args.add(file.path);
      final process = await Process.start(Platform.isWindows ? 'mpv.exe' : 'mpv', args);
      if (session != _session) {
        process.kill();
        return;
      }
      _activeAudioProcess = process;
      _isPlaying = true;
      notifyListeners();
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      unawaited(process.exitCode.then((exitCode) {
        if (session != _session || !identical(_activeAudioProcess, process)) return;
        _activeAudioProcess = null;
        _playbackTicker?.cancel();
        _isPlaying = false;
        if (exitCode != 0) _playbackError = 'O reprodutor mpv terminou com erro.';
        notifyListeners();
      }));
      // Desktop ainda depende de posição real via IPC do mpv. Não inventar
      // progresso a partir de um cronômetro enquanto essa conexão não existir.
    } catch (error) {
      if (session != _session) return;
      _playbackTicker?.cancel();
      _activeAudioProcess = null;
      _androidPrepared = false;
      _isPlaying = false;
      _playbackError = error.toString();
      notifyListeners();
    }
  }

  Future<void> _pollAndroid(int session) async {
    if (_pollingAndroid || session != _session) return;
    _pollingAndroid = true;
    try {
      final status = await _androidAudio.invokeMapMethod<String, dynamic>('position');
      if (session != _session || status == null) return;
      final isActuallyPlaying = status['isPlaying'] == true;
      final positionMs = (status['positionMs'] as num?)?.toInt() ?? 0;
      final durationMs = (status['durationMs'] as num?)?.toInt() ?? 0;
      _position = Duration(milliseconds: positionMs.clamp(0, 2147483647));
      if (durationMs > 0) _backendDuration = Duration(milliseconds: durationMs);
      final completed = _isPlaying && !isActuallyPlaying;
      _isPlaying = isActuallyPlaying;
      notifyListeners();
      if (completed) {
        _playbackTicker?.cancel();
        _androidPrepared = false;
        if (_playlist.length > 1 || _isRepeat) {
          next();
        }
      }
    } catch (error) {
      if (session != _session) return;
      _playbackTicker?.cancel();
      _androidPrepared = false;
      _isPlaying = false;
      _playbackError = error.toString();
      notifyListeners();
    } finally {
      _pollingAndroid = false;
    }
  }

  Future<void> _setAndroidPaused(bool paused) async {
    final session = _session;
    try {
      final status = await _androidAudio.invokeMapMethod<String, dynamic>(
        paused ? 'pause' : 'resume',
      );
      if (session != _session) return;
      _isPlaying = status?['isPlaying'] == true;
      if (!paused && _playbackTicker == null) {
        _playbackTicker = Timer.periodic(
          const Duration(milliseconds: 500),
          (_) => unawaited(_pollAndroid(session)),
        );
      }
      if (paused) {
        _playbackTicker?.cancel();
        _playbackTicker = null;
      }
      notifyListeners();
    } catch (error) {
      if (session == _session) {
        _playbackError = error.toString();
        notifyListeners();
      }
    }
  }

  Future<void> _seekAndroid(Duration position) async {
    final session = _session;
    try {
      await _androidAudio.invokeMethod<void>('seek', {
        'positionMs': position.inMilliseconds,
      });
      if (session == _session) await _pollAndroid(session);
    } catch (error) {
      if (session == _session) {
        _playbackError = error.toString();
        notifyListeners();
      }
    }
  }

  void _applyDspToActivePlayback() {
    if (_isPlaying && (Platform.isLinux || Platform.isWindows)) _startPlayback();
  }

  void _stopNativeProcess() {
    try {
      _activeAudioProcess?.kill();
    } catch (_) {}
    _activeAudioProcess = null;
  }

  @override
  void dispose() {
    _session++;
    _playbackTicker?.cancel();
    if (Platform.isAndroid) unawaited(_androidAudio.invokeMethod<void>('stop').catchError((Object _) {}));
    _stopNativeProcess();
    super.dispose();
  }
}
