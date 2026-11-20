import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/archive/archive_image.dart';
import '../../core/security/file_picker_adapter.dart';
import '../../core/security/local_image_helper.dart';

class ArchiveImagePicker {
  static const extensions = ['png', 'jpg', 'jpeg', 'webp'];
  static const _maxSourceBytes = 8 * 1024 * 1024;
  static const _maxSourcePixels = 24000000;

  static Future<ArchiveImage?> pick(BuildContext context) async {
    String? path;
    try {
      final picked = await LocalImageHelper.filePickerAdapter.pickAttachments(
        allowedExtensions: extensions, allowMultiple: false,
      );
      path = picked.firstOrNull;
    } on FilePickerUnavailableException {
      if (!context.mounted) return null;
      final picked =
          await CrossPlatformFilePickerAdapter.showPortableFileChooserDialog(
        context,
        allowedExtensions: extensions,
      );
      path = picked.firstOrNull;
    }
    if (!context.mounted || path == null) return null;
    final selected = path;
    final file = File(selected);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size < 1 ||
        stat.size > _maxSourceBytes ||
        !extensions
            .any((extension) => selected.toLowerCase().endsWith('.$extension'))) {
      throw const FormatException(
          'Escolha uma imagem PNG, JPEG ou WebP de até 8 MiB.');
    }
    final input = await file.open();
    final bytes = await (() async {
      try {
        return await input.read(_maxSourceBytes + 1);
      } finally {
        await input.close();
      }
    })();
    if (bytes.length > _maxSourceBytes) {
      throw const FormatException('A imagem selecionada excede 8 MiB.');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width * descriptor.height > _maxSourcePixels) {
          throw const FormatException(
              'A imagem selecionada excede 24 megapixels.');
        }
        for (final limit in const [ArchiveImage.maxDimension, 640, 400]) {
          final width = descriptor.width;
          final height = descriptor.height;
          final side = width > height ? width : height;
          final codec = await descriptor.instantiateCodec(
            targetWidth:
                side > limit ? (width * limit ~/ side).clamp(1, limit) : width,
            targetHeight: side > limit
                ? (height * limit ~/ side).clamp(1, limit)
                : height,
          );
          try {
            final frame = await codec.getNextFrame();
            try {
              final png =
                  await frame.image.toByteData(format: ui.ImageByteFormat.png);
              if (png != null &&
                  png.lengthInBytes <= ArchiveImage.maxImageBytes) {
                return ArchiveImage.fromPng(
                  png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
                );
              }
            } finally {
              frame.image.dispose();
            }
          } finally {
            codec.dispose();
          }
        }
        throw const FormatException(
            'A imagem não coube no limite da publicação.');
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }
}

class ArchiveImageView extends StatelessWidget {
  const ArchiveImageView({super.key, required this.image, required this.index});
  final ArchiveImage image;
  final int index;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360, maxWidth: 680),
              child: Image.memory(
                image.bytes,
                fit: BoxFit.contain,
                semanticLabel: image.caption.isEmpty
                    ? 'Imagem ${index + 1}'
                    : image.caption,
                errorBuilder: (_, __, ___) =>
                    const Text('Não foi possível abrir esta imagem.'),
              ),
            ),
            if (image.caption.isNotEmpty) Text(image.caption),
          ],
        ),
      );
}
