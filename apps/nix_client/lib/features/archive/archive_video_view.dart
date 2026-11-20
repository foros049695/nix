import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/archive/archive_video.dart';
import '../../core/security/file_picker_adapter.dart';
import '../../core/security/local_image_helper.dart';

Future<ArchiveVideo?> pickArchiveVideo(BuildContext context) async {
  const extensions = ['mp4'];
  List<String> selected;
  try {
    selected = await LocalImageHelper.filePickerAdapter.pickAttachments(
      allowedExtensions: extensions,
      allowMultiple: false,
    );
  } on FilePickerUnavailableException {
    if (!context.mounted) return null;
    selected =
        await CrossPlatformFilePickerAdapter.showPortableFileChooserDialog(
      context,
      allowedExtensions: extensions,
    );
  }
  final path = selected.firstOrNull;
  if (path == null) return null;
  final file = File(path);
  final stat = await file.stat();
  if (stat.type != FileSystemEntityType.file ||
      stat.size > ArchiveVideo.maxBytes ||
      !path.toLowerCase().endsWith('.mp4')) {
    throw const FormatException('Escolha um MP4 de até 2 MiB.');
  }
  final input = await file.open();
  try {
    return ArchiveVideo.fromMp4(await input.read(ArchiveVideo.maxBytes + 1));
  } finally {
    await input.close();
  }
}

class ArchiveVideoView extends StatelessWidget {
  const ArchiveVideoView({super.key, required this.video});

  final ArchiveVideo video;

  Future<void> _play(BuildContext context) async {
    try {
      if (Platform.isAndroid) {
        await const MethodChannel('com.projetonix.nix/platform')
            .invokeMethod<void>('playArchiveVideo', video.bytes);
        return;
      }
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Abrir no reprodutor do sistema?'),
          content: const Text(
              'O Nix entregará uma cópia temporária do vídeo ao reprodutor.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Abrir')),
          ],
        ),
      );
      if (approved != true) return;
      final folder =
          await Directory.systemTemp.createTemp('nix-archive-video-');
      final file = File('${folder.path}${Platform.pathSeparator}archive.mp4');
      try {
        await file.writeAsBytes(video.bytes, flush: true);
        final launched = Platform.isWindows
            ? await Process.run('powershell.exe', [
                '-NoProfile',
                '-NonInteractive',
                '-Command',
                r'Invoke-Item -LiteralPath $env:NIX_ARCHIVE_PLAYBACK_FILE',
              ], environment: {
                'NIX_ARCHIVE_PLAYBACK_FILE': file.path
              })
            : await Process.run(
                Platform.isMacOS ? 'open' : 'xdg-open', [file.path]);
        if (launched.exitCode != 0)
          throw StateError('Reprodutor indisponível.');
      } catch (_) {
        await folder.delete(recursive: true);
        rethrow;
      }
      // A associação de arquivos pode retornar antes de o reprodutor ler o vídeo.
      Future<void>.delayed(const Duration(minutes: 10), () async {
        try {
          await folder.delete(recursive: true);
        } on FileSystemException {
          // O sistema pode manter a cópia aberta enquanto houver reprodução.
        }
      });
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Não foi possível abrir o vídeo local.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        key: const Key('archive_verified_video'),
        onPressed: () => _play(context),
        icon: const Icon(Icons.play_circle_outline),
        label: const Text('Reproduzir vídeo MP4'),
      );
}
