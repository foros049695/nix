import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/calls/onion_voice_link.dart';
import 'realtime_voice_audio.dart';

class OnionVoiceDialog extends StatefulWidget {
  const OnionVoiceDialog({super.key, required this.tor, required this.gate});

  final VoiceTor tor;
  final bool Function() gate;

  @override
  State<OnionVoiceDialog> createState() => _OnionVoiceDialogState();
}

class _OnionVoiceDialogState extends State<OnionVoiceDialog>
    with WidgetsBindingObserver {
  final _invite = TextEditingController();
  final _message = TextEditingController();
  final _audio = RealtimeVoiceAudio();
  final _chat = <({String text, bool incoming})>[];
  OnionVoiceLink? _room;
  StreamSubscription<({Uint8List audio, String? text})>? _events;
  Timer? _tick;
  Timer? _popupTimer;
  String? _popup;
  String? _error;
  bool _busy = false;
  bool _reading = false;
  bool _networkTick = false;
  bool _muted = true;
  bool _deafened = false;
  bool _foreground = true;

  bool _mayConnect() => mounted && widget.gate();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _pulse());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    setState(() {
      _foreground = foreground;
      if (!foreground) _muted = true;
    });
    if (!foreground) {
      _room?.setAudio(Uint8List(0));
      unawaited(_audio.stopInput());
      unawaited(_audio.stopOutput());
    }
  }

  Future<void> _open({required bool join}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final room = join
          ? OnionVoiceLink.join(_invite.text, widget.tor, _mayConnect)
          : await OnionVoiceLink.host(widget.tor, _mayConnect);
      if (!mounted) {
        room.close();
        return;
      }
      _events = room.updates.listen(_receive);
      _invite.clear();
      setState(() => _room = room);
    } catch (_) {
      _notifyError(
          'Não foi possível abrir a chamada. Confira o convite e o Tor.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _receive(({Uint8List audio, String? text}) event) {
    if (!mounted) return;
    final text = event.text;
    if (text != null) {
      _popupTimer?.cancel();
      setState(() {
        _keep(text, incoming: true);
        _popup = text;
      });
      _popupTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _popup = null);
      });
    }
    if (_foreground && !_deafened && event.audio.isNotEmpty) {
      unawaited(_audio.play(event.audio).catchError((Object _) {
        _notifyError('O reprodutor de áudio da chamada ficou indisponível.');
      }).whenComplete(() => event.audio.fillRange(0, event.audio.length, 0)));
    } else {
      event.audio.fillRange(0, event.audio.length, 0);
    }
  }

  void _pulse() {
    final room = _room;
    if (room == null || !mounted) return;
    if (!room.available) {
      room.close();
      _audio.close();
      _notifyError('A chamada foi encerrada.');
      _tick?.cancel();
      return;
    }
    if (!room.peerConnected && !_muted) {
      _muted = true;
      room.setAudio(Uint8List(0));
      unawaited(_audio.stopInput());
    }
    if (_foreground && !_muted && !_reading) {
      _reading = true;
      unawaited(_audio.read().then((bytes) {
        if (mounted && _foreground && !_muted && room.peerConnected)
          room.setAudio(bytes);
        bytes.fillRange(0, bytes.length, 0);
      }).catchError((Object error) {
        _muted = true;
        unawaited(_audio.stopInput());
        _notifyError('O microfone da chamada ficou indisponível.');
      }).whenComplete(() => _reading = false));
    }
    if (!_networkTick) {
      _networkTick = true;
      unawaited(room.tick().then((_) {
        if (mounted && room.peerConnected) setState(() => _error = null);
      }).catchError((Object _) {
        if (_foreground && !room.peerConnected) {
          _notifyError('Aguardando conexão pelo Tor.');
        }
      }).whenComplete(() => _networkTick = false));
    }
    setState(() {});
  }

  Future<void> _toggleMic() async {
    final room = _room;
    if (room == null || !room.peerConnected || !_foreground || _busy) return;
    if (!_muted) {
      setState(() => _muted = true);
      room.setAudio(Uint8List(0));
      await _audio.stopInput();
      return;
    }
    setState(() => _busy = true);
    try {
      await _audio.start();
      if (mounted && _foreground && room.peerConnected) {
        setState(() => _muted = false);
      }
    } catch (_) {
      await _audio.stopInput();
      _notifyError('Não foi possível iniciar o microfone.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _keep(String text, {required bool incoming}) {
    if (_chat.length == 40) _chat.removeAt(0);
    _chat.add((text: text, incoming: incoming));
  }

  void _send() {
    final room = _room;
    final text = _message.text.trim();
    if (room == null || text.isEmpty || !room.peerConnected) return;
    try {
      room.sendText(text);
      _message.clear();
      setState(() => _keep(text, incoming: false));
    } on StateError catch (error) {
      _notifyError(error.message);
    }
  }

  void _notifyError(String text) {
    if (mounted && _error != text) setState(() => _error = text);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _popupTimer?.cancel();
    unawaited(_events?.cancel() ?? Future.value());
    _room?.close();
    _audio.close();
    _invite.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final invite = room?.invite;
    final connected = room?.peerConnected == true;
    return AlertDialog(
      title: const Text('Chamada privada'),
      scrollable: true,
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (room == null) ...[
              const Text(
                  'Um convite conecta dois dispositivos via Tor. Compartilhe pelo canal privado de sua escolha.'),
              TextField(
                controller: _invite,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 600,
                decoration:
                    const InputDecoration(labelText: 'Convite de chamada'),
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : () => _open(join: false),
                    child: const Text('Criar convite'),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : () => _open(join: true),
                    child: const Text('Usar convite'),
                  ),
                ],
              ),
            ] else ...[
              Text(connected
                  ? 'Dispositivo conectado'
                  : 'Aguardando dispositivo'),
              if (invite != null)
                OutlinedButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: invite)),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copiar convite privado'),
                ),
              Wrap(
                children: [
                  IconButton(
                    tooltip:
                        _muted ? 'Ativar microfone' : 'Silenciar microfone',
                    onPressed: connected && _audio.supported && !_busy
                        ? _toggleMic
                        : null,
                    icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                  ),
                  IconButton(
                    tooltip: _deafened
                        ? 'Ativar saída de áudio'
                        : 'Silenciar saída de áudio',
                    onPressed: !_audio.supported
                        ? null
                        : () {
                            setState(() => _deafened = !_deafened);
                            if (_deafened) unawaited(_audio.stopOutput());
                          },
                    icon: Icon(_deafened ? Icons.headset_off : Icons.headset),
                  ),
                ],
              ),
              if (_popup case final text?)
                Semantics(
                  liveRegion: true,
                  child: ListTile(
                    key: const Key('onion_call_chat_popup'),
                    leading: const Icon(Icons.chat_outlined),
                    title: Text(text,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _popup = null),
                    ),
                  ),
                ),
              for (final row in _chat.reversed.take(8).toList().reversed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                      '${row.incoming ? 'Participante' : 'Você'} · ${row.text}'),
                ),
              TextField(
                controller: _message,
                enabled: connected,
                maxLength: 300,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  labelText: 'Mensagem da chamada',
                  suffixIcon: IconButton(
                    tooltip: 'Enviar mensagem',
                    icon: const Icon(Icons.send),
                    onPressed: connected ? _send : null,
                  ),
                ),
              ),
            ],
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?) Text(error),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Sair')),
      ],
    );
  }
}
