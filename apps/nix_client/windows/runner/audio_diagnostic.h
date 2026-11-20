#ifndef RUNNER_AUDIO_DIAGNOSTIC_H_
#define RUNNER_AUDIO_DIAGNOSTIC_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <mmsystem.h>

#include <array>
#include <cstdint>
#include <vector>

class AudioDiagnostic {
 public:
  explicit AudioDiagnostic(flutter::BinaryMessenger* messenger);
  ~AudioDiagnostic();

 private:
  struct Buffer {
    std::array<std::int16_t, 512> samples{};
    WAVEHDR header{};
  };

  struct PlaybackBuffer {
    std::array<std::uint8_t, 24000> bytes{};
    WAVEHDR header{};
  };

  bool Start();
  bool ReadSamples(std::vector<std::uint8_t>& pcm);
  bool PlayCall(const std::vector<std::uint8_t>& pcm);
  void StopPlayback();
  void Stop();
  void ReadLevel(flutter::MethodResult<flutter::EncodableValue>& result);

  flutter::MethodChannel<flutter::EncodableValue> channel_;
  HWAVEIN capture_ = nullptr;
  HWAVEOUT playback_ = nullptr;
  bool in_call_ = false;
  size_t next_input_ = 0;
  std::array<PlaybackBuffer, 3> playback_buffers_{};
  std::array<Buffer, 24> buffers_{};
};

#endif  // RUNNER_AUDIO_DIAGNOSTIC_H_
