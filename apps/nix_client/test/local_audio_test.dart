import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/media/local_audio_library_service.dart';

String _resolveAudioFixture(String fileName) {
  for (final candidate in [
    '../../test_fixtures/audio/$fileName',
    'test_fixtures/audio/$fileName',
  ]) {
    final file = File(candidate);
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }
  throw StateError('Fixture de áudio não encontrada: $fileName');
}

Future<bool> _hasFfmpegTools() async {
  try {
    final ffprobe = await Process.run('ffprobe', const ['-version']);
    if (ffprobe.exitCode != 0) return false;
    final ffmpeg = await Process.run('ffmpeg', const ['-version']);
    return ffmpeg.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  test('LocalAudioLibraryService extracts real metadata and cover from FLAC/MP3', () async {
    if (!await _hasFfmpegTools()) {
      markTestSkipped('A extração completa de tags/capa FLAC e MP3 exige ffprobe e ffmpeg no PATH.');
      return;
    }

    String? extractedCoverPath;
    addTearDown(() async {
      if (extractedCoverPath != null) {
        final coverFile = File(extractedCoverPath);
        if (await coverFile.exists()) {
          await coverFile.delete();
        }
      }
    });

    final service = LocalAudioLibraryService();
    final flacPath = _resolveAudioFixture('tagged_sine.flac');
    final track = await service.extractMetadata(flacPath);
    expect(track, isNotNull);
    expect(track!.name, equals('Soberano Test Flac'));
    expect(track.artist, equals('Nix Core'));
    expect(track.album, equals('Test Audio Vault'));
    expect(track.audioFormat, equals('FLAC'));
    expect(track.durationSeconds, equals(3));
    expect(track.coverPath, isNotNull);
    extractedCoverPath = track.coverPath;
    expect(File(track.coverPath!).existsSync(), isTrue);

    final mp3Path = _resolveAudioFixture('tagged_sine.mp3');
    final trackMp3 = await service.extractMetadata(mp3Path);
    expect(trackMp3, isNotNull);
    expect(trackMp3!.name, equals('Soberano Test Mp3'));
    expect(trackMp3.artist, equals('Nix Core'));
    expect(trackMp3.audioFormat, equals('MP3'));
    expect(trackMp3.durationSeconds, equals(2));
  });
}
