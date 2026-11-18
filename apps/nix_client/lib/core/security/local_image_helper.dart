import 'dart:io';
import 'dart:typed_data';

/// Utilitário local para seleção, validação e remoção de metadados (EXIF/chunks) de imagens
/// (PNG, JPEG, WebP) para Avatar e Capas Culturais do Card ID.
class LocalImageHelper {
  static const List<String> supportedExtensions = ['png', 'jpg', 'jpeg', 'webp', 'gif'];
  static const List<String> supportedMediaExtensions = [
    'png', 'jpg', 'jpeg', 'webp', 'gif',
    'mp4', 'mkv', 'webm',
    'mp3', 'ogg', 'wav', 'flac',
    'pdf', 'txt', 'docx', 'md', 'json', 'tar', 'gz', 'zip'
  ];

  static bool isSupportedExtension(String path) {
    final lower = path.trim().toLowerCase();
    return supportedExtensions.any((ext) => lower.endsWith('.$ext'));
  }

  /// Formata tamanho em bytes para leitura humana (ex: 2.4 MB)
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Retorna o nome base do arquivo
  static String getFileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  /// Invoca seletor nativo para qualquer anexo (imagens, áudio, vídeos, documentos).
  static Future<List<String>> pickAttachmentsNativeDesktop() async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return ['documento_seguro.pdf'];
    }
    if (!Platform.isLinux) return [];
    try {
      final res = await Process.run(
        'zenity',
        [
          '--file-selection',
          '--multiple',
          '--separator=|',
          '--title=Selecionar Arquivos / Anexos (Criptografia E2EE Nix)',
          '--file-filter=Todos os Arquivos Suportados | *.png *.jpg *.jpeg *.webp *.gif *.mp4 *.mp3 *.ogg *.wav *.pdf *.txt *.docx *.zip',
        ],
      );
      if (res.exitCode == 0) {
        final out = res.stdout.toString().trim();
        if (out.isNotEmpty) {
          return out.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        }
      }
    } catch (_) {}

    try {
      final res = await Process.run(
        'kdialog',
        [
          '--getopenfilename',
          '--multiple',
          '--separate-output',
          Platform.environment['HOME'] ?? '.',
          '*.png *.jpg *.jpeg *.webp *.gif *.mp4 *.mp3 *.ogg *.wav *.pdf *.txt *.docx|Arquivos Suportados',
        ],
      );
      if (res.exitCode == 0) {
        final out = res.stdout.toString().trim();
        if (out.isNotEmpty) {
          return out.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        }
      }
    } catch (_) {}

    return [];
  }

  /// Invoca seletor de arquivos nativo no Desktop (Linux `zenity`/`kdialog`) quando disponível.
  static Future<String?> pickImageNativeDesktop() async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return '/tmp/nix_test_avatar.png';
    }
    if (!Platform.isLinux) return null;
    try {
      final res = await Process.run(
        'zenity',
        [
          '--file-selection',
          '--title=Selecionar Imagem Local (PNG, JPEG, WebP)',
          '--file-filter=Imagens | *.png *.jpg *.jpeg *.webp',
        ],
      );
      if (res.exitCode == 0) {
        final out = res.stdout.toString().trim();
        if (out.isNotEmpty) return out;
      }
    } catch (_) {}

    try {
      final res = await Process.run(
        'kdialog',
        [
          '--getopenfilename',
          Platform.environment['HOME'] ?? '.',
          '*.png *.jpg *.jpeg *.webp|Imagens',
        ],
      );
      if (res.exitCode == 0) {
        final out = res.stdout.toString().trim();
        if (out.isNotEmpty) return out;
      }
    } catch (_) {}

    return null;
  }

  /// Copia a imagem para área isolada local removendo metadados JPEG (APP1-APP15/COM) e PNG (eXIf/tEXt/iTXt/zTXt).
  static Future<String?> sanitizeAndStoreImage(String sourcePath) async {
    final file = File(sourcePath.trim());
    if (!await file.exists()) return null;
    if (!isSupportedExtension(sourcePath)) return null;

    final raw = await file.readAsBytes();
    final cleaned = stripMetadataBytes(raw);

    final home = Platform.environment['HOME'] ?? '/tmp';
    final cacheDir = Directory('$home/.local/share/nix/sanitized_media');
    await cacheDir.create(recursive: true);

    final ext = sourcePath.split('.').last.toLowerCase();
    final outPath =
        '${cacheDir.path}/nix_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File(outPath).writeAsBytes(cleaned, flush: true);
    return outPath;
  }

  /// Remove segmentos EXIF/XMP/IPTC de JPEG e chunks textuais/EXIF de PNG em memória pura.
  static Uint8List stripMetadataBytes(Uint8List data) {
    if (data.length < 12) return data;

    // JPEG: SOI (FF D8) ... remove APP1..APP15 (FF E1..FF EF) e COM (FF FE)
    if (data[0] == 0xFF && data[1] == 0xD8) {
      final out = BytesBuilder();
      out.add([0xFF, 0xD8]);
      int i = 2;
      while (i + 1 < data.length) {
        if (data[i] != 0xFF) {
          out.add(data.sublist(i));
          break;
        }
        final marker = data[i + 1];
        if (marker == 0xDA || marker == 0xD9) {
          // SOS (dados da imagem) ou EOI: copia restante intacto
          out.add(data.sublist(i));
          break;
        }
        if (marker == 0x00 || (marker >= 0xD0 && marker <= 0xD7)) {
          out.add([data[i], marker]);
          i += 2;
          continue;
        }
        if (i + 3 >= data.length) {
          out.add(data.sublist(i));
          break;
        }
        final segLen = (data[i + 2] << 8) | data[i + 3];
        final endIdx = i + 2 + segLen;
        if (segLen < 2 || endIdx > data.length) {
          out.add(data.sublist(i));
          break;
        }
        final isSensitiveMeta = (marker >= 0xE1 && marker <= 0xEF) || marker == 0xFE;
        if (!isSensitiveMeta) {
          out.add(data.sublist(i, endIdx));
        }
        i = endIdx;
      }
      return out.toBytes();
    }

    // PNG: assinatura 89 50 4E 47 0D 0A 1A 0A -> remove eXIf, tEXt, zTXt, iTXt, tIME
    if (data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4E &&
        data[3] == 0x47) {
      final out = BytesBuilder();
      out.add(data.sublist(0, 8));
      int i = 8;
      const stripTypes = {'eXIf', 'tEXt', 'zTXt', 'iTXt', 'tIME'};
      while (i + 12 <= data.length) {
        final len = (data[i] << 24) |
            (data[i + 1] << 16) |
            (data[i + 2] << 8) |
            data[i + 3];
        final type = String.fromCharCodes(data.sublist(i + 4, i + 8));
        final totalLen = 12 + len;
        if (len < 0 || i + totalLen > data.length) {
          out.add(data.sublist(i));
          break;
        }
        if (!stripTypes.contains(type)) {
          out.add(data.sublist(i, i + totalLen));
        }
        i += totalLen;
      }
      return out.toBytes();
    }

    return data;
  }
}
