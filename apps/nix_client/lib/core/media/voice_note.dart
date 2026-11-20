import 'dart:typed_data';

class VoiceNote {
  static const sampleRate = 16000;
  static const maximumSeconds = 12;
  static const maximumPcmBytes = sampleRate * maximumSeconds * 2;
  static const wavHeaderBytes = 44;
  static const fileName = 'Mensagem de voz.wav';
  static const mimeType = 'audio/wav';

  const VoiceNote._(this.pcm);

  final Uint8List pcm;

  int get durationMs => pcm.length * 1000 ~/ (sampleRate * 2);

  factory VoiceNote.fromPcm(Uint8List pcm) {
    if (pcm.isEmpty || pcm.length.isOdd || pcm.length > maximumPcmBytes) {
      throw const FormatException('A gravação está vazia ou excede o limite.');
    }
    return VoiceNote._(pcm);
  }

  Uint8List _wavHeader() {
    final bytes = Uint8List(wavHeaderBytes);
    final header = ByteData.sublistView(bytes);
    bytes.setRange(0, 4, 'RIFF'.codeUnits);
    header.setUint32(4, wavHeaderBytes + pcm.length - 8, Endian.little);
    bytes.setRange(8, 16, 'WAVEfmt '.codeUnits);
    header
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, sampleRate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little);
    bytes.setRange(36, 40, 'data'.codeUnits);
    header.setUint32(40, pcm.length, Endian.little);
    return bytes;
  }

  Uint8List toWav() => Uint8List(wavHeaderBytes + pcm.length)
    ..setRange(0, wavHeaderBytes, _wavHeader())
    ..setRange(wavHeaderBytes, wavHeaderBytes + pcm.length, pcm);

  factory VoiceNote.fromWav(Uint8List wav) {
    if (wav.length <= wavHeaderBytes ||
        wav.length > wavHeaderBytes + maximumPcmBytes) {
      throw const FormatException('Áudio incompatível com mensagem de voz.');
    }
    final note = VoiceNote.fromPcm(Uint8List.sublistView(wav, wavHeaderBytes));
    final expected = note._wavHeader();
    for (var index = 0; index < wavHeaderBytes; index++) {
      if (wav[index] != expected[index]) {
        throw const FormatException('Áudio incompatível com mensagem de voz.');
      }
    }
    return note;
  }
}
