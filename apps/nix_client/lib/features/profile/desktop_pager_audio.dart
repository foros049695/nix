import 'dart:async';
import 'dart:io';

import '../../core/media/pager_playlist.dart';
import '../../core/security/file_picker_adapter.dart';

class DesktopPagerAudio {
  Process? _process;
  String? playing;
  int _generation = 0;

  static const _windowsScript = r'''
$ErrorActionPreference = 'Stop'
$audio = New-Object System.Media.SoundPlayer
try {
  $audio.SoundLocation = $env:NIX_PAGER_WAV_PATH
  $audio.Load()
  [Console]::WriteLine('READY')
  $audio.PlaySync()
} finally {
  $audio.Dispose()
}
''';

  Future<PagerTrack?> pick() async {
    final choices =
        await const CrossPlatformFilePickerAdapter().pickAttachments(
      allowedExtensions: const ['wav'],
      allowMultiple: false,
    );
    if (choices.isEmpty) return null;
    final file = File(choices.single).absolute;
    final track = PagerTrack(
      uri: file.uri.toString(),
      name: file.uri.pathSegments.last,
    );
    await _localWav(track);
    return track;
  }

  Future<File> _localWav(PagerTrack track) async {
    final uri = Uri.parse(PagerTrack.fromMap(track.toMap()).uri);
    if (uri.scheme != 'file' ||
        (Platform.isWindows && !RegExp(r'^/[a-zA-Z]:/').hasMatch(uri.path)))
      throw const FormatException('Selecione um WAV local.');
    final file = File.fromUri(uri);
    final resolved = File(await file.resolveSymbolicLinks());
    if (resolved.uri.hasAuthority && resolved.uri.authority.isNotEmpty) {
      throw const FormatException('Selecione um WAV local.');
    }
    final stat = await resolved.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size < 44 ||
        stat.size > 64 * 1024 * 1024) {
      throw const FormatException('O WAV deve ter entre 44 bytes e 64 MiB.');
    }
    final header =
        await resolved.openRead(0, 12).expand((bytes) => bytes).toList();
    if (String.fromCharCodes(header.take(4)) != 'RIFF' ||
        String.fromCharCodes(header.skip(8)) != 'WAVE') {
      throw const FormatException('O arquivo selecionado precisa ser um WAV.');
    }
    return resolved;
  }

  Future<void> play(PagerTrack track) async {
    stop();
    final generation = _generation;
    final file = await _localWav(track);
    final windows = Platform.isWindows;
    final runtimeDirectory = Platform.environment['XDG_RUNTIME_DIR'];
    if (!windows &&
        (runtimeDirectory == null ||
            !runtimeDirectory.startsWith('/') ||
            RegExp(r'\s').hasMatch(runtimeDirectory))) {
      throw StateError('O servidor de áudio local do Linux está indisponível.');
    }
    final process = await Process.start(
      windows ? 'powershell.exe' : 'paplay',
      windows
          ? ['-NoProfile', '-NonInteractive', '-Command', _windowsScript]
          : ['--', file.path],
      environment: windows
          ? {'NIX_PAGER_WAV_PATH': file.path}
          : {'PULSE_SERVER': 'unix:$runtimeDirectory/pulse/native'},
    );
    if (generation != _generation) {
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      process.kill();
      return;
    }
    final ready = Completer<void>();
    final earlyError =
        StateError('O sistema não conseguiu reproduzir este WAV.');
    _process = process;
    unawaited(process.stderr.drain<void>());
    if (windows) {
      var output = '';
      process.stdout.listen((bytes) {
        if (ready.isCompleted) return;
        output += String.fromCharCodes(bytes);
        if (output.split(RegExp(r'\r?\n')).contains('READY')) ready.complete();
      });
    } else {
      unawaited(process.stdout.drain<void>());
    }
    final finished = process.exitCode.then((code) {
      if (identical(_process, process)) {
        _process = null;
        playing = null;
      }
      if (!ready.isCompleted) {
        if (code == 0 && !windows) {
          ready.complete();
        } else {
          ready.completeError(earlyError);
        }
      }
    });
    try {
      if (windows) {
        await ready.future.timeout(const Duration(seconds: 5));
      } else {
        await Future.any<void>([
          ready.future,
          Future<void>.delayed(const Duration(milliseconds: 150)),
        ]);
      }
      if (_process == process) playing = track.uri;
    } catch (_) {
      if (_process == process) stop();
      throw earlyError;
    } finally {
      unawaited(finished);
    }
  }

  void stop() {
    _generation++;
    _process?.kill();
    _process = null;
    playing = null;
  }
}
