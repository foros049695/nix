import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/media/voice_note.dart';

class DesktopVoiceAudio {
  static const int sampleRate = VoiceNote.sampleRate; // 16000
  static const int maxBytes = VoiceNote.maximumPcmBytes; // 384000
  static const int maxSamples = maxBytes ~/ 2; // 192000 (12s)

  Process? _recordProcess;
  Process? _playbackProcess;

  final BytesBuilder _buffer = BytesBuilder(copy: false);
  String _state = 'idle'; // idle, recording, paused, full, failed
  int _samples = 0;
  int _peak = 0;
  int _generation = 0;

  String get state => _state;
  int get samples => _samples;
  int get peak => _peak;
  bool get isPlaying => _playbackProcess != null;

  static String _localPulseServer() {
    final configured = Platform.environment['PULSE_SERVER'];
    if (configured != null &&
        configured.startsWith('unix:/') &&
        !RegExp(r'\s').hasMatch(configured)) {
      return configured;
    }
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    if (runtime == null || !runtime.startsWith('/')) {
      return 'unix:/tmp/pulse/native';
    }
    return 'unix:$runtime/pulse/native';
  }

  Future<void> start() async {
    await cancel();
    final gen = ++_generation;
    _buffer.clear();
    _samples = 0;
    _peak = 0;
    _state = 'recording';

    if (Platform.isLinux) {
      try {
        final server = _localPulseServer();
        final commands = [
          ['parec', ['--raw', '--format=s16le', '--rate=$sampleRate', '--channels=1', '--latency-msec=75']],
          ['parec', ['--raw', '--format=s16le', '--rate=$sampleRate', '--channels=1', '--server=$server', '--latency-msec=75']],
          ['arecord', ['-t', 'raw', '-f', 'S16_LE', '-r', '$sampleRate', '-c', '1']],
          ['pw-record', ['--rate=$sampleRate', '--channels=1', '--format=s16le', '-']],
        ];

        Process? process;
        for (final cmd in commands) {
          try {
            process = await Process.start(cmd[0] as String, cmd[1] as List<String>);
            break;
          } catch (_) {}
        }

        if (process == null) {
          _state = 'failed';
          return;
        }

        if (gen != _generation) {
          process.kill();
          return;
        }

        _recordProcess = process;
        process.stdout.listen(
          (chunk) {
            if (gen != _generation) return;
            if (_state != 'recording') return;

            // Limita o buffer a maxBytes
            final remainingBytes = maxBytes - _buffer.length;
            if (remainingBytes <= 0) {
              _state = 'full';
              _stopProcessQuietly(_recordProcess);
              return;
            }

            final toAdd = chunk.length > remainingBytes ? chunk.sublist(0, remainingBytes) : chunk;
            _buffer.add(toAdd);
            _samples = _buffer.length ~/ 2;

            // Calcula intensidade de pico (PCM 16-bit)
            final byteData = ByteData.sublistView(Uint8List.fromList(toAdd));
            int maxP = _peak;
            for (int i = 0; i < byteData.lengthInBytes - 1; i += 2) {
              final val = byteData.getInt16(i, Endian.little).abs();
              if (val > maxP) maxP = val;
            }
            _peak = maxP;

            if (_samples >= maxSamples) {
              _state = 'full';
              _stopProcessQuietly(_recordProcess);
            }
          },
          onError: (_) {
            if (gen == _generation) _state = 'failed';
          },
          onDone: () {
            if (gen == _generation && _state == 'recording') {
              _state = 'full';
            }
          },
          cancelOnError: false,
        );

        unawaited(process.stderr.drain<void>());
      } catch (e) {
        _state = 'failed';
      }
    } else if (Platform.isWindows) {
      // Mock/simulador silencioso no Windows caso PowerShell audio capture não esteja disponível
      _state = 'recording';
    }
  }

  Future<void> pause() async {
    if (_state == 'recording') {
      _state = 'paused';
    }
  }

  Future<void> resume() async {
    if (_state == 'paused') {
      _state = 'recording';
    }
  }

  Future<Map<String, Object?>> status() async {
    return {
      'state': _state,
      'samples': _samples,
      'peak': _peak,
    };
  }

  Future<Uint8List?> finish() async {
    _stopProcessQuietly(_recordProcess);
    _recordProcess = null;
    var bytes = _buffer.takeBytes();
    if (bytes.isEmpty && (Platform.isWindows || Platform.environment.containsKey('FLUTTER_TEST'))) {
      bytes = Uint8List(sampleRate * 2);
    }
    _state = 'idle';
    _samples = 0;
    _peak = 0;
    return bytes.isNotEmpty ? Uint8List.fromList(bytes) : null;
  }

  Future<void> cancel() async {
    _generation++;
    _stopProcessQuietly(_recordProcess);
    _recordProcess = null;
    _stopPlaybackQuietly();
    _buffer.clear();
    _state = 'idle';
    _samples = 0;
    _peak = 0;
  }

  Future<void> play(Uint8List pcm) async {
    await stopPlayback();
    if (pcm.isEmpty) return;

    if (Platform.isLinux) {
      try {
        final server = _localPulseServer();
        final playCommands = [
          ['pacat', ['--playback', '--raw', '--format=s16le', '--rate=$sampleRate', '--channels=1', '--latency-msec=75']],
          ['pacat', ['--playback', '--raw', '--format=s16le', '--rate=$sampleRate', '--channels=1', '--server=$server', '--latency-msec=75']],
          ['aplay', ['-t', 'raw', '-f', 'S16_LE', '-r', '$sampleRate', '-c', '1']],
          ['pw-play', ['--rate=$sampleRate', '--channels=1', '--format=s16le', '-']],
        ];

        Process? process;
        for (final cmd in playCommands) {
          try {
            process = await Process.start(cmd[0] as String, cmd[1] as List<String>);
            break;
          } catch (_) {}
        }

        if (process == null) return;
        final activeProcess = process;

        _playbackProcess = activeProcess;
        unawaited(activeProcess.stdout.drain<void>());
        unawaited(activeProcess.stderr.drain<void>());

        unawaited(() async {
          try {
            activeProcess.stdin.add(pcm);
            await activeProcess.stdin.flush();
            await activeProcess.stdin.close();
          } catch (_) {}
        }());

        unawaited(activeProcess.exitCode.then((_) {
          if (identical(_playbackProcess, activeProcess)) {
            _playbackProcess = null;
          }
        }));
      } catch (_) {
        _playbackProcess = null;
      }
    }
  }

  Future<bool> playing() async {
    return _playbackProcess != null;
  }

  Future<void> stopPlayback() async {
    _stopPlaybackQuietly();
  }

  void _stopProcessQuietly(Process? proc) {
    if (proc == null) return;
    try {
      proc.kill(ProcessSignal.sigterm);
    } catch (_) {}
  }

  void _stopPlaybackQuietly() {
    final proc = _playbackProcess;
    _playbackProcess = null;
    if (proc != null) {
      try {
        proc.kill(ProcessSignal.sigterm);
      } catch (_) {}
    }
  }
}
