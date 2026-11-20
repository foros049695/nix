import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MicrophoneTestCard extends StatefulWidget {
  const MicrophoneTestCard({super.key});

  @override
  State<MicrophoneTestCard> createState() => _MicrophoneTestCardState();
}

class _MicrophoneTestCardState extends State<MicrophoneTestCard>
    with WidgetsBindingObserver {
  static const _bridge = MethodChannel('com.projetonix.nix/audio_diagnostic');
  Process? _capture;
  Timer? _timer;
  int _generation = 0;
  bool _busy = false;
  bool _capturing = false;
  double? _level;
  double? _peak;
  int? _lowByte;
  String? _error;
  String? _route;
  DateTime? _lastSample;

  bool get _usesNativeBridge => Platform.isAndroid || Platform.isWindows;
  bool get _supported => _usesNativeBridge || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadRoutes());
  }

  Future<void> _loadRoutes() async {
    String? route;
    try {
      if (_usesNativeBridge) {
        route = await _bridge.invokeMethod<String>('devices');
      } else if (Platform.isLinux) {
        final reports = await Future.wait([
          Process.run('pactl', ['get-default-source']),
          Process.run('pactl', ['get-default-sink']),
        ]).timeout(const Duration(seconds: 3));
        final input = reports[0].exitCode == 0
            ? (reports[0].stdout as String).trim()
            : 'indisponível';
        final output = reports[1].exitCode == 0
            ? (reports[1].stdout as String).trim()
            : 'indisponível';
        route = 'Entrada padrão: $input\nSaída padrão: $output';
      }
    } catch (_) {
      // A consulta de rotas não impede uma tentativa explícita de teste.
    }
    if (mounted) setState(() => _route = route);
  }

  void _releaseCapture() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _capture?.kill();
    _capture = null;
    _peak = null;
    _level = null;
    _lowByte = null;
    _busy = false;
    _capturing = false;
    if (_usesNativeBridge) unawaited(_stopNativeCapture());
  }

  Future<void> _stopNativeCapture() async {
    try {
      await _bridge.invokeMethod<void>('stop');
    } on PlatformException {
      // O runner também encerra a captura ao fechar.
    } on MissingPluginException {
      // O bridge pode estar indisponível em builds de desenvolvimento.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) &&
        (_capturing || _busy)) {
      setState(_releaseCapture);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_capturing || _busy) _releaseCapture();
    super.dispose();
  }

  void _failed(int generation, String message) {
    if (!mounted || generation != _generation) return;
    setState(() {
      _releaseCapture();
      _error = message;
    });
  }

  Future<void> _start() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_usesNativeBridge) {
        await _bridge.invokeMethod<void>('start');
      } else {
        final process = await Process.start('parec', [
          '--raw',
          '--format=s16le',
          '--rate=16000',
          '--channels=1',
        ]);
        if (!mounted || generation != _generation) {
          process.kill();
          return;
        }
        _capture = process;
        process.stdout.listen((bytes) {
          if (generation != _generation) return;
          for (final byte in bytes) {
            final low = _lowByte;
            if (low == null) {
              _lowByte = byte;
            } else {
              final word = (byte << 8) | low;
              final signed = word >= 32768 ? word - 65536 : word;
              _peak = math.max(_peak ?? 0, signed.abs() / 32768);
              _lowByte = null;
            }
          }
        });
        unawaited(process.stderr.drain<void>());
        unawaited(process.exitCode.then((_) => _failed(
            generation, 'A captura Linux foi encerrada pelo sistema.')));
      }
      if (!mounted || generation != _generation) return;
      _lastSample = DateTime.now();
      setState(() {
        _busy = false;
        _capturing = true;
      });
      _timer = Timer.periodic(const Duration(milliseconds: 160), (_) {
        if (_usesNativeBridge) {
          unawaited(_readNativeLevel(generation));
        } else {
          _updateLevel(generation, _peak);
          _peak = null;
        }
      });
    } on PlatformException catch (error) {
      _failed(generation, error.message ?? 'O sistema recusou a captura.');
    } catch (_) {
      _failed(
          generation,
          Platform.isLinux
              ? 'Não foi possível iniciar parec. Verifique o microfone e o servidor de áudio PulseAudio ou PipeWire.'
              : 'Não foi possível iniciar a captura do microfone.');
    }
  }

  Future<void> _readNativeLevel(int generation) async {
    try {
      final level = await _bridge.invokeMethod<double>('level');
      _updateLevel(generation, level);
    } catch (_) {
      _failed(generation, 'O áudio do microfone ficou indisponível.');
    }
  }

  void _updateLevel(int generation, double? level) {
    if (!mounted || generation != _generation) return;
    if (level != null) {
      _lastSample = DateTime.now();
      setState(() => _level = level.clamp(0, 1).toDouble());
    } else if (DateTime.now().difference(_lastSample!) >
        const Duration(seconds: 4)) {
      _failed(
          generation, 'O dispositivo deixou de entregar amostras de áudio.');
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_route != null) ...[
                Text(_route!),
                const SizedBox(height: 12),
              ],
              const Text('Teste local do microfone'),
              const SizedBox(height: 8),
              Text(_error ??
                  (!_supported
                      ? 'O diagnóstico de áudio ainda não está disponível nesta plataforma.'
                      : _busy
                          ? 'Aguardando permissão ou dispositivo de áudio.'
                          : _capturing
                              ? 'Fale no microfone. O teste mede o áudio em memória.'
                              : 'O teste usa o microfone padrão e descarta as amostras.')),
              if (_level != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _level,
                  semanticsLabel: 'Nível de entrada do microfone',
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: !_supported || _busy
                    ? null
                    : _capturing
                        ? () => setState(_releaseCapture)
                        : _start,
                icon:
                    Icon(_capturing ? Icons.stop_rounded : Icons.mic_outlined),
                label: Text(_capturing ? 'Parar teste' : 'Iniciar teste'),
              ),
            ],
          ),
        ),
      );
}
