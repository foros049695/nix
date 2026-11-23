import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/features/chat/desktop_voice_audio.dart';

void main() {
  test('DesktopVoiceAudio manages recording and playback lifecycles cleanly', () async {
    final audio = DesktopVoiceAudio();

    expect(audio.state, 'idle');
    expect(audio.samples, 0);
    expect(audio.peak, 0);
    expect(audio.isPlaying, isFalse);

    // Status returns initial map
    final initialStatus = await audio.status();
    expect(initialStatus['state'], 'idle');
    expect(initialStatus['samples'], 0);

    // Pause / Resume transitions
    await audio.pause();
    expect(audio.state, 'idle'); // cannot pause if not recording

    // Cancel cleans up state
    await audio.cancel();
    expect(audio.state, 'idle');

    // Playback with empty or zero bytes
    await audio.play(Uint8List(0));
    expect(await audio.playing(), isFalse);

    await audio.stopPlayback();
    expect(await audio.playing(), isFalse);
  });
}
