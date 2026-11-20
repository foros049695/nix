#ifndef RUNNER_AUDIO_DIAGNOSTIC_H_
#define RUNNER_AUDIO_DIAGNOSTIC_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <mmsystem.h>

#include <array>
#include <cstdint>

class AudioDiagnostic {
 public:
  explicit AudioDiagnostic(flutter::BinaryMessenger* messenger);
  ~AudioDiagnostic();

 private:
  struct Buffer {
    std::array<std::int16_t, 512> samples{};
    WAVEHDR header{};
  };

  bool Start();
  void Stop();
  void ReadLevel(flutter::MethodResult<flutter::EncodableValue>& result);

  flutter::MethodChannel<flutter::EncodableValue> channel_;
  HWAVEIN capture_ = nullptr;
  std::array<Buffer, 8> buffers_{};
};

#endif  // RUNNER_AUDIO_DIAGNOSTIC_H_
