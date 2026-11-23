import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'file_picker_adapter.dart';
import 'platform_runtime.dart';

/// Utilitário local para seleção, validação e remoção de metadados (EXIF/chunks) de imagens
/// (PNG, JPEG, WebP, GIF) para Avatar e Capas Culturais do Card ID.
class LocalImageHelper {
  static FilePickerAdapter filePickerAdapter =
      const CrossPlatformFilePickerAdapter();

  static const List<String> supportedImageExtensions = ['png', 'jpg', 'jpeg', 'webp', 'gif'];
  static const List<String> supportedVideoExtensions = ['mp4', 'webm', 'mkv', 'mov', 'avi'];
  static const List<String> supportedExtensions = [
    'png', 'jpg', 'jpeg', 'webp', 'gif',
    'mp4', 'webm', 'mkv', 'mov', 'avi',
  ];
  static const List<String> supportedMediaExtensions = [
    'png', 'jpg', 'jpeg', 'webp', 'gif',
    'mp4', 'mkv', 'webm', 'mov', 'avi',
    'mp3', 'ogg', 'wav', 'flac',
    'pdf', 'txt', 'docx', 'md', 'json', 'tar', 'gz', 'zip'
  ];

  static bool isSupportedExtension(String path) {
    final lower = path.trim().toLowerCase();
    return supportedExtensions.any((ext) => lower.endsWith('.$ext'));
  }

  static bool isVideoExtension(String path) {
    final lower = path.trim().toLowerCase();
    return supportedVideoExtensions.any((ext) => lower.endsWith('.$ext'));
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
    final parts = path.replaceAll('\\', '/').split('/').where((part) => part.isNotEmpty);
    return (parts.lastOrNull ?? 'Anexo').replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '');
  }

  /// Invoca seletor portável multiplataforma para qualquer anexo (imagens, áudio, vídeos, documentos).
  static Future<List<String>> pickAttachmentsNativeDesktop() async {
    return filePickerAdapter.pickAttachments(
      allowedExtensions: supportedMediaExtensions,
      allowMultiple: true,
    );
  }

  /// Invoca seletor de imagens multiplataforma (PNG, JPEG, WebP, GIF).
  static Future<String?> pickImageNativeDesktop() async {
    return filePickerAdapter.pickImage(
      allowedExtensions: supportedExtensions,
    );
  }

  /// Copia a imagem ou vídeo para área isolada após sanitização; recusa contêiner malformado.
  /// Se for um vídeo (MP4, WebM, MKV, MOV, AVI), converte automaticamente para WebP animado
  /// com loop contínuo para renderização de alta fluidez em fundos, perfis e banners.
  static Future<String?> sanitizeAndStoreImage(
    String sourcePath, {
    int maxDimension = 1280,
    int maxSeconds = 12,
    int fps = 18,
  }) async {
    final file = File(sourcePath.trim());
    if (!await file.exists()) return null;
    if (!isSupportedExtension(sourcePath)) return null;

    final ext = sourcePath.split('.').last.toLowerCase();
    final isVideo = supportedVideoExtensions.contains(ext);

    if (isVideo) {
      final converted = await _tryConvertVideoToAnimatedWebp(
        sourceFile: file,
        maxDimension: maxDimension,
        maxSeconds: maxSeconds,
        fps: fps,
      );
      if (converted != null) return converted;

      return _writeDirectMedia(await file.readAsBytes(), ext);
    }

    return _sanitizeAndStoreBytes(await file.readAsBytes(), ext);
  }

  static Future<String?> _tryConvertVideoToAnimatedWebp({
    required File sourceFile,
    int maxDimension = 1280,
    int maxSeconds = 12,
    int fps = 18,
  }) async {
    try {
      final cacheDir = Directory(NixPlatformPaths.resolveDataFile('sanitized_media'));
      await cacheDir.create(recursive: true);
      final outPath =
          '${cacheDir.path}/nix_anim_${DateTime.now().microsecondsSinceEpoch}.webp';

      final filter = 'fps=$fps,scale=min($maxDimension\\,iw):-2:flags=lanczos';

      final result = await Process.run(
        'ffmpeg',
        [
          '-y',
          '-v', 'error',
          '-i', sourceFile.path,
          '-t', '$maxSeconds',
          '-vf', filter,
          '-loop', '0',
          outPath,
        ],
      );

      if (result.exitCode == 0 && await File(outPath).exists() && await File(outPath).length() > 0) {
        return outPath;
      }
    } catch (_) {}
    return null;
  }

  static Future<String> _writeDirectMedia(Uint8List data, String ext) async {
    final cacheDir = Directory(NixPlatformPaths.resolveDataFile('sanitized_media'));
    await cacheDir.create(recursive: true);

    final outPath =
        '${cacheDir.path}/nix_media_${DateTime.now().microsecondsSinceEpoch}.$ext';
    await File(outPath).writeAsBytes(data, flush: true);
    return outPath;
  }

  static ({Uint8List bytes, String extension})? readCatalogThumbnail(String? reference) {
    if (reference == null || reference.length > 1400000) return null;
    final match = RegExp(r'^data:image/(png|jpeg|webp);base64,').firstMatch(reference);
    if (match == null) return null;
    try {
      final bytes = base64Decode(reference.substring(match.end));
      return (bytes: stripMetadataBytes(bytes), extension: match.group(1)!);
    } on FormatException {
      return null;
    }
  }

  static Future<String?> storeCatalogThumbnail(String? reference) async {
    final thumbnail = readCatalogThumbnail(reference);
    if (thumbnail == null) return null;
    return _writeCleanImage(thumbnail.bytes, thumbnail.extension);
  }

  static Future<String?> _sanitizeAndStoreBytes(Uint8List raw, String ext) async {
    final Uint8List cleaned;
    try {
      cleaned = stripMetadataBytes(raw);
    } on FormatException {
      return null;
    }

    return _writeCleanImage(cleaned, ext);
  }

  static Future<String> _writeCleanImage(Uint8List cleaned, String ext) async {
    final cacheDir = Directory(NixPlatformPaths.resolveDataFile('sanitized_media'));
    await cacheDir.create(recursive: true);

    final outPath =
        '${cacheDir.path}/nix_${DateTime.now().microsecondsSinceEpoch}.$ext';
    await File(outPath).writeAsBytes(cleaned, flush: true);
    return outPath;
  }

  static File get pagerWallpaper =>
      File(NixPlatformPaths.resolveDataFile('sanitized_media/pager_wallpaper'));

  static Future<bool> storePagerWallpaper(String sourcePath) async {
    final source = File(sourcePath);
    if (!isSupportedExtension(sourcePath) || !await source.exists() ||
        await source.length() > 100 * 1024 * 1024) {
      return false;
    }
    final ext = sourcePath.split('.').last.toLowerCase();
    final isVideo = supportedVideoExtensions.contains(ext);
    final Uint8List cleaned;
    if (isVideo) {
      final converted = await _tryConvertVideoToAnimatedWebp(sourceFile: source, maxDimension: 640);
      if (converted != null) {
        cleaned = await File(converted).readAsBytes();
      } else {
        cleaned = await source.readAsBytes();
      }
    } else {
      cleaned = stripMetadataBytes(await source.readAsBytes());
    }
    final file = pagerWallpaper;
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.pending');
    try {
      await pending.writeAsBytes(cleaned, flush: true);
      await pending.rename(file.path);
    } finally {
      if (await pending.exists()) await pending.delete();
    }
    return true;
  }

  /// Remove metadados dos contêineres suportados sem decodificar pixels.
  /// Estruturas truncadas/desconhecidas são recusadas, nunca copiadas em aberto.
  static Uint8List stripMetadataBytes(Uint8List data) {
    if (_matches(data, 0, [0xff, 0xd8])) return _stripJpeg(data);
    if (_matches(data, 0, [137, 80, 78, 71, 13, 10, 26, 10])) {
      return _stripPng(data);
    }
    if (_matches(data, 0, 'RIFF'.codeUnits) &&
        _matches(data, 8, 'WEBP'.codeUnits)) {
      return _stripWebp(data);
    }
    if (_matches(data, 0, 'GIF87a'.codeUnits) ||
        _matches(data, 0, 'GIF89a'.codeUnits)) {
      return _stripGif(data);
    }
    throw const FormatException('Formato de imagem inválido ou não suportado.');
  }

  static bool _matches(Uint8List data, int offset, List<int> expected) {
    if (offset + expected.length > data.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (data[offset + i] != expected[i]) return false;
    }
    return true;
  }

  static void _require(bool condition) {
    if (!condition) {
      throw const FormatException('Contêiner de imagem malformado.');
    }
  }

  static Uint8List _stripJpeg(Uint8List data) {
    final out = BytesBuilder()..add([0xff, 0xd8]);
    var i = 2;
    var inScan = false;
    while (i < data.length) {
      if (inScan) {
        final start = i;
        // FF00 e restart markers pertencem aos dados comprimidos. Outros
        // marcadores encerram o scan, inclusive em JPEG progressivo.
        while (i < data.length) {
          if (data[i] != 0xff) {
            i++;
            continue;
          }
          var next = i + 1;
          while (next < data.length && data[next] == 0xff) {
            next++;
          }
          _require(next < data.length);
          final marker = data[next];
          if (marker == 0 || (marker >= 0xd0 && marker <= 0xd7)) {
            i = next + 1;
            continue;
          }
          break;
        }
        out.add(data.sublist(start, i));
        inScan = false;
      }
      _require(i < data.length && data[i] == 0xff);
      final start = i;
      while (i < data.length && data[i] == 0xff) {
        i++;
      }
      _require(i < data.length);
      final marker = data[i++];
      if (marker == 0xd9) {
        out.add(data.sublist(start, i));
        return out.toBytes();
      }
      _require(
          marker != 0 && marker != 0xd8 && !(marker >= 0xd0 && marker <= 0xd7));
      if (marker == 0x01) {
        // TEM não possui campo de comprimento.
        out.add(data.sublist(start, i));
        continue;
      }
      _require(i + 2 <= data.length);
      final length = (data[i] << 8) | data[i + 1];
      _require(length >= 2 && i + length <= data.length);
      final end = i + length;
      if (!((marker >= 0xe1 && marker <= 0xef) || marker == 0xfe)) {
        out.add(data.sublist(start, end));
      }
      inScan = marker == 0xda;
      i = end;
    }
    throw const FormatException('JPEG sem EOI.');
  }

  static Uint8List _stripPng(Uint8List data) {
    final out = BytesBuilder()..add(data.sublist(0, 8));
    final view = ByteData.sublistView(data);
    var i = 8;
    // iCCP também permite nomes e descrições identificadoras do perfil.
    const stripTypes = {'eXIf', 'tEXt', 'zTXt', 'iTXt', 'tIME', 'iCCP'};
    while (i < data.length) {
      _require(i + 12 <= data.length);
      final length = view.getUint32(i, Endian.big);
      final end = i + 12 + length;
      _require(end <= data.length);
      final type = String.fromCharCodes(data.sublist(i + 4, i + 8));
      _require(RegExp(r'^[a-zA-Z]{4}$').hasMatch(type));
      if (i == 8) _require(type == 'IHDR' && length == 13);
      if (type == 'IEND') _require(length == 0);
      if (!stripTypes.contains(type)) out.add(data.sublist(i, end));
      if (type == 'IEND') return out.toBytes();
      i = end;
    }
    throw const FormatException('PNG sem IEND.');
  }

  static Uint8List _stripWebp(Uint8List data) {
    final view = ByteData.sublistView(data);
    final end = view.getUint32(4, Endian.little) + 8;
    _require(end >= 12 && end <= data.length);
    final chunks = BytesBuilder();
    var i = 12;
    while (i < end) {
      _require(i + 8 <= end);
      final type = String.fromCharCodes(data.sublist(i, i + 4));
      final length = view.getUint32(i + 4, Endian.little);
      final next = i + 8 + length + (length & 1);
      _require(next <= end);
      if (length.isOdd) _require(data[next - 1] == 0);
      if (type == 'VP8X') {
        _require(length == 10);
        final chunk = data.sublist(i, next);
        chunk[8] &= ~0x0c; // Limpa somente flags EXIF (0x08) e XMP (0x04).
        chunks.add(chunk);
      } else if (type != 'EXIF' && type != 'XMP ') {
        chunks.add(data.sublist(i, next));
      }
      i = next;
    }
    final body = chunks.takeBytes();
    _require(body.isNotEmpty);
    final header = data.sublist(0, 12);
    ByteData.sublistView(header).setUint32(4, body.length + 4, Endian.little);
    return (BytesBuilder()
          ..add(header)
          ..add(body))
        .toBytes();
  }

  static Uint8List _stripGif(Uint8List data) {
    _require(data.length >= 13);
    var i = 13;
    if (data[10] & 0x80 != 0) {
      i += 3 * (1 << ((data[10] & 7) + 1));
    }
    _require(i <= data.length);
    final out = BytesBuilder()..add(data.sublist(0, i));
    while (i < data.length) {
      final start = i;
      final block = data[i++];
      if (block == 0x3b) {
        out.add([0x3b]);
        return out.toBytes();
      }
      var strip = false;
      if (block == 0x2c) {
        _require(i + 9 <= data.length);
        final packed = data[i + 8];
        i += 9;
        if (packed & 0x80 != 0) i += 3 * (1 << ((packed & 7) + 1));
        _require(i < data.length && data[i] >= 2 && data[i] <= 8);
        i++; // Tamanho mínimo de código LZW.
      } else if (block == 0x21) {
        _require(i + 1 < data.length);
        final label = data[i++];
        if (label == 0xf9) {
          _require(data[i] == 4 && i + 6 <= data.length && data[i + 5] == 0);
          i += 6;
          out.add(data.sublist(start, i));
          continue;
        } else if (label == 0xfe) {
          strip = true;
        } else if (label == 0xff || label == 0x01) {
          final headerSize = label == 0xff ? 11 : 12;
          _require(data[i] == headerSize && i + 1 + headerSize <= data.length);
          if (label == 0xff) {
            // Só extensões de controle de animação podem sobreviver.
            strip = !_matches(data, i + 1, 'NETSCAPE2.0'.codeUnits) &&
                !_matches(data, i + 1, 'ANIMEXTS1.0'.codeUnits);
          }
          i += 1 + headerSize;
        } else {
          throw const FormatException('Extensão GIF desconhecida.');
        }
      } else {
        throw const FormatException('Bloco GIF inválido.');
      }
      // Dados de imagem, comentários e aplicações usam sub-blocos terminados em 0.
      while (true) {
        _require(i < data.length);
        final length = data[i++];
        _require(i + length <= data.length);
        i += length;
        if (length == 0) break;
      }
      if (!strip) out.add(data.sublist(start, i));
    }
    throw const FormatException('GIF sem trailer.');
  }
}
