import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
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
  final Duration _duration = const Duration(minutes: 3, seconds: 20);
  Timer? _playbackTicker;

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
  Duration get duration => currentTrack != null && currentTrack!.durationSeconds > 0
      ? Duration(seconds: currentTrack!.durationSeconds)
      : _duration;

  AudioDspSettings get dspSettings => _dspSettings;

  void setPlaylist(List<PagerTrack> tracks, {int startIndex = 0}) {
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
    _isPlaying = false;
    _playbackTicker?.cancel();
    _stopNativeProcess();
    notifyListeners();
  }

  void resume() {
    if (_currentIndex == -1 && _playlist.isNotEmpty) {
      _currentIndex = 0;
    }
    if (_currentIndex != -1) {
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
    _position = newPosition;
    if (_position > duration) _position = duration;
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
    _isPlaying = true;
    _playbackTicker?.cancel();
    _playbackTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }
      if (_position.inSeconds < duration.inSeconds) {
        _position += const Duration(seconds: 1);
        notifyListeners();
      } else {
        if (_isRepeat) {
          _position = Duration.zero;
          notifyListeners();
        } else {
          next();
        }
      }
    });

    _spawnNativePlayback();
    notifyListeners();
  }

  Future<void> _spawnNativePlayback() async {
    _stopNativeProcess();
    final track = currentTrack;
    if (track == null) return;

    final uri = Uri.tryParse(track.uri);
    if (uri != null && uri.scheme == 'file') {
      final file = File.fromUri(uri);
      if (await file.exists()) {
        try {
          final isLinux = Platform.isLinux;
          if (isLinux) {
            // Constrói filtro de equalização real se AutoEQ estiver ativo
            final args = <String>[
              '--no-video',
              '--no-terminal',
              '--volume=${(_volume * 100).toInt()}',
            ];

            if (_dspSettings.autoEqEnabled) {
              // Aplica ganho de graves e agudos real via lavfi equalizer
              final bass = _dspSettings.bassGainDb;
              final treble = _dspSettings.trebleGainDb;
              args.add('--af=lavfi=[equalizer=f=100:t=q:w=1:g=$bass,equalizer=f=10000:t=q:w=1:g=$treble]');
            }

            args.add(file.path);
            _activeAudioProcess = await Process.start('mpv', args);
          }
        } catch (_) {}
      }
    }
  }

  void _applyDspToActivePlayback() {
    // Recarrega filtros no processo ativo
    _spawnNativePlayback();
  }

  void _stopNativeProcess() {
    try {
      _activeAudioProcess?.kill();
    } catch (_) {}
    _activeAudioProcess = null;
  }

  @override
  void dispose() {
    _playbackTicker?.cancel();
    _stopNativeProcess();
    super.dispose();
  }
}
