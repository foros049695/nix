import 'dart:convert';
import 'dart:typed_data';

/// Um MP4 local de tamanho limitado, incorporado aos bytes assinados.
class ArchiveVideo {
  static const maxBytes = 2 * 1024 * 1024;
  static const _boxes = {'ftyp', 'moov', 'mdat', 'free', 'skip', 'wide'};

  final Uint8List _bytes;

  ArchiveVideo._(this._bytes);

  Uint8List get bytes => Uint8List.fromList(_bytes);

  factory ArchiveVideo.fromMp4(Uint8List input) {
    if (input.length < 32 || input.length > maxBytes) {
      throw const FormatException('Escolha um MP4 de até 2 MiB.');
    }
    final data = ByteData.sublistView(input);
    final found = <String>{};
    var offset = 0;
    while (offset < input.length) {
      if (input.length - offset < 8) {
        throw const FormatException('Estrutura MP4 incompleta.');
      }
      final size = data.getUint32(offset);
      final type = String.fromCharCodes(input.sublist(offset + 4, offset + 8));
      if (size < 8 ||
          size > input.length - offset ||
          !_boxes.contains(type) ||
          (offset == 0 && (type != 'ftyp' || size < 16)) ||
          (type == 'ftyp' && offset != 0) ||
          ((type == 'moov' || type == 'mdat') && size == 8)) {
        throw const FormatException(
            'Use um MP4 autocontido e não fragmentado.');
      }
      if (!found.add(type) && (type == 'moov' || type == 'mdat')) {
        throw const FormatException('Estrutura MP4 incompatível.');
      }
      if (type == 'moov') _verifyTracks(data, offset + 8, offset + size);
      offset += size;
    }
    if (!found.containsAll({'moov', 'mdat'})) {
      throw const FormatException('MP4 sem cabeçalho ou conteúdo de mídia.');
    }
    return ArchiveVideo._(Uint8List.fromList(input));
  }

  static void _verifyTracks(ByteData data, int start, int end) {
    var tracks = 0;
    for (final track in _children(data, start, end, 0x7472616b)) {
      if (++tracks > 8) throw const FormatException('O MP4 tem muitas faixas.');
      final media = _one(data, track, 0x6d646961);
      final mediaInfo = _one(data, media, 0x6d696e66);
      final info = _one(data, mediaInfo, 0x64696e66);
      final refs = _one(data, info, 0x64726566);
      // dref FullBox, uma entrada e uma url FullBox marcada como autocontida.
      if (refs.$2 - refs.$1 != 20 ||
          data.getUint32(refs.$1) != 0 ||
          data.getUint32(refs.$1 + 4) != 1 ||
          data.getUint32(refs.$1 + 8) != 12 ||
          data.getUint32(refs.$1 + 12) != 0x75726c20 ||
          data.getUint32(refs.$1 + 16) != 1) {
        throw const FormatException('O MP4 contém referência a mídia externa.');
      }
    }
    if (tracks == 0)
      throw const FormatException('O MP4 não tem faixas locais.');
  }

  static (int, int) _one(ByteData data, (int, int) parent, int type) {
    final matches = _children(data, parent.$1, parent.$2, type).toList();
    if (matches.length != 1) {
      throw const FormatException('Faixa MP4 incompatível.');
    }
    return matches.single;
  }

  static Iterable<(int, int)> _children(
      ByteData data, int offset, int end, int type) sync* {
    while (offset < end) {
      if (end - offset < 8) throw const FormatException('Faixa MP4 truncada.');
      final size = data.getUint32(offset);
      if (size < 8 || size > end - offset) {
        throw const FormatException('Tamanho de caixa MP4 inválido.');
      }
      if (data.getUint32(offset + 4) == type) yield (offset + 8, offset + size);
      offset += size;
    }
  }

  static ArchiveVideo? fromJson(Object? value) {
    if (value == null) return null;
    if (value is! String || value.length > ((maxBytes + 2) ~/ 3) * 4) {
      throw const FormatException('Vídeo do Archive inválido.');
    }
    final video = ArchiveVideo.fromMp4(base64Decode(value));
    if (video.toJson() != value) {
      throw const FormatException('Codificação do vídeo inválida.');
    }
    return video;
  }

  String toJson() => base64Encode(_bytes);
}
