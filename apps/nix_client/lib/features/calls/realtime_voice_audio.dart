import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/calls/onion_voice_link.dart';

class RealtimeVoiceAudio {
  static const _android = MethodChannel('com.projetonix.nix/voice_notes');
  static const _windows = MethodChannel('com.projetonix.nix/audio_diagnostic');
  static const _pulseFormat = [
    '--raw',
    '--format=s16le',
    '--rate=16000',
    '--channels=1'
  ];
  static String _localPulseServer() {
    final configured = Platform.environment['PULSE_SERVER'];
    if (configured != null &&
        configured.startsWith('unix:/') &&
        !RegExp(r'\s').hasMatch(configured)) return configured;
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    if (runtime == null || !runtime.startsWith('/')) {
      throw StateError('Saída PulseAudio local indisponível.');
    }
    return 'unix:$runtime/pulse/native';
  }

  MethodChannel get _bridge => Platform.isAndroid ? _android : _windows;
  bool get supported =>
      Platform.isAndroid || Platform.isLinux || Platform.isWindows;

  Process? _input;
  Process? _output;
  Uint8List _pending = Uint8List(0);
  int _generation = 0;
  int _outputGeneration = 0;
  bool _capturing = false;
  bool _captureFailed = false;
  bool _starting = false;
  bool _playing = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_disposed || _starting || _capturing || !supported) return;
    final generation = ++_generation;
    _starting = true;
    _captureFailed = false;
    try {
      if (Platform.isLinux) {
        final input = await Process.start('parec', [
          ..._pulseFormat,
          '--server=${_localPulseServer()}',
          '--latency-msec=75'
        ]);
        if (generation != _generation) {
          input.kill();
          return;
        }
        _input = input;
        input.stdout.listen((chunk) {
          if (generation != _generation) return;
          final bytes = Uint8List.fromList([..._pending, ...chunk]);
          _pending.fillRange(0, _pending.length, 0);
          final offset = (bytes.length - OnionVoiceLink.maxAudioBytes)
              .clamp(0, bytes.length);
          _pending = Uint8List.fromList(bytes.sublist(offset - offset % 2));
          bytes.fillRange(0, bytes.length, 0);
        });
        unawaited(input.stderr.drain<void>());
        unawaited(input.exitCode.then((_) {
          if (identical(_input, input)) {
            _input = null;
            _capturing = false;
            _captureFailed = true;
          }
        }));
      } else {
        await _bridge.invokeMethod<void>('callStart');
        if (generation != _generation) {
          await _nativeStop('callStopInput');
          return;
        }
      }
      _capturing = true;
    } finally {
      _starting = false;
    }
  }

  Future<Uint8List> read() async {
    if (_captureFailed && !_disposed)
      throw StateError('A captura local foi interrompida.');
    if (!_capturing || _disposed) return Uint8List(0);
    if (!Platform.isLinux) {
      final generation = _generation;
      final bytes =
          await _bridge.invokeMethod<Uint8List>('callRead') ?? Uint8List(0);
      if (generation != _generation) {
        bytes.fillRange(0, bytes.length, 0);
        return Uint8List(0);
      }
      return bytes;
    }
    final length = _pending.length - _pending.length % 2;
    final data = Uint8List.fromList(_pending.sublist(0, length));
    final remainder = _pending.sublist(length);
    _pending.fillRange(0, _pending.length, 0);
    _pending = remainder;
    return data;
  }

  Future<void> play(Uint8List bytes) async {
    if (_disposed || _playing || bytes.isEmpty || !supported) return;
    _playing = true;
    final generation = _outputGeneration;
    try {
      if (Platform.isLinux) {
        if (_output == null) {
          final output = await Process.start('pacat', [
            '--playback',
            ..._pulseFormat,
            '--server=${_localPulseServer()}',
            '--latency-msec=75',
          ]);
          if (_disposed || generation != _outputGeneration) {
            output.kill();
            return;
          }
          _output = output;
          unawaited(output.stdout.drain<void>());
          unawaited(output.stderr.drain<void>());
          unawaited(output.exitCode.then((_) {
            if (identical(_output, output)) _output = null;
          }));
        }
        final output = _output;
        if (output == null) return;
        output.stdin.add(Uint8List.fromList(bytes));
        await output.stdin.flush().timeout(const Duration(milliseconds: 600));
      } else {
        await _bridge.invokeMethod<void>('callPlay', bytes);
      }
    } finally {
      _playing = false;
    }
  }

  Future<void> _nativeStop(String method) async {
    if (Platform.isAndroid || Platform.isWindows) {
      try {
        await _bridge.invokeMethod<void>(method);
      } on PlatformException {
        // O runner também libera os recursos ao encerrar.
      } on MissingPluginException {
        // Builds de desenvolvimento podem usar runners anteriores.
      }
    }
  }

  Future<void> stopInput() async {
    final active = _capturing || _starting;
    _capturing = false;
    _captureFailed = false;
    _generation++;
    _input?.kill();
    _input = null;
    _pending.fillRange(0, _pending.length, 0);
    _pending = Uint8List(0);
    if (active) await _nativeStop('callStopInput');
  }

  Future<void> stopOutput() async {
    _outputGeneration++;
    _output?.kill();
    _output = null;
    await _nativeStop('callStopOutput');
  }

  void close() {
    _disposed = true;
    unawaited(stopInput());
    unawaited(stopOutput());
  }
}
