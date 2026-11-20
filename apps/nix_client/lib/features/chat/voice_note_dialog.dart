import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/media/voice_note.dart';

class VoiceNoteDialog extends StatefulWidget {
  const VoiceNoteDialog.record({super.key, required this.onSend}) : load = null;
  const VoiceNoteDialog.listen({super.key, required this.load}) : onSend = null;

  static const channel = MethodChannel('com.projetonix.nix/voice_notes');
  final Future<void> Function(VoiceNote)? onSend;
  final Future<VoiceNote?> Function()? load;

  @override
  State<VoiceNoteDialog> createState() => _VoiceNoteDialogState();
}

class _VoiceNoteDialogState extends State<VoiceNoteDialog>
    with WidgetsBindingObserver {
  VoiceNote? _note;
  String _status = 'idle';
  String? _error;
  int _samples = 0;
  int _peak = 0;
  bool _busy = false;
  bool _polling = false;
  bool _playing = false;
  bool _backgrounded = false;
  Timer? _timer;

  bool get _recording => _status == 'recording';
  bool get _paused => _status == 'paused';
  bool get _ready => _status == 'full';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(milliseconds: 125), (_) => _poll());
    final load = widget.load;
    if (load != null) {
      unawaited(_run(() async {
        final note = await load();
        if (!mounted || _backgrounded) {
          if (note != null) note.pcm.fillRange(0, note.pcm.length, 0);
          return;
        }
        if (note == null)
          throw StateError('A nota de voz não está disponível.');
        _note = note;
      }));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _backgrounded = false;
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _backgrounded = true;
      unawaited(_cancel());
      if (_recording || _paused || _ready || _playing) {
        setState(() {
          _status = 'idle';
          _samples = 0;
          _peak = 0;
          _playing = false;
          _error = 'O áudio foi interrompido em segundo plano.';
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    final note = _note;
    if (note != null) note.pcm.fillRange(0, note.pcm.length, 0);
    unawaited(_cancel());
    super.dispose();
  }

  static Future<void> _cancel() async {
    try {
      await VoiceNoteDialog.channel.invokeMethod<void>('cancel');
    } catch (_) {
      // A atividade Android também libera o microfone ao sair de cena.
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on PlatformException catch (error) {
      _error = error.message ?? 'O áudio está indisponível.';
    } on StateError catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Não foi possível concluir a operação.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _poll() async {
    if (_busy || _polling || !mounted || _backgrounded) return;
    _polling = true;
    try {
      if (_recording) {
        final snapshot = await VoiceNoteDialog.channel
            .invokeMapMethod<String, Object?>('status');
        if (snapshot == null ||
            !mounted ||
            _busy ||
            !_recording ||
            _backgrounded) return;
        setState(() {
          _status = snapshot['state'] as String;
          _samples = snapshot['samples'] as int;
          _peak = snapshot['peak'] as int;
          if (_status == 'failed')
            _error = 'A captura do microfone foi interrompida.';
        });
      } else if (_playing) {
        final playing =
            await VoiceNoteDialog.channel.invokeMethod<bool>('playing');
        if (mounted && !_busy && playing != true)
          setState(() => _playing = false);
      }
    } catch (_) {
      if (mounted && !_busy)
        setState(() => _error = 'O áudio foi interrompido.');
    } finally {
      _polling = false;
    }
  }

  Future<void> _changeRecording(String method, String state) => _run(() async {
        await VoiceNoteDialog.channel.invokeMethod<void>(method);
        if (!_backgrounded && mounted) _status = state;
      });

  Future<void> _finish() => _run(() async {
        final pcm =
            await VoiceNoteDialog.channel.invokeMethod<Uint8List>('finish');
        if (pcm == null) throw StateError('A gravação está vazia.');
        if (!mounted || _backgrounded) {
          pcm.fillRange(0, pcm.length, 0);
          return;
        }
        _note = VoiceNote.fromPcm(pcm);
        _status = 'idle';
      });

  Future<void> _play(VoiceNote note) => _run(() async {
        if (_playing) {
          await VoiceNoteDialog.channel.invokeMethod<void>('stopPlayback');
          _playing = false;
        } else {
          await VoiceNoteDialog.channel.invokeMethod<void>('play', note.pcm);
          _playing = !_backgrounded;
        }
      });

  @override
  Widget build(BuildContext context) {
    final note = _note;
    final onSend = widget.onSend;
    final elapsedMs =
        note?.durationMs ?? _samples * 1000 ~/ VoiceNote.sampleRate;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: const Text('Mensagem de voz'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_busy) const LinearProgressIndicator(),
            if (note != null || _recording || _paused || _ready)
              Text('${(elapsedMs / 1000).toStringAsFixed(1)} s'),
            if (_recording)
              Semantics(
                label: 'Nível do microfone',
                child: LinearProgressIndicator(
                    value: (_peak / 32768).clamp(0.0, 1.0).toDouble()),
              ),
            if (_paused) const Text('Gravação pausada'),
            if (_ready) const Text('Limite de 12 segundos atingido.'),
            if (note == null && onSend != null)
              Wrap(
                spacing: 8,
                children: [
                  if (!_recording && !_paused && !_ready)
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _changeRecording('start', 'recording'),
                      icon: const Icon(Icons.mic),
                      label: const Text('Gravar'),
                    ),
                  if (_recording || _paused)
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _changeRecording(
                                _paused ? 'resume' : 'pause',
                                _paused ? 'recording' : 'paused',
                              ),
                      icon: Icon(_paused ? Icons.mic : Icons.pause),
                      label: Text(_paused ? 'Retomar' : 'Pausar'),
                    ),
                  if (_recording || _paused || _ready)
                    TextButton(
                      onPressed: _busy || _samples == 0 ? null : _finish,
                      child: const Text('Pré-visualizar'),
                    ),
                ],
              ),
            if (note != null)
              TextButton.icon(
                onPressed: _busy ? null : () => _play(note),
                icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
                label: Text(_playing ? 'Parar' : 'Reproduzir'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(onSend == null ? 'Fechar' : 'Cancelar'),
          ),
          if (note != null && onSend != null)
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        await onSend(note);
                        if (context.mounted) Navigator.pop(context);
                      }),
              child: const Text('Enviar voz'),
            ),
        ],
      ),
    );
  }
}
