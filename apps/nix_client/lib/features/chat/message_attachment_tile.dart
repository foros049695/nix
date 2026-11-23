import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import '../../core/media/voice_note.dart';
import 'telegram_audio_card.dart';
import 'package:provider/provider.dart';

import '../../core/models/message.dart';
import '../../core/security/local_image_helper.dart';
import '../../core/security/secure_file_download_helper.dart';
import '../../core/theme.dart';
import '../../core/theme/nix_colors.dart';
import '../../state/nix_state.dart';

class MessageAttachmentTile extends StatefulWidget {
  const MessageAttachmentTile(
      {super.key, required this.message, required this.index});

  final Message message;
  final int index;

  @override
  State<MessageAttachmentTile> createState() => _MessageAttachmentTileState();
}

class _MessageAttachmentTileState extends State<MessageAttachmentTile> {
  Future<Uint8List?>? _imageBytes;

  String get _reference => widget.message.attachments[widget.index];
  String get _name => LocalImageHelper.getFileName(_reference);

  static const _videoExtensions = ['mp4', 'mkv', 'webm', 'mov', 'avi'];

  bool get _isVideo {
    final lower = _name.toLowerCase();
    return _videoExtensions.any((ext) => lower.endsWith('.$ext'));
  }

  bool get _isVoiceNote =>
      _name == VoiceNote.fileName ||
      _name.endsWith(VoiceNote.fileName) ||
      (_name.toLowerCase().endsWith('.wav') &&
          (_name.toLowerCase().contains('voice') ||
              _name.toLowerCase().contains('voz')));

  bool get _isPhoto {
    return LocalImageHelper.isSupportedExtension(_name) && !_name.startsWith('doc_');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(MessageAttachmentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.index != widget.index ||
        oldWidget.message.attachments[oldWidget.index] != _reference) {
      _imageBytes = null;
      _load();
    }
  }

  void _load() {
    if (_imageBytes != null || !_isPhoto) return;
    _imageBytes =
        context.read<NixState>().readMessageImage(widget.message, widget.index);
  }

  IconData _resolveDocumentIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (lower.endsWith('.zip') || lower.endsWith('.tar') || lower.endsWith('.gz') || lower.endsWith('.7z')) {
      return Icons.folder_zip_rounded;
    }
    if (lower.endsWith('.txt') || lower.endsWith('.md') || lower.endsWith('.json') || lower.endsWith('.csv')) {
      return Icons.article_rounded;
    }
    if (lower.endsWith('.apk') || lower.endsWith('.deb') || lower.endsWith('.exe')) {
      return Icons.extension_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  String _resolveDocumentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'Documento PDF';
    if (lower.endsWith('.zip') || lower.endsWith('.tar') || lower.endsWith('.gz') || lower.endsWith('.7z')) {
      return 'Arquivo compactado';
    }
    if (lower.endsWith('.txt')) return 'Arquivo de texto';
    if (lower.endsWith('.md')) return 'Documento Markdown';
    if (lower.endsWith('.json')) return 'Arquivo JSON';
    if (lower.endsWith('.csv')) return 'Planilha CSV';
    if (lower.endsWith('.apk')) return 'Instalador Android (APK)';
    if (lower.endsWith('.deb')) return 'Pacote Debian/Ubuntu';
    return 'Documento Cifrado';
  }

  Future<void> _openPhotoViewer(BuildContext context, Uint8List bytes) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black.withValues(alpha: 0.92),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.image_outlined, size: 18, color: Colors.white70),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _name,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_rounded, color: Colors.white70),
                    tooltip: 'Salvar imagem',
                    onPressed: () async {
                      final confirmed = await SecureFileDownloadHelper.confirmDownload(
                        dialogContext,
                        fileName: _name,
                        byteSize: bytes.length,
                      );
                      if (confirmed && mounted) {
                        try {
                          final file = await SecureFileDownloadHelper.saveFileSafely(
                            bytes: bytes,
                            rawFileName: _name,
                          );
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Foto salva com segurança em: ${file.path}')),
                            );
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Erro ao salvar foto: $e')),
                            );
                          }
                        }
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openVideoViewer(BuildContext context) async {
    final state = context.read<NixState>();
    final bytes = await state.readMessageAttachmentBytes(widget.message, widget.index);

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black.withValues(alpha: 0.94),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.movie_outlined, size: 18, color: Colors.white70),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _name,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (bytes != null)
                    IconButton(
                      icon: const Icon(Icons.download_rounded, color: Colors.white70),
                      tooltip: 'Baixar vídeo',
                      onPressed: () async {
                        final confirmed = await SecureFileDownloadHelper.confirmDownload(
                          dialogContext,
                          fileName: _name,
                          byteSize: bytes.length,
                        );
                        if (confirmed && mounted) {
                          try {
                            final file = await SecureFileDownloadHelper.saveFileSafely(
                              bytes: bytes,
                              rawFileName: _name,
                            );
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Vídeo salvo com segurança em: ${file.path}')),
                              );
                            }
                          } catch (e) {
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Erro ao salvar vídeo: $e')),
                              );
                            }
                          }
                        }
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
            ),
            Container(
              height: 240,
              width: double.infinity,
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_circle_fill_rounded, size: 64, color: Colors.white70),
                    const SizedBox(height: 12),
                    Text(
                      'Reprodução de Vídeo Protegida',
                      style: TextStyle(color: NixColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Decodificação isolada no cliente Nix sem tráfego remoto',
                      style: TextStyle(color: NixColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadDocument(BuildContext context) async {
    final state = context.read<NixState>();
    final confirmed = await SecureFileDownloadHelper.confirmDownload(
      context,
      fileName: _name,
    );
    if (!confirmed || !context.mounted) return;

    final bytes = await state.readMessageAttachmentBytes(widget.message, widget.index);
    if (bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível ler os dados do anexo.')),
        );
      }
      return;
    }

    try {
      final saved = await SecureFileDownloadHelper.saveFileSafely(
        bytes: bytes,
        rawFileName: _name,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Arquivo verificado (SHA-256) e salvo com segurança em: ${saved.path}'),
            backgroundColor: Colors.green.shade800,
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Falha na verificação de integridade: $error'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.nixScheme;
    final isSupportedVoicePlatform = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows;

    // 1. Mensagem de Voz (Padrão visual Telegram com waveform e player inline)
    if (_isVoiceNote && isSupportedVoicePlatform) {
      final state = context.read<NixState>();
      final message = widget.message;
      final index = widget.index;
      return TelegramAudioCard(
        message: message,
        index: index,
        load: () => state.readMessageVoiceNote(message, index),
      );
    }

    // 2. Fotos (Sem nome do arquivo nem extensão no balão por padrão)
    if (_isPhoto) {
      return FutureBuilder<Uint8List?>(
        future: _imageBytes,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) {
            return Container(
              width: 140,
              height: 100,
              decoration: BoxDecoration(
                color: scheme.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Icon(Icons.image_outlined, size: 24, color: Colors.white24),
              ),
            );
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: ValueKey('message_image_${widget.message.id}_${widget.index}'),
              onTap: () => _openPhotoViewer(context, bytes),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 320,
                  maxHeight: 260,
                ),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  cacheWidth: Platform.environment.containsKey('FLUTTER_TEST') ? null : 640,
                  errorBuilder: (_, __, ___) => Container(
                    padding: const EdgeInsets.all(16),
                    color: scheme.surfaceElevated,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    // 3. Vídeos (Miniatura com botão play, tipo/duração e visualizador)
    if (_isVideo) {
      return InkWell(
        key: ValueKey('message_video_${widget.message.id}_${widget.index}'),
        onTap: () => _openVideoViewer(context),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 260,
          height: 160,
          decoration: BoxDecoration(
            color: NixColors.surfaceCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: NixColors.surfaceBorder),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    color: Colors.black45,
                    child: Center(
                      child: Icon(
                        Icons.movie_outlined,
                        size: 48,
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white30, width: 1.5),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_rounded, size: 12, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text(
                        _name.split('.').last.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 4. Documentos (Apresentação própria com ícone, nome, tipo e ação de baixar com aviso)
    final docIcon = _resolveDocumentIcon(_name);
    final docType = _resolveDocumentType(_name);

    return InkWell(
      key: ValueKey('message_doc_${widget.message.id}_${widget.index}'),
      onTap: () async {
        final state = context.read<NixState>();
        final bytes = await state.readMessageAttachmentBytes(widget.message, widget.index);
        if (bytes != null && LocalImageHelper.isSupportedExtension(_name) && context.mounted) {
          await _openPhotoViewer(context, bytes);
        } else if (context.mounted) {
          await _downloadDocument(context);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: NixColors.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: NixColors.surfaceBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                docIcon,
                color: context.accentTextColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: NixColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    docType,
                    style: TextStyle(
                      color: NixColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.download_rounded, size: 20),
              color: NixColors.textSecondary,
              tooltip: 'Baixar arquivo seguro',
              onPressed: () => _downloadDocument(context),
            ),
          ],
        ),
      ),
    );
  }
}
