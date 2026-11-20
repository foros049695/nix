import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/workspace_banner.dart';
import '../../core/security/file_picker_adapter.dart';
import '../../core/security/local_image_helper.dart';

class WorkspaceImage extends StatelessWidget {
  const WorkspaceImage(
      {super.key, required this.path, required this.fallback, this.size = 30});

  final String? path;
  final Widget fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = path;
    if (image == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .23),
      child: Image.file(File(image),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: 144,
          errorBuilder: (_, __, ___) => fallback),
    );
  }
}

class WorkspaceImageField extends StatefulWidget {
  const WorkspaceImageField(
      {super.key, required this.path, required this.onChanged});

  final String? path;
  final ValueChanged<String?> onChanged;

  @override
  State<WorkspaceImageField> createState() => _WorkspaceImageFieldState();
}

class _WorkspaceImageFieldState extends State<WorkspaceImageField> {
  bool _busy = false;
  String? _error;

  Future<void> _choose() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String? selected;
      try {
        selected = await LocalImageHelper.pickImageNativeDesktop();
      } on FilePickerUnavailableException {
        if (!mounted) return;
        selected =
            (await CrossPlatformFilePickerAdapter.showPortableFileChooserDialog(
                    context,
                    title: 'Escolher imagem ou GIF',
                    allowedExtensions: LocalImageHelper.supportedExtensions))
                .firstOrNull;
      }
      if (!mounted || selected == null) return;
      final file = File(selected);
      if (!await file.exists() || await file.length() > 20 * 1024 * 1024) {
        if (mounted)
          setState(() => _error = 'Imagem ausente ou maior que 20 MB.');
        return;
      }
      final saved = await LocalImageHelper.sanitizeAndStoreImage(selected);
      if (!mounted) return;
      if (saved == null) {
        setState(() => _error = 'Não foi possível validar a imagem.');
      } else {
        widget.onChanged(saved);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível abrir a imagem.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            spacing: 8,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                  onPressed: _busy ? null : _choose,
                  icon: WorkspaceImage(
                      path: widget.path,
                      size: 26,
                      fallback: const Icon(Icons.image_outlined, size: 19)),
                  label: const Text('Escolher imagem ou GIF')),
              if (widget.path != null)
                IconButton(
                    tooltip: 'Remover imagem',
                    onPressed: _busy ? null : () => widget.onChanged(null),
                    icon: const Icon(Icons.image_not_supported_outlined)),
            ]),
        if (_error != null)
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]);
}

class WorkspaceBannerView extends StatelessWidget {
  const WorkspaceBannerView({super.key, required this.banner, this.height = 132});
  final WorkspaceBanner? banner;
  final double height;

  @override
  Widget build(BuildContext context) {
    final value = banner;
    if (value == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(
        File(value.path), height: height, width: double.infinity,
        alignment: Alignment(value.x, value.y), fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}

class WorkspaceBannerField extends StatelessWidget {
  const WorkspaceBannerField({super.key, required this.banner, required this.onChanged});
  final WorkspaceBanner? banner;
  final ValueChanged<WorkspaceBanner?> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = banner;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Banner'),
      WorkspaceBannerView(banner: value, height: 90),
      WorkspaceImageField(path: value?.path, onChanged: (path) =>
        onChanged(path == null ? null : WorkspaceBanner(path))),
      if (value != null) ...[
        const Text('Posição horizontal do recorte'),
        Slider(value: value.x, min: -1, max: 1, onChanged: (x) =>
          onChanged(WorkspaceBanner(value.path, x: x, y: value.y))),
        const Text('Posição vertical do recorte'),
        Slider(value: value.y, min: -1, max: 1, onChanged: (y) =>
          onChanged(WorkspaceBanner(value.path, x: value.x, y: y))),
      ],
    ]);
  }
}
