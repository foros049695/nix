import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/security/local_image_helper.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/theme/nix_tokens.dart';

enum ImageSendQuality {
  compressed,
  original,
  asFile,
}

class ImageQualityDialog extends StatefulWidget {
  final String filePath;

  const ImageQualityDialog({super.key, required this.filePath});

  static Future<ImageSendQuality?> selectQuality(
    BuildContext context, {
    required String filePath,
  }) {
    return showDialog<ImageSendQuality>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ImageQualityDialog(filePath: filePath),
    );
  }

  @override
  State<ImageQualityDialog> createState() => _ImageQualityDialogState();
}

class _ImageQualityDialogState extends State<ImageQualityDialog> {
  Uint8List? _previewBytes;
  int _byteSize = 0;
  ImageSendQuality _selected = ImageSendQuality.compressed;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final file = File(widget.filePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (mounted) {
          setState(() {
            _previewBytes = bytes;
            _byteSize = bytes.length;
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final fileName = LocalImageHelper.getFileName(widget.filePath);

    return Dialog(
      backgroundColor: NixColors.surfaceElevatedHigh,
      shape: RoundedRectangleBorder(
        borderRadius: NixTokens.borderCard,
        side: BorderSide(color: NixColors.surfaceBorderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 20, color: Colors.amber),
                  const SizedBox(width: 8),
                  Text(
                    'Modo de Envio da Imagem',
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Prévia da Imagem
              if (_previewBytes != null)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 140, maxWidth: 220),
                      color: Colors.black26,
                      child: Image.memory(
                        _previewBytes!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '$fileName (${LocalImageHelper.formatFileSize(_byteSize)})',
                  style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                ),
              ),
              const SizedBox(height: 14),
              // Opção 1: Foto Comprimida
              _buildOption(
                quality: ImageSendQuality.compressed,
                icon: Icons.photo_size_select_small_outlined,
                title: 'Foto comprimida (Recomendado)',
                description:
                    'Otimiza tamanho, remove metadados sensíveis (EXIF) e exibe diretamente no chat.',
              ),
              const SizedBox(height: 8),
              // Opção 2: Foto em Qualidade Original
              _buildOption(
                quality: ImageSendQuality.original,
                icon: Icons.high_quality_outlined,
                title: 'Foto em qualidade original',
                description:
                    'Preserva resolução integral. Alerta: arquivos originais podem conter metadados EXIF.',
              ),
              const SizedBox(height: 8),
              // Opção 3: Enviar como Arquivo
              _buildOption(
                quality: ImageSendQuality.asFile,
                icon: Icons.insert_drive_file_outlined,
                title: 'Enviar como arquivo',
                description:
                    'Trata como documento não renderizado diretamente, preservando nome e bytes exatos.',
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('confirm_image_quality_button'),
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('Confirmar Envio'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOption({
    required ImageSendQuality quality,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final isSelected = _selected == quality;
    return InkWell(
      key: Key('image_quality_${quality.name}'),
      onTap: () => setState(() => _selected = quality),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? NixColors.surfaceCard
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.amber : NixColors.surfaceBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.amber : NixColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      color: NixColors.textMuted,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Radio<ImageSendQuality>(
              value: quality,
              groupValue: _selected,
              onChanged: (val) {
                if (val != null) setState(() => _selected = val);
              },
            ),
          ],
        ),
      ),
    );
  }
}
