# Cliente Windows x64

O runner Flutter nativo está em `apps/nix_client/windows`. O workflow manual **Nix pilot builds** configura MSVC e OpenSSL no runner Windows, compila em release e produz um ZIP com o executável, as DLLs, os assets, a licença e o Tor Expert Bundle. O código usa `%LOCALAPPDATA%\Projeto Nix` (alternativa `%USERPROFILE%\AppData\Local\Projeto Nix`) para armazenamento. O cofre exige SQLCipher real. O cliente carrega a DLL pelo caminho absoluto junto ao executável. O Credential Manager usa uma credencial por usuário, com a mesma opção de desbloqueio por frase-passe do cliente.

A versão Windows 16.0.1 do Tor Expert Bundle foi verificada localmente pela assinatura OpenPGP do Tor Browser Developers. Fingerprint da chave principal `EF6E286DDA85EA2A4BA7DE684E2C6E8793298290`. O workflow exige o SHA-256 do artefato autenticado. O cliente procura `tor/tor.exe` junto ao executável e usa um diretório de dados por usuário. O restante do bootstrap e o bloqueio de tráfego direto seguem o transporte comum do Nix. [Distribuição oficial](https://dist.torproject.org/torbrowser/16.0.1/)

| Requisito | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| Runner, SQLCipher e distribuição | `windows/`, `pilot-builds.yml` | Cliente x64 nativo e ZIP do piloto | Build, abertura de cofre cifrado e abertura de processo no job Windows | VERIFIED_WINDOWS | Aceite de uso em Windows e ARM64 requer execução dedicada. |
| Cofre nativo | `windows_credential_storage.dart` | Credential Manager via FFI | `windows_credential_storage_test.dart` | VERIFIED_WINDOWS | Teste requer Windows. |
| Transporte | `nix_embedded_tor.dart`, `pilot-builds.yml` | Tor empacotado, caminho em diretório do usuário e fail-closed | Assinatura OpenPGP do bundle e teste de `torrc` isolado | VERIFIED_LOCAL | Bootstrap e conversa real em Windows aguardam homologação. |
| Áudio | `windows/runner/audio_diagnostic.cpp` | Enumera entrada e saída e mede PCM em memória | Diagnóstico do dispositivo no cliente | PARTIAL | Captura em hardware, player e gravação de mensagem aguardam homologação. |
| Instalação | `pilot-builds.yml` | ZIP e SHA-256 | Artefato do job | PARTIAL | Instalador, assinatura Authenticode e atualizador foram deixados pendentes. |

O [piloto da revisão `2aa9cd7`](https://github.com/foros049695/nix/actions/runs/44800654122) concluiu os dois testes do runtime Windows e gerou o pacote x64.
