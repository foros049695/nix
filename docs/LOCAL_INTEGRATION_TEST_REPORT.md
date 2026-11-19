# Relatório de Testes Locais e Integração — Projeto Nix

**Data de execução:** 19/11/2026  
**Commit base auditado:** `115f3894b3f9d08609c95bc4b5c85b2bb1417038`  
**Ambiente:** Linux x86_64 · Flutter/Dart SDK local · Go 1.23 · SQLCipher `4.10.0` (`libsqlcipher_flutter_libs_plugin.so`) + SQLite comum (`libsqlite3.so.0.8.6`) para teste negativo · `$HOME` temporário isolado em todos os testes destrutivos do cliente.

---

## 1. Resumo Consolidado das Execuções

| Camada / Suíte | Comando Executado | Resultado | Contagem | Observações |
|---|---|---|---:|---|
| **Portão Estático de Privacidade** | `./scripts/verify_privacy_matrix.sh` | ✅ PASS | 3/3 gates | L-S (zero SDKs/telemetria), I-S (zero captura de IP em `.go`), I-A (zero permissões civis em `AndroidManifest.xml`). |
| **Relay Go (`services/nix_relay`)** | `go vet ./... && go test -race ./...` | ✅ PASS | `cmd/relay` + `internal/buffer` | 0 data races; erros de persistência propagados (`ErrPersistence`); limite dinâmico HTTP 413; expansão de `~`; histerese `AutoPruner`. |
| **Core Criptográfico (`modules/core_crypto`)** | `dart analyze --fatal-infos && dart test` | ✅ PASS | 10/10 | 0 issues no analyzer; Ed25519/X25519, AEAD, Argon2id, X3DH, Double Ratchet atômico pré-commit, `ReplayGuard`, `PqxdhCombiner`, `SignedReleaseManifest`. |
| **Transporte (`modules/transport`)** | `dart analyze --fatal-infos && dart test` | ✅ PASS | 22/22 | 0 issues no analyzer; **Issue `#11`** (TLS nativo `RawSecureSocket` sobre SOCKS5, rejeição de cert inválido, DNS remoto, `UnsupportedTransportSchemeException`), `EmbeddedTorManager` isolado, Bluetooth Mesh `NIXB`, Radio Off-Grid `<=240B`. |
| **Cliente Flutter (`apps/nix_client`) — Analyzer** | `flutter analyze --no-fatal-infos` | ✅ PASS | 0 erros, 0 warnings | Apenas diagnósticos informativos (`prefer_const_constructors` / `deprecated_member_use`) pré-existentes. |
| **Cliente Flutter (`apps/nix_client`) — Suíte Completa** | `HOME="$TMP_HOME" FLUTTER_TEST=true flutter test` | ✅ PASS | 97/97 | Inclui todas as suítes legadas + `transactional_messaging_fault_test.dart` (6), `audit_integration_verification_test.dart` (12), `plain_sqlite_rejection_probe_test.dart` (1) e `security_startup_gate_and_radio_test.dart` (8). |
| **Build Desktop Linux + Tor Embutido** | `flutter build linux --release && ./scripts/bundle_tor_linux.sh` | ✅ PASS | Bundle completo | `nix_client`, `libapp.so`, `libsqlcipher_flutter_libs_plugin.so` e `tor` 0.4.9.15 (`--verify-config` válido). |
| **Build Android APK Universal (NDK)** | `flutter build apk --release` (`minSdk 24`, `targetSdk 35`) | ✅ PASS | 52 MB (4 ABIs) | Verificados no APK: `lib/*/libtor.so` (0.4.8.17.2), `lib/*/libsqlcipher.so`, `MainActivity.kt` (TEE/StrongBox), `NixBleMeshController.kt` (GATT), `NixRNodeRadioController.kt` (USB-OTG/BLE KISS), `allowBackup=false`, `network_security_config.xml`. |

---

## 2. Cobertura Detalhada por Fase da Auditoria

### Fase 2 — Issues `#11`, `#12` e PRs `#1`–`#10`, `#13`–`#18`
- **Issue `#11`:** `modules/transport/test/https_over_socks_probe_test.dart` executado dentro de `dart test` (22/22). Confirmado handshake TLS sobre SOCKS5 sem fallback clearnet, rejeição de certificado não confiável e bloqueio de esquemas inválidos.
- **Issue `#12`:** Consulta autenticada à API GitHub retornou `HTTP 200 {"enabled": true}` para Private Vulnerability Reporting; coerência confirmada com `SECURITY.md` e `docs/INCIDENT_RESPONSE.md`.
- **PRs `#1`–`#10`, `#13`–`#18`:** Todos os 16 PRs integrados verificados sem regressões (detalhes completos em `docs/PR_ISSUE_VERIFICATION.md`).

### Fase 3 — Integração Real da Mensageria (`NixState` + `SovereignMessenger` + UI)
- **Teste:** `apps/nix_client/test/transactional_messaging_fault_test.dart` (grupo Fase 3).
- **Cenários verificados:**
  1. Duas instâncias totalmente independentes de `NixState` (`aliceState` e `bobState`), cada qual com seu próprio `KeyVault`, `LocalDatabase` SQLCipher e diretório temporário, comunicando-se através de um **servidor HTTP relay cego local e proxy SOCKS5 em loopback** sob política `TransportMode.torFailClosed`.
  2. Diferenciação explícita de **Mensagens Salvas** (`deliveryState: 'saved'`, nunca vai para `outbox` nem relay) vs conversas privadas remotas.
  3. Tentativa de envio remoto **sem sessão criptográfica Double Ratchet**: marcada como `deliveryState: 'failed'`, `isVerified: false`, expondo `lastMessagingError` (nenhuma mensagem marcada como entregue/autenticada em memória).
  4. Handshake assinado (`exportLocalSignedCardJson` → `importPeerCardAndEstablishSession`), envio via `NixState.sendDirectMessage()` (`queued` → `accepted`), recepção via `NixState.syncWithRelay()` (`delivered`, `isVerified: true`) e resposta bidirecional de Bob para Alice.
  5. **Recuperação após reinicialização:** envio durante queda simulada do relay (`HTTP 503` → `failed`), encerramento (`dispose()`) de `aliceState`, abertura de nova instância `aliceRestarted` com `unlockWithPassphrase`, restauração da mensagem pendente na UI, retorno do relay e conclusão da entrega em Bob.

### Fase 4 — Consistência Transacional da Criptografia (Injeção de Falhas)
- **Teste:** `apps/nix_client/test/transactional_messaging_fault_test.dart` (grupo Fase 4).
- **Todos os 6 estágios exigidos foram injetados e verificados:**
  1. `beforeSessionSave` → rollback atômico (revisão da sessão inalterada, 0 mensagens, 0 itens na outbox; mensagem seguinte decifra em Bob).
  2. `afterSessionSave` → rollback atômico da transação SQLite (sessão não avança; ratchet sincronizado com Bob).
  3. `afterMessageInsert` → rollback atômico de `sessions` + `messages` + `outbox`.
  4. `duringOutboxInsert` → rollback atômico completo; nenhuma perda silenciosa nem avanço de ratchet.
  5. `duringRelaySend` → outbox e mensagem transitam atomicamente para `failed` (`attempts` incrementado); retentativa subsequente reenvia o mesmo `ciphertext` e confirma `accepted`.
  6. `afterRemoteAcceptBeforeLocalConfirm` → após HTTP `202` do relay e crash antes do commit local, retentativa reenvia o envelope e Bob deduplica o segundo envelope pré-ratchet via `wireMsgId` (`skippedDuplicateCount == 1`, `committed.length == 1`, `errors.isEmpty`).

### Fase 5 — SQLCipher e KeyVault
- **Testes:** `apps/nix_client/test/audit_integration_verification_test.dart` (Fase 5) + `test/plain_sqlite_rejection_probe_test.dart` + `test/milestone_b_security_test.dart` + `test/local_database_probe_test.dart`.
- **Cenários verificados:**
  1. **SQLCipher real (`4.10.0`):** `cipherInfo.isEncrypted == true`, cabeçalho do arquivo `.db` não começa com `SQLite format 3`, string confidencial inserida não aparece em texto claro nos bytes brutos em disco, abertura com chave incorreta falha na verificação HMAC de página.
  2. **SQLite comum (`libsqlite3.so.0`):** mesmo fornecendo `rawCipherKey` válida de 32 bytes, `LocalDatabase.open(..., requireEncryption: true)` rejeita com `StateError('[Fail-Closed] SQLCipher obrigatório...')` e remove o arquivo recém-criado.
  3. **Ausência de frase-passe padrão:** `NixState.initializeEncryptedDatabase` exige `required String passphrase` e recusa string vazia.
  4. **Backup e restauração cifrados do KeyVault:** `exportEncryptedBackupBundle` não contém frase-passe em claro; `importEncryptedBackupBundle` rejeita senha incorreta e restaura a mesma masterKey de 32 bytes com a senha correta.

### Fase 6 — Onboarding e Tor
- **Teste:** `apps/nix_client/test/audit_integration_verification_test.dart` (Fase 6) + `test/clean_onboarding_and_real_messenger_test.dart`.
- **Cenários verificados:**
  1. `completeOnboarding()` bloqueia conclusão indevida (`StateError`) em modo produção quando nenhuma identidade Seed A foi inicializada.
  2. `verifyTorTransportAndFailClosed()` testa ativamente o bloqueio clearnet na `TransportPolicy.torFailClosed` e diferencia porta SOCKS5 fechada (`socksActive: false`) de proxy SOCKS5 local ativo (`socksActive: true`).
  3. `OnboardingStateSnapshot.save` usa escrita atômica `.tmp + renameSync` sem deixar temporários residuais.
  4. `SovereignOnboardingFlow` renderiza sem overflow em `800x600` e `1440x900`.

### Fase 7 — Mercado Monero P2P
- **Teste:** `apps/nix_client/test/audit_integration_verification_test.dart` (Fase 7) + `test/widget_test.dart`.
- **Cenários verificados:** assinatura Ed25519 real com chave isolada da Seed A (`order.traderPublicId != messagingIdentity.publicId`), rejeição de preço `<= 0` e `max < min`, detecção de adulteração de preço, expiração, anti-replay de nonce em ordem distinta, persistência em SQLCipher após reinício e ausência do saldo fictício `4.825 XMR`.

### Fase 8 — Anexos, Grupos e Arquivos
- **Teste:** `apps/nix_client/test/audit_integration_verification_test.dart` (Fase 8) + `test/gate3_two_client_e2ee_test.dart`.
- **Cenários verificados:** seleção portável via `ProgrammableFilePickerAdapter` (sem `zenity`/`kdialog`), cancelamento cooperativo de `prepareEncryptedAttachment` com limpeza automática de chunks no disco e no SQLite, `cleanupTemporaryStagingFiles`, rotação de época de Sender Keys em `applyAdminAction` (`kick`/`ban`) e bloqueio de `sendMessage` para membros silenciados/banidos.

### Fase 9 — Archive, Media Catalog, GitHub Discovery e APK Offline
- **Teste:** `apps/nix_client/test/audit_integration_verification_test.dart` (Fase 9).
- **Cenários verificados:**
  - **9.1 Archive:** sanitização determinística contra 8 vetores adversariais XSS (incluindo entidades hex/decimais `java&#x09;script:`, tags não fechadas, comentários, `svg/onload`, `img/onerror`), fluxo completo criar → editar (`supersedes`) → refutar → verificar assinatura Ed25519/SHA-256 → histórico de revisões.
  - **9.2 Media Catalog:** busca local FTS5 (`searchCulturalCatalog`), bloqueio de conectores opt-in desabilitados (`StateError`), bloqueio fail-closed sem Tor SOCKS5 (`TorrentClearnetLeakBlockedException`) e execução autorizada com cache local quando habilitado sob circuito Tor.
  - **9.3 GitHub Discovery:** `enforceStarwireDownloadTransport(strictTorMode: true, allowClearnetBypass: true)` lança `TransportBlockedException`, bloqueio de clearnet `github.com` sob `torFailClosed`, validação contra path traversal em ZIP e persistência de favoritos após reinicialização.
  - **9.4 Offline APK Share:** verificação Ed25519 via `SignedReleaseManifest` aceita pacote assinado, rejeita pacote adulterado, rejeita chave de publicador não confiável e valida transferência HTTP local real (`/nix.apk` + `/nix.apk.sig.json`) via `ShareAppOfflineDialog.downloadAndVerifyFromPeer`.

---

## 3. Escudo Fail-Closed de Inicialização, Modo Off-Grid Estrito e Drivers Nativos Android

- **Teste:** `apps/nix_client/test/security_startup_gate_and_radio_test.dart` (8/8).
- **Cenários verificados localmente:**
  1. `NixFailClosedHttpOverrides` bloqueia conexões HTTP/HTTPS diretas pela rede doméstica (`TransportBlockedException`) e permite apenas loopback `127.0.0.1`.
  2. `AppShell` em modo produção (`enforceStartupGate: true`) bloqueia a entrada sem Tor Onion v3 100% operacional + todas as camadas criptográficas (SQLCipher + KeyVault + Seed A).
  3. **Modo Off-Grid Estrito (BLE / LoRa · Zero Internet):** `NixState.enterStrictOffGridMode()` mantém o firewall HTTP anti-clearnet ativo, desativa `syncWithRelay()`, Starwire e conectores remotos (`TransportBlockedException`), continua exigindo SQLCipher + KeyVault + Seed A e libera o onboarding offline e a comunicação local via Bluetooth BLE (`NIXB`) e Rádio LoRa (`NX` KISS).
  4. `KissFrameCodec` + `RadioPacketCodec` (`<= 240B`, CRC16-CCITT) + `BluetoothMeshManager.onTransmitPacket` verificados localmente em memória/enquadramento (sem simular transmissão de rádio físico).

---

## 4. Limitações de Laboratório Local e Itens Ainda Não Testados em Hardware Físico

Os itens abaixo **permanecem classificados como `UNVERIFIED` / pendentes de validação em hardware real**:
1. Operação contínua e soak test de 60 minutos em **VPS externa Debian 13** com Onion Service v3 real.
2. **Onboarding + SQLCipher + AndroidKeyStore TEE/StrongBox** em execução nos dois celulares Android físicos (criação de Seed A com frase-passe vazia e verificação de vínculo automático no TEE após reinicialização).
3. **Bluetooth BLE Físico (`NIXB`)** entre os dois celulares Android reais (descoberta via GATT/Advertising e entrega bidirecional pelo ar).
4. **Rádio LoRa / Reticulum RNode físico:** validado apenas o enquadramento local `NX` (CRC16-CCITT válido e framing KISS) sem transceptor LoRa físico conectado.
5. Liquidação financeira real contra **`monero-wallet-rpc`** em `stagenet`/`mainnet`.
