#include "audio_diagnostic.h"

#include <algorithm>
#include <cstdlib>
#include <memory>
#include <string>
#include <utility>

#include "utils.h"

namespace {

constexpr UINT kWaveHeaderSize = static_cast<UINT>(sizeof(WAVEHDR));

WAVEFORMATEX VoiceFormat() {
  WAVEFORMATEX format{};
  format.wFormatTag = WAVE_FORMAT_PCM;
  format.nChannels = 1;
  format.nSamplesPerSec = 16000;
  format.wBitsPerSample = 16;
  format.nBlockAlign = 2;
  format.nAvgBytesPerSec = 32000;
  return format;
}

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
        } else if (call.method_name() == "callStart") {
          if (!capture_ && Start()) {
            in_call_ = true;
            result->Success();
          } else {
            result->Error("MIC_UNAVAILABLE", "Microfone ocupado ou indisponível.");
          }
        } else if (call.method_name() == "callRead") {
          std::vector<std::uint8_t> pcm;
          if (in_call_ && ReadSamples(pcm)) {
            result->Success(flutter::EncodableValue(std::move(pcm)));
          } else {
            result->Error("MIC_STOPPED", "O microfone da chamada foi interrompido.");
          }
        } else if (call.method_name() == "callStopInput") {
          if (in_call_) Stop();
          result->Success();
        } else if (call.method_name() == "callPlay") {
          const auto* args = call.arguments();
          const auto* pcm = args ? std::get_if<std::vector<std::uint8_t>>(args) : nullptr;
          if (pcm && PlayCall(*pcm)) {
            result->Success();
          } else {
            result->Error("SPEAKER_UNAVAILABLE", "Saída de áudio indisponível.");
          }
        } else if (call.method_name() == "callStopOutput") {
          StopPlayback();
          result->Success();
        } else if (call.method_name() == "level") {
          if (in_call_) {
            result->Error("MIC_BUSY", "Microfone em uso pela chamada.");
          } else {
            ReadLevel(*result);
          }
        } else if (call.method_name() == "stop") {
          if (!in_call_) Stop();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

AudioDiagnostic::~AudioDiagnostic() {
  channel_.SetMethodCallHandler(nullptr);
  Stop();
  StopPlayback();
}

bool AudioDiagnostic::Start() {
  auto format = VoiceFormat();
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

bool AudioDiagnostic::ReadSamples(std::vector<std::uint8_t>& pcm) {
  if (!capture_) return false;
  for (size_t index = 0; index < buffers_.size(); ++index) {
    auto& buffer = buffers_[next_input_];
    if (!(buffer.header.dwFlags & WHDR_DONE)) break;
    next_input_ = (next_input_ + 1) % buffers_.size();
    const auto count = std::min(sizeof(buffer.samples),
        static_cast<size_t>(buffer.header.dwBytesRecorded));
    const auto* bytes = reinterpret_cast<const std::uint8_t*>(buffer.samples.data());
    pcm.insert(pcm.end(), bytes, bytes + count - count % 2);
    SecureZeroMemory(buffer.samples.data(), sizeof(buffer.samples));
    if (waveInAddBuffer(capture_, &buffer.header, kWaveHeaderSize) !=
        MMSYSERR_NOERROR) {
      Stop();
      return false;
    }
  }
  return true;
}

void AudioDiagnostic::ReadLevel(
    flutter::MethodResult<flutter::EncodableValue>& result) {
  std::vector<std::uint8_t> pcm;
  if (!ReadSamples(pcm)) {
    result.Error("MIC_STOPPED", "O dispositivo encerrou a captura.");
    return;
  }
  if (pcm.empty()) {
    result.Success();
    return;
  }
  int peak = 0;
  for (size_t i = 0; i + 1 < pcm.size(); i += 2) {
    const auto word = pcm[i] | (pcm[i + 1] << 8);
    const int sample = word >= 32768 ? word - 65536 : word;
    peak = std::max(peak, std::abs(sample));
  }
  SecureZeroMemory(pcm.data(), pcm.size());
  result.Success(flutter::EncodableValue(peak / 32768.0));
}

bool AudioDiagnostic::PlayCall(const std::vector<std::uint8_t>& pcm) {
  if (pcm.empty() || pcm.size() > playback_buffers_[0].bytes.size() ||
      pcm.size() % 2 != 0) return false;
  if (!playback_) {
    auto format = VoiceFormat();
    if (waveOutOpen(&playback_, WAVE_MAPPER, &format, 0, 0, CALLBACK_NULL) !=
        MMSYSERR_NOERROR) {
      playback_ = nullptr;
      return false;
    }
  }
  for (auto& buffer : playback_buffers_) {
    if (buffer.header.dwFlags & WHDR_PREPARED) {
      if (!(buffer.header.dwFlags & WHDR_DONE)) continue;
      if (waveOutUnprepareHeader(playback_, &buffer.header, kWaveHeaderSize) !=
          MMSYSERR_NOERROR) return false;
    }
    SecureZeroMemory(buffer.bytes.data(), buffer.bytes.size());
    std::copy(pcm.begin(), pcm.end(), buffer.bytes.begin());
    buffer.header = {};
    buffer.header.lpData = reinterpret_cast<LPSTR>(buffer.bytes.data());
    buffer.header.dwBufferLength = static_cast<DWORD>(pcm.size());
    if (waveOutPrepareHeader(playback_, &buffer.header, kWaveHeaderSize) !=
        MMSYSERR_NOERROR ||
        waveOutWrite(playback_, &buffer.header, kWaveHeaderSize) !=
        MMSYSERR_NOERROR) {
      StopPlayback();
      return false;
    }
    return true;
  }
  return true;
}

void AudioDiagnostic::StopPlayback() {
  if (!playback_) return;
  waveOutReset(playback_);
  for (auto& buffer : playback_buffers_) {
    if (buffer.header.dwFlags & WHDR_PREPARED) {
      waveOutUnprepareHeader(playback_, &buffer.header, kWaveHeaderSize);
    }
    buffer.header = {};
    SecureZeroMemory(buffer.bytes.data(), buffer.bytes.size());
  }
  waveOutClose(playback_);
  playback_ = nullptr;
}

void AudioDiagnostic::Stop() {
  in_call_ = false;
  next_input_ = 0;
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
