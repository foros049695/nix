# Diagnóstico de áudio

Abra **Configurações → Som e microfone → Iniciar teste**. A ação inicia a leitura do microfone padrão em memória. O medidor aparece após a primeira amostra válida. O teste descarta o áudio, encerra a captura ao sair e informa problemas de permissão ou perda do dispositivo.

| Plataforma | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| Android | `MainActivity.kt`, `NixAudioDiagnostic.kt` | Permissão `RECORD_AUDIO`, `AudioManager` e `AudioRecord` | Build nativo e teste de interface | IMPLEMENTED | Aceite requer dispositivo com microfone. |
| Linux | `microphone_test_card.dart` | Rotas via `pactl`, PCM ao vivo via `parec` | Build e teste de interface Flutter | IMPLEMENTED | Requer utilitários PulseAudio e servidor PulseAudio ou PipeWire compatível. |
| Windows | `windows/runner/audio_diagnostic.cpp` | Dispositivos WinMM e leituras PCM de buffers nativos | Build Windows | IMPLEMENTED | Aceite requer dispositivo com microfone. |

Preferências de volume e filtros já armazenadas foram preservadas. A página de diagnóstico mostra dispositivos detectados e mede o nível real de entrada. O Android oferece notas de voz em conversas diretas cifradas. A escolha de rota dentro do Nix, o processamento de eco e ruído, a gravação no desktop e o transporte de chamadas continuam pendentes. [Voz e formatação](MESSAGING_AND_MEDIA_INTEGRATION.md#voz-e-formatação)
