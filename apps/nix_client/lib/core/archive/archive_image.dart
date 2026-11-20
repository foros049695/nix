import 'dart:convert';
import 'dart:typed_data';

/// Imagem autocontida do Archive. Nenhum nome de arquivo, caminho ou URL faz
/// parte da publicação, e apenas os chunks de pixels permitidos são mantidos.
class ArchiveImage {
  ArchiveImage._(this._bytes, this.caption);

  static const maxImages = 3;
  static const maxImageBytes = 384 * 1024;
  static const maxTotalBytes = 1024 * 1024;
  static const maxDimension = 1024;
  static const maxCaptionLength = 180;
  static const _magic = [137, 80, 78, 71, 13, 10, 26, 10];
  static const _allowedChunks = {'IHDR', 'PLTE', 'tRNS', 'IDAT', 'IEND'};

  final Uint8List _bytes;
  Uint8List get bytes => Uint8List.fromList(_bytes);
  final String caption;

  factory ArchiveImage.fromPng(Uint8List bytes, {String caption = ''}) {
    final title = caption.trim();
    if (title.length > maxCaptionLength ||
        title.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
      throw const FormatException('Legenda inválida.');
    }
    return ArchiveImage._(_canonicalPng(bytes), title);
  }

  static Uint8List _canonicalPng(Uint8List bytes) {
    const invalid = FormatException('PNG incompatível com o Archive.');
    if (bytes.length < 45 || bytes.length > maxImageBytes + 64 * 1024) {
      throw invalid;
    }
    for (var index = 0; index < _magic.length; index++) {
      if (bytes[index] != _magic[index]) throw invalid;
    }
    final result = BytesBuilder(copy: false)..add(_magic);
    final data = ByteData.sublistView(bytes);
    var offset = _magic.length;
    var sawPixels = false;
    while (offset + 12 <= bytes.length) {
      final size = data.getUint32(offset, Endian.big);
      final end = offset + 12 + size;
      if (end > bytes.length) throw invalid;
      final name = String.fromCharCodes(bytes, offset + 4, offset + 8);
      if (!RegExp(r'^[A-Za-z]{4}$').hasMatch(name)) throw invalid;
      if (offset == _magic.length) {
        if (name != 'IHDR' || size != 13) throw invalid;
        final width = data.getUint32(offset + 8, Endian.big);
        final height = data.getUint32(offset + 12, Endian.big);
        if (width < 1 ||
            height < 1 ||
            width > maxDimension ||
            height > maxDimension) {
          throw const FormatException(
              'A imagem deve ter até 1024 pixels por lado.');
        }
      } else if (name == 'IHDR') {
        throw invalid;
      }
      if (_allowedChunks.contains(name)) {
        result.add(Uint8List.sublistView(bytes, offset, end));
      } else if (name.codeUnitAt(0) < 97) {
        throw invalid;
      }
      if (name == 'IDAT' && size > 0) sawPixels = true;
      if (name == 'IEND') {
        if (!sawPixels || size != 0 || end != bytes.length) throw invalid;
        final clean = result.takeBytes();
        if (clean.length > maxImageBytes) {
          throw const FormatException(
              'A imagem excede 384 KiB após preparação.');
        }
        return clean;
      }
      offset = end;
    }
    throw invalid;
  }

  Map<String, Object> toJson() => {
        'png': base64Encode(_bytes),
        'caption': caption,
      };

  static List<ArchiveImage> readList(Object? source) {
    if (source == null) return const [];
    if (source is! List || source.length > maxImages) {
      throw const FormatException('Limite de três imagens por artigo.');
    }
    final images = <ArchiveImage>[];
    for (final entry in source) {
      if (entry is! Map ||
          entry['png'] is! String ||
          entry['caption'] is! String ||
          (entry['png'] as String).length > ((maxImageBytes + 2) ~/ 3) * 4) {
        throw const FormatException('Imagem incorporada inválida.');
      }
      final encoded = entry['png'] as String;
      final bytes = base64Decode(encoded);
      final caption = entry['caption'] as String;
      final image = ArchiveImage.fromPng(bytes, caption: caption);
      if (image._bytes.length != bytes.length || image.caption != caption) {
        throw const FormatException(
            'A imagem contém dados além da representação canônica.');
      }
      images.add(image);
    }
    validateLimits(images);
    return List.unmodifiable(images);
  }

  static void validateLimits(List<ArchiveImage> images) {
    if (images.length > maxImages ||
        images.fold<int>(0, (total, item) => total + item._bytes.length) >
            maxTotalBytes) {
      throw const FormatException(
          'Use até três imagens, com até 1 MiB no total.');
    }
  }
}
