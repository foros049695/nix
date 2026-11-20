import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'desktop_pager_audio.dart';
import 'package:flutter/services.dart';

import '../../core/media/pager_playlist.dart';

class PagerPlaylistDialog extends StatefulWidget {
  const PagerPlaylistDialog({super.key, required this.playlist});

  static const channel = MethodChannel('com.projetonix.nix/pager_audio');
  final PagerPlaylist playlist;

  @override
  State<PagerPlaylistDialog> createState() => _PagerPlaylistDialogState();
}

class _PagerPlaylistDialogState extends State<PagerPlaylistDialog>
    with WidgetsBindingObserver {
  late final _desktop = switch (defaultTargetPlatform) {
    TargetPlatform.linux || TargetPlatform.windows => DesktopPagerAudio(),
    _ => null,
  };
  List<PagerTrack> _tracks = [];
  String? _playing;
  String? _error;
  Timer? _statusTimer;
  bool _busy = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    await _run(() async {
      _tracks = await widget.playlist.load();
      _loaded = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_stopQuietly());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    unawaited(_stopQuietly());
    super.dispose();
  }

  Future<void> _stopQuietly() async {
    final desktop = _desktop;
    if (desktop != null) {
      desktop.stop();
      return;
    }
    try {
      await PagerPlaylistDialog.channel.invokeMethod<void>('stop');
    } catch (_) {
      // O MediaPlayer também é liberado pelo ciclo de vida do Android.
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on PlatformException catch (error) {
      _error = error.message ?? 'O Android não conseguiu acessar o áudio.';
    } on FormatException catch (error) {
      _error = error.message;
    } on StateError catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Não foi possível acessar a playlist ou o áudio do sistema.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final desktop = _desktop;
    PagerTrack? selected;
    if (desktop != null) {
      selected = await desktop.pick();
    } else {
      final picked = await PagerPlaylistDialog.channel
          .invokeMapMethod<Object?, Object?>('pick');
      selected = picked == null ? null : PagerTrack.fromMap(picked);
    }
    final track = selected;
    if (track == null) return;
    if (_tracks.any((value) => value.uri == track.uri)) {
      _error = 'Esta faixa já está na playlist.';
      return;
    }
    try {
      await _save([..._tracks, track]);
    } catch (_) {
      await _release(track);
      rethrow;
    }
  }

  Future<void> _save(List<PagerTrack> tracks) async {
    await widget.playlist.save(tracks);
    _tracks = tracks;
  }

  Future<void> _reorder(int from, int to) async {
    final next = [..._tracks];
    next.insert(to, next.removeAt(from));
    await _save(next);
  }

  Future<void> _release(PagerTrack track) async {
    final desktop = _desktop;
    if (desktop != null) {
      if (desktop.playing == track.uri) desktop.stop();
    } else {
      await PagerPlaylistDialog.channel
          .invokeMethod<void>('release', {'uri': track.uri});
    }
  }

  Future<void> _remove(PagerTrack track) async {
    await _save(_tracks.where((value) => value.uri != track.uri).toList());
    await _release(track);
    if (_playing == track.uri) _playing = null;
  }

  Future<void> _toggle(PagerTrack track) async {
    if (_playing == track.uri) {
      await _stopQuietly();
      _playing = null;
      return;
    }
    _playing = null;
    final desktop = _desktop;
    if (desktop != null) {
      await desktop.play(track);
    } else {
      await PagerPlaylistDialog.channel
          .invokeMethod<void>('play', {'uri': track.uri});
    }
    if (!mounted) {
      await _stopQuietly();
      return;
    }
    _playing = desktop != null ? desktop.playing : track.uri;
    _statusTimer ??= Timer.periodic(const Duration(seconds: 1), (_) async {
      final trackAtPoll = _playing;
      if (!mounted || _busy || trackAtPoll == null) return;
      try {
        final uri = desktop != null
            ? desktop.playing
            : await PagerPlaylistDialog.channel.invokeMethod<String>('playing');
        if (mounted &&
            !_busy &&
            _playing == trackAtPoll &&
            uri != trackAtPoll) {
          setState(() => _playing = null);
        }
      } catch (_) {
        if (mounted && !_busy && _playing == trackAtPoll) {
          setState(() => _playing = null);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Playlist do Pager'),
        scrollable: true,
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_desktop != null
                  ? 'Arquivos WAV locais. A reprodução começa ao tocar em Reproduzir.'
                  : 'Faixas locais. A reprodução começa ao tocar em Reproduzir.'),
              if (_busy) const LinearProgressIndicator(),
              if (_loaded && _tracks.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('Nenhuma faixa adicionada.'),
                ),
              for (var index = 0; index < _tracks.length; index++)
                _trackRow(_tracks[index], index),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
          FilledButton(
            onPressed:
                !_loaded || _busy || _tracks.length >= PagerPlaylist.maxTracks
                    ? null
                    : () => _run(_add),
            child: const Text('Adicionar faixa'),
          ),
        ],
      ),
    );
  }

  Widget _trackRow(PagerTrack track, int index) {
    return Row(
      children: [
        IconButton(
          tooltip: _playing == track.uri ? 'Parar' : 'Reproduzir',
          icon: Icon(_playing == track.uri ? Icons.stop : Icons.play_arrow),
          onPressed: _busy ? null : () => _run(() => _toggle(track)),
        ),
        Expanded(
            child:
                Text(track.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
        PopupMenuButton<int>(
          enabled: !_busy,
          tooltip: 'Opções da faixa',
          itemBuilder: (_) => [
            PopupMenuItem(
                value: index - 1,
                enabled: index > 0,
                child: const Text('Mover para cima')),
            PopupMenuItem(
              value: index + 1,
              enabled: index + 1 < _tracks.length,
              child: const Text('Mover para baixo'),
            ),
            const PopupMenuItem(value: -2, child: Text('Remover faixa')),
          ],
          onSelected: (value) => _run(
            () => value == -2 ? _remove(track) : _reorder(index, value),
          ),
        ),
      ],
    );
  }
}
