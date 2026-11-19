import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/security/local_image_helper.dart';

Uint8List bytes(List<int> value) => Uint8List.fromList(value);
List<int> u32(int value, Endian endian) =>
    (ByteData(4)..setUint32(0, value, endian)).buffer.asUint8List();
List<int> pngChunk(String name, List<int> payload) => [
      ...u32(payload.length, Endian.big), ...name.codeUnits, ...payload,
      0, 0, 0, 0, // CRC não é interpretado pelo sanitizador de contêiner.
    ];
final pngHeader = [137, 80, 78, 71, 13, 10, 26, 10];
final png = [
  ...pngHeader,
  ...pngChunk('IHDR', List.filled(13, 0)),
  ...pngChunk('IDAT', [1]),
  ...pngChunk('IEND', []),
];
List<int> riffChunk(String name, List<int> payload) => [
      ...name.codeUnits,
      ...u32(payload.length, Endian.little),
      ...payload,
      if (payload.length.isOdd) 0,
    ];
List<int> webp(List<int> chunks) => [
      ...'RIFF'.codeUnits,
      ...u32(chunks.length + 4, Endian.little),
      ...'WEBP'.codeUnits,
      ...chunks,
    ];
final vp8x = [0x1c, ...List.filled(9, 0)]; // alpha, EXIF, XMP
final vp8 = riffChunk('VP8 ', [1, 2, 3]);
final jpeg = [
  0xff,
  0xd8,
  0xff,
  0xda,
  0,
  3,
  1,
  42,
  0xff,
  0,
  10,
  0xff,
  0xd0,
  11,
  0xff,
  0xd9
];
final gifHeader = [
  ...'GIF89a'.codeUnits,
  1,
  0,
  1,
  0,
  0x80,
  0,
  0,
  0,
  0,
  0,
  255,
  255,
  255
];
final gifFrame = [
  0x21,
  0xf9,
  4,
  0,
  0,
  0,
  0,
  0,
  0x2c,
  0,
  0,
  0,
  0,
  1,
  0,
  1,
  0,
  0,
  2,
  2,
  0x44,
  1,
  0
];
final gif = [...gifHeader, ...gifFrame, 0x3b];
List<int> app(String id) => [0x21, 0xff, 11, ...id.codeUnits, 3, 1, 0, 0, 0];

void main() {
  test('arquivo malformado é recusado sem exceção para o chamador', () async {
    final dir = await Directory.systemTemp.createTemp('nix_image_probe_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/invalid.png');
    await file.writeAsBytes([137, 80, 78, 71]);
    expect(await LocalImageHelper.sanitizeAndStoreImage(file.path), isNull);
  });

  test('GIF remove IPTC e aplicações desconhecidas, preservando loops', () {
    final input = [
      ...gifHeader,
      ...app('NETSCAPE2.0'),
      ...app('MGK8BIM0000'),
      ...app('UNKNOWN0000'),
      ...app('ANIMEXTS1.0'),
      ...gifFrame,
      0x3b
    ];
    expect(
        LocalImageHelper.stripMetadataBytes(bytes(input)),
        bytes([
          ...gifHeader,
          ...app('NETSCAPE2.0'),
          ...app('ANIMEXTS1.0'),
          ...gifFrame,
          0x3b
        ]));
  });

  test('WebP remove EXIF/XMP, limpa flags e recalcula RIFF com padding ímpar',
      () {
    final input = webp([
      ...riffChunk('VP8X', vp8x),
      ...vp8,
      ...riffChunk('EXIF', [1, 2, 3]),
      ...riffChunk('XMP ', [4, 5]),
    ]);
    final expected = webp([
      ...riffChunk('VP8X', [0x10, ...List.filled(9, 0)]),
      ...vp8
    ]);
    expect(LocalImageHelper.stripMetadataBytes(bytes(input)), bytes(expected));
    expect(
        input,
        webp([
          ...riffChunk('VP8X', vp8x),
          ...vp8,
          ...riffChunk('EXIF', [1, 2, 3]),
          ...riffChunk('XMP ', [4, 5]),
        ]),
        reason: 'Não altera a entrada');
  });

  test('GIF remove comentários e XMP preservando frames e loop', () {
    final loop = app('NETSCAPE2.0');
    final input = [
      ...gifHeader,
      ...loop,
      0x21,
      0xfe,
      3,
      65,
      66,
      67,
      0,
      ...app('XMP DataXMP'),
      ...gifFrame,
      0x3b,
      99
    ];
    expect(LocalImageHelper.stripMetadataBytes(bytes(input)),
        bytes([...gifHeader, ...loop, ...gifFrame, 0x3b]));
  });

  test('PNG descarta metadados e todo conteúdo após IEND', () {
    final input = [
      ...pngHeader,
      ...pngChunk('IHDR', List.filled(13, 0)),
      ...pngChunk('tEXt', [65]),
      ...pngChunk('iCCP', [66]),
      ...pngChunk('IDAT', [1]),
      ...pngChunk('IEND', []),
      99,
      100
    ];
    expect(LocalImageHelper.stripMetadataBytes(bytes(input)), bytes(png));
  });

  test('JPEG termina no EOI e preserva stuffing e restart de scan', () {
    expect(LocalImageHelper.stripMetadataBytes(bytes([...jpeg, 65, 66])),
        bytes(jpeg));
  });

  test('JPEG remove APP1 mesmo com fill bytes antes do marcador', () {
    final input = [
      0xff,
      0xd8,
      0xff,
      0xff,
      0xe1,
      0,
      6,
      69,
      120,
      105,
      102,
      ...jpeg.skip(2)
    ];
    expect(LocalImageHelper.stripMetadataBytes(bytes(input)), bytes(jpeg));
  });

  test('JPEG remove metadados entre scans progressivos', () {
    final scan = jpeg.sublist(2, jpeg.length - 2);
    final input = [
      0xff,
      0xd8,
      ...scan,
      0xff,
      0xe1,
      0,
      3,
      99,
      ...scan,
      0xff,
      0xd9
    ];
    expect(LocalImageHelper.stripMetadataBytes(bytes(input)),
        bytes([0xff, 0xd8, ...scan, ...scan, 0xff, 0xd9]));
  });

  test('falha fechada em cada truncamento de contêiner e formato desconhecido',
      () {
    for (final valid in [png, jpeg, gif, webp(vp8)]) {
      expect(LocalImageHelper.stripMetadataBytes(bytes(valid)), bytes(valid));
      for (var end = 0; end < valid.length; end++) {
        expect(
            () => LocalImageHelper.stripMetadataBytes(
                bytes(valid.sublist(0, end))),
            throwsFormatException,
            reason: 'Truncamento em $end de ${valid.length}');
      }
    }
    expect(() => LocalImageHelper.stripMetadataBytes(Uint8List(20)),
        throwsFormatException);
  });

  test('rejeita comprimentos inválidos e padding RIFF inválido', () {
    for (final input in [
      [0xff, 0xd8, 0xff, 0xe1, 0, 1, ...jpeg.skip(2)],
      webp(riffChunk('VP8X', [0])),
      webp([...vp8.take(vp8.length - 1), 1]),
      [...gifHeader, 0x21, 0xff, 2, 0, 0, 0, ...gifFrame, 0x3b],
      [
        ...png.take(png.length - 12),
        ...pngChunk('IEND', [1])
      ],
    ]) {
      expect(() => LocalImageHelper.stripMetadataBytes(bytes(input)),
          throwsFormatException);
    }
  });
}
