#include "audio_diagnostic.h"

#include <algorithm>
#include <cstdlib>
#include <memory>
#include <string>

#include "utils.h"

namespace {

constexpr UINT kWaveHeaderSize = static_cast<UINT>(sizeof(WAVEHDR));

std::string AudioDevices() {
  std::string inputs;
  std::string outputs;
  for (UINT index = 0; index < waveInGetNumDevs(); ++index) {
    WAVEINCAPSW device{};
    if (waveInGetDevCapsW(index, &device, static_cast<UINT>(sizeof(device))) == MMSYSERR_NOERROR) {
      if (!inputs.empty()) inputs += ", ";
      inputs += Utf8FromUtf16(device.szPname);
    }
  }
  for (UINT index = 0; index < waveOutGetNumDevs(); ++index) {
    WAVEOUTCAPSW device{};
    if (waveOutGetDevCapsW(index, &device, static_cast<UINT>(sizeof(device))) == MMSYSERR_NOERROR) {
      if (!outputs.empty()) outputs += ", ";
      outputs += Utf8FromUtf16(device.szPname);
    }
  }
  return "Entradas: " + (inputs.empty() ? "nenhuma" : inputs) +
         "\nSaídas: " + (outputs.empty() ? "nenhuma" : outputs);
}

}  // namespace

AudioDiagnostic::AudioDiagnostic(flutter::BinaryMessenger* messenger)
    : channel_(messenger, "com.projetonix.nix/audio_diagnostic",
               &flutter::StandardMethodCodec::GetInstance()) {
  channel_.SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "devices") {
          result->Success(flutter::EncodableValue(AudioDevices()));
        } else if (call.method_name() == "start") {
          if (capture_) {
            result->Error("MIC_BUSY", "Já existe um teste de microfone.");
          } else if (Start()) {
            result->Success();
          } else {
            result->Error("MIC_UNAVAILABLE",
                          "Verifique o microfone e as permissões de áudio do Windows.");
          }
        } else if (call.method_name() == "level") {
          ReadLevel(*result);
        } else if (call.method_name() == "stop") {
          Stop();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

AudioDiagnostic::~AudioDiagnostic() {
  channel_.SetMethodCallHandler(nullptr);
  Stop();
}

bool AudioDiagnostic::Start() {
  WAVEFORMATEX format{};
  format.wFormatTag = WAVE_FORMAT_PCM;
  format.nChannels = 1;
  format.nSamplesPerSec = 16000;
  format.wBitsPerSample = 16;
  format.nBlockAlign = 2;
  format.nAvgBytesPerSec = 32000;
  if (waveInOpen(&capture_, WAVE_MAPPER, &format, 0, 0, CALLBACK_NULL) !=
      MMSYSERR_NOERROR) {
    capture_ = nullptr;
    return false;
  }

  for (auto& buffer : buffers_) {
    buffer.header.lpData = reinterpret_cast<LPSTR>(buffer.samples.data());
    buffer.header.dwBufferLength = static_cast<DWORD>(sizeof(buffer.samples));
    if (waveInPrepareHeader(capture_, &buffer.header, kWaveHeaderSize) !=
            MMSYSERR_NOERROR ||
        waveInAddBuffer(capture_, &buffer.header, kWaveHeaderSize) !=
            MMSYSERR_NOERROR) {
      Stop();
      return false;
    }
  }
  if (waveInStart(capture_) == MMSYSERR_NOERROR) return true;
  Stop();
  return false;
}

void AudioDiagnostic::ReadLevel(
    flutter::MethodResult<flutter::EncodableValue>& result) {
  if (!capture_) {
    result.Error("MIC_STOPPED", "A captura de microfone encerrou.");
    return;
  }
  int peak = -1;
  for (auto& buffer : buffers_) {
    if (!(buffer.header.dwFlags & WHDR_DONE)) continue;
    const auto count = std::min(buffer.samples.size(),
        static_cast<size_t>(buffer.header.dwBytesRecorded / sizeof(std::int16_t)));
    for (size_t index = 0; index < count; ++index) {
      peak = std::max(peak, std::abs(static_cast<int>(buffer.samples[index])));
    }
    if (waveInAddBuffer(capture_, &buffer.header, kWaveHeaderSize) !=
        MMSYSERR_NOERROR) {
      Stop();
      result.Error("MIC_STOPPED", "O dispositivo encerrou a captura.");
      return;
    }
  }
  if (peak < 0) {
    result.Success();
  } else {
    result.Success(flutter::EncodableValue(peak / 32768.0));
  }
}

void AudioDiagnostic::Stop() {
  if (!capture_) return;
  waveInReset(capture_);
  for (auto& buffer : buffers_) {
    if (buffer.header.dwFlags & WHDR_PREPARED) {
      waveInUnprepareHeader(capture_, &buffer.header, kWaveHeaderSize);
    }
    buffer.header = {};
    SecureZeroMemory(buffer.samples.data(), sizeof(buffer.samples));
  }
  waveInClose(capture_);
  capture_ = nullptr;
}
