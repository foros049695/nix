import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/media/local_audio_library_service.dart';

void main() {
  test('LocalAudioLibraryService extracts real metadata and cover from FLAC/MP3', () async {
    final service = LocalAudioLibraryService();
    final flacPath = '/home/gus/.gemini/antigravity/scratch/nix/test_fixtures/audio/tagged_sine.flac';
    final track = await service.extractMetadata(flacPath);
    expect(track, isNotNull);
    expect(track!.name, equals('Soberano Test Flac'));
    expect(track.artist, equals('Nix Core'));
    expect(track.album, equals('Test Audio Vault'));
    expect(track.audioFormat, equals('FLAC'));
    expect(track.durationSeconds, equals(3));
    expect(track.coverPath, isNotNull);
    expect(File(track.coverPath!).existsSync(), isTrue);
    // ignore: avoid_print
    print('FLAC Track: ${track.name} by ${track.artist} (${track.audioFormat}, ${track.sampleRate}, ${track.bitDepth})');
    // ignore: avoid_print
    print('Extracted cover: ${track.coverPath}');

    final mp3Path = '/home/gus/.gemini/antigravity/scratch/nix/test_fixtures/audio/tagged_sine.mp3';
    final trackMp3 = await service.extractMetadata(mp3Path);
    expect(trackMp3, isNotNull);
    expect(trackMp3!.name, equals('Soberano Test Mp3'));
    expect(trackMp3.artist, equals('Nix Core'));
    expect(trackMp3.audioFormat, equals('MP3'));
    expect(trackMp3.durationSeconds, equals(2));
    // ignore: avoid_print
    print('MP3 Track: ${trackMp3.name} by ${trackMp3.artist} (${trackMp3.audioFormat}, ${trackMp3.bitRateKbps} kbps)');
  });
}
