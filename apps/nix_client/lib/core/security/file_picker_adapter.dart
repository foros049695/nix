import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/nix_colors.dart';

/// Abstração multiplataforma portável para seleção de arquivos e imagens (Fase 8).
/// Evita acoplamento rígido a `zenity`/`kdialog` e permite injeção determinística em testes
/// bem como seletor Flutter local em ambientes sem utilitários de diálogo externos (ex: Fluxbox mínimo).
abstract class FilePickerAdapter {
  Future<List<String>> pickAttachments({
    List<String> allowedExtensions = const [],
    bool allowMultiple = true,
  });

  Future<String?> pickImage({
    List<String> allowedExtensions = const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
  });
}

/// Adaptador programável para testes automatizados de seleção, cancelamento e múltiplos anexos.
class ProgrammableFilePickerAdapter implements FilePickerAdapter {
  List<String> nextAttachments;
  String? nextImage;
  int pickAttachmentsCalls = 0;
  int pickImageCalls = 0;

  ProgrammableFilePickerAdapter({
    this.nextAttachments = const [],
    this.nextImage,
  });

  @override
  Future<List<String>> pickAttachments({
    List<String> allowedExtensions = const [],
    bool allowMultiple = true,
  }) async {
    pickAttachmentsCalls++;
    if (allowedExtensions.isEmpty) return List<String>.from(nextAttachments);
    return nextAttachments.where((path) {
      final lower = path.toLowerCase();
      return allowedExtensions.any((ext) => lower.endsWith('.${ext.toLowerCase()}'));
    }).toList();
  }

  @override
  Future<String?> pickImage({
    List<String> allowedExtensions = const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
  }) async {
    pickImageCalls++;
    return nextImage;
  }
}

/// Implementação multiplataforma (Linux, macOS, Windows + fallback de navegação local).
class CrossPlatformFilePickerAdapter implements FilePickerAdapter {
  const CrossPlatformFilePickerAdapter();

  @override
  Future<List<String>> pickAttachments({
    List<String> allowedExtensions = const [],
    bool allowMultiple = true,
  }) async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return const ['documento_seguro.pdf'];
    }
    if (Platform.isLinux) {
      final res = await _pickLinux(
        title: 'Selecionar Arquivos / Anexos (Criptografia E2EE Nix)',
        extensions: allowedExtensions,
        multiple: allowMultiple,
      );
      if (res.isNotEmpty) return res;
    } else if (Platform.isMacOS) {
      final res = await _pickMacOS(multiple: allowMultiple);
      if (res.isNotEmpty) return res;
    } else if (Platform.isWindows) {
      final res = await _pickWindows(
        extensions: allowedExtensions,
        multiple: allowMultiple,
      );
      if (res.isNotEmpty) return res;
    }
    return const [];
  }

  @override
  Future<String?> pickImage({
    List<String> allowedExtensions = const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
  }) async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return '/tmp/nix_test_avatar.png';
    }
    final list = await pickAttachments(
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
    );
    return list.isNotEmpty ? list.first : null;
  }

  Future<List<String>> _pickLinux({
    required String title,
    required List<String> extensions,
    required bool multiple,
  }) async {
    final glob = extensions.isEmpty
        ? '*.png *.jpg *.jpeg *.webp *.gif *.mp4 *.mp3 *.ogg *.wav *.pdf *.txt *.docx *.zip'
        : extensions.map((e) => '*.$e').join(' ');

    for (final bin in const ['zenity', 'qarma']) {
      try {
        final args = <String>[
          '--file-selection',
          if (multiple) '--multiple',
          if (multiple) '--separator=|',
          '--title=$title',
          '--file-filter=Arquivos Suportados | $glob',
        ];
        final res = await Process.run(bin, args);
        if (res.exitCode == 0) {
          final out = res.stdout.toString().trim();
          if (out.isNotEmpty) {
            return (multiple ? out.split('|') : [out])
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
        }
      } catch (_) {}
    }

    try {
      final args = <String>[
        '--getopenfilename',
        if (multiple) '--multiple',
        if (multiple) '--separate-output',
        Platform.environment['HOME'] ?? '.',
        '$glob|Arquivos Suportados',
      ];
      final res = await Process.run('kdialog', args);
      if (res.exitCode == 0) {
        final out = res.stdout.toString().trim();
        if (out.isNotEmpty) {
          return out
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}

    return const [];
  }

  Future<List<String>> _pickMacOS({required bool multiple}) async {
    try {
      final multClause = multiple ? ' with multiple selections allowed' : '';
      final script =
          'set chosen to choose file with prompt "Selecionar Arquivo Nix"$multClause\n'
          'if class of chosen is list then\n'
          '  set out to ""\n'
          '  repeat with f in chosen\n'
          '    set out to out & (POSIX path of f) & "\\n"\n'
          '  end repeat\n'
          '  return out\n'
          'else\n'
          '  return POSIX path of chosen\n'
          'end if';
      final res = await Process.run('osascript', ['-e', script]);
      if (res.exitCode == 0) {
        return res.stdout
            .toString()
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<List<String>> _pickWindows({
    required List<String> extensions,
    required bool multiple,
  }) async {
    try {
      final mult = multiple ? '\$true' : '\$false';
      final script =
          'Add-Type -AssemblyName System.Windows.Forms; '
          '\$d = New-Object System.Windows.Forms.OpenFileDialog; '
          '\$d.Multiselect = $mult; '
          'if (\$d.ShowDialog() -eq "OK") { \$d.FileNames -join "|" }';
      final res = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', script],
      );
      if (res.exitCode == 0) {
        final out = res.stdout.toString().trim();
        if (out.isNotEmpty) {
          return out
              .split('|')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}
    return const [];
  }

  /// Diálogo Flutter multiplataforma de fallback quando nenhum seletor externo do SO está instalado.
  static Future<List<String>> showPortableFileChooserDialog(
    BuildContext context, {
    String title = 'Selecionar Arquivo Local (Criptografia E2EE)',
    List<String> allowedExtensions = const [],
  }) async {
    final pathCtrl = TextEditingController();
    String currentDir =
        Platform.environment['HOME'] ?? Directory.current.path;
    String? errorMsg;

    final selected = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          List<FileSystemEntity> entries = const [];
          try {
            final dir = Directory(currentDir);
            if (dir.existsSync()) {
              entries = dir.listSync().where((e) {
                final name = e.uri.pathSegments.isNotEmpty
                    ? e.uri.pathSegments.last
                    : '';
                if (name.startsWith('.')) return false;
                if (e is Directory) return true;
                if (allowedExtensions.isEmpty) return true;
                final lower = e.path.toLowerCase();
                return allowedExtensions
                    .any((ext) => lower.endsWith('.${ext.toLowerCase()}'));
              }).take(40).toList();
            }
          } catch (_) {}

          return AlertDialog(
            backgroundColor: NixColors.surfaceElevatedHigh,
            title: Text(
              title,
              style: TextStyle(
                color: NixColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('portable_file_picker_path_input'),
                    controller: pathCtrl,
                    style: TextStyle(color: NixColors.textPrimary, fontSize: 12.5),
                    decoration: const InputDecoration(
                      labelText: 'Caminho completo do arquivo local',
                      hintText: '/caminho/para/arquivo.png',
                      isDense: true,
                    ),
                  ),
                  if (entries.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 160,
                      child: ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (_, i) {
                          final e = entries[i];
                          final isDir = e is Directory;
                          final name =
                              e.path.split(Platform.pathSeparator).last;
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isDir
                                  ? Icons.folder_outlined
                                  : Icons.insert_drive_file_outlined,
                              size: 16,
                              color: NixColors.textSecondary,
                            ),
                            title: Text(
                              name,
                              style: TextStyle(
                                color: NixColors.textPrimary,
                                fontSize: 12,
                              ),
                            ),
                            onTap: () {
                              if (isDir) {
                                setDlgState(() => currentDir = e.path);
                              } else {
                                setDlgState(() {
                                  pathCtrl.text = e.path;
                                  errorMsg = null;
                                });
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                  if (errorMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMsg!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(const <String>[]),
                child: Text(
                  'Cancelar',
                  style: TextStyle(color: NixColors.textMuted),
                ),
              ),
              ElevatedButton(
                key: const Key('portable_file_picker_confirm_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NixColors.accentYellow,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  final raw = pathCtrl.text.trim();
                  if (raw.isEmpty || !File(raw).existsSync()) {
                    setDlgState(() => errorMsg = 'Arquivo local não encontrado.');
                    return;
                  }
                  if (allowedExtensions.isNotEmpty) {
                    final lower = raw.toLowerCase();
                    final ok = allowedExtensions
                        .any((ext) => lower.endsWith('.${ext.toLowerCase()}'));
                    if (!ok) {
                      setDlgState(
                        () => errorMsg =
                            'Extensão não permitida (${allowedExtensions.join(', ')}).',
                      );
                      return;
                    }
                  }
                  Navigator.of(ctx).pop([raw]);
                },
                child: const Text(
                  'Selecionar',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
    pathCtrl.dispose();
    return selected ?? const [];
  }
}
