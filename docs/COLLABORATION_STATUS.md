# 📋 STATUS DE COLABORAÇÃO TÉCNICA E AUDITORIA DE PRs / ISSUES
## Projeto Nix — Governança e Relatório Contínuo de Integração

**Data da verificação:** 19 de Novembro de 2026  
**Commit base anterior (`origin/main` antes dos merges):** `742533cadd3ef9a2468597fbafd74f33153d2295`  
**Commits principais na `main`:** `8618b79`..`1799597` (`#1`–`#10`), `1dea5f3` (Fases 0–9), `807e93b`..`f2effa4` (`#13`–`#18`), `1b21f65`  
**Escopo:** Auditoria Técnica de Contribuições, CI e Integração  
**Contribuidores ativos:** @foros049695 (Proprietário), @gabrielmaialva33 (Colaborador)

---

## 1. RESUMO EXECUTIVO DO ESTADO DO PROJETO

| Categoria | Quantidade | Observações |
|---|:---:|---|
| **Pull Requests Abertos** | 0 | PRs #1 a #18 totalmente integrados na branch `main` (últimos merges: `#13`–`#18`) |
| **Pull Requests Integrados** | 16 (do #1 ao #10 + #13 ao #18; sem #11/#12 pois eram Issues) | PRs `#1`–`#10` + implementação Fases 0–9 (`1dea5f3`) + PRs `#13`–`#18` (`807e93b`–`f2effa4`) |
| **Issues Rastreáveis** | 2 resolvidas e encerradas | **Issue #11** (TLS real sobre SOCKS5, fechada em `completed`) · **Issue #12** (PVR ativo, fechada) |
| **GitHub Actions Remoto** | ✅ GREEN em `1b21f65` (Run `44464220218`) | Todos os 5 jobs verdes (`Privacy`, `Flutter Client`, `Relay Go`, `Transport`, `Core Crypto`) |
| **Suites Locais Combinadas** | ✅ 100% GREEN (Pós-Auditoria Local) | Privacy gate (3/3), Relay Go (`vet` + `test -race`), Crypto (`10/10`), Transport (`22/22` incl. Issue `#11`), Client (`89/89` com SQLCipher `4.10.0`, rejeição de SQLite comum `libsqlite3.so.0`, injeção de falhas em 6 estágios e `$HOME` isolado). Ver `docs/LOCAL_INTEGRATION_TEST_REPORT.md` e `docs/PR_ISSUE_VERIFICATION.md`. |

---

## 2. DIAGNÓSTICO DAS FALHAS DO GITHUB ACTIONS (CI PIPELINE)

Ao auditar as execuções de CI (`.github/workflows/ci.yml`) nas branches dos PRs #2 a #10, identificou-se o motivo exato de todos os PRs apresentarem status vermelho no GitHub:

1. **Dependência Cruzada de Analisadores:**
   - O pipeline do GitHub executa cinco jobs obrigatórios:
     - `Privacy & Security Gate Check` (`./scripts/verify_privacy_matrix.sh`)
     - `Relay Go Lint & Test` (`go vet` e `go test -race`)
     - `Core Crypto Dart Analyze & Test` (`dart analyze --fatal-infos` e `dart test`)
     - `Transport Dart Analyze & Test` (`dart analyze --fatal-infos` e `dart test`)
     - `Flutter Client Analyze & Test` (`flutter pub get`, `flutter analyze` e `flutter test`)
2. **Isolamento de Branches dos PRs:**
   - **PR #2** corrigiu apenas os analisadores estritos de Dart em `core_crypto` e `transport`, mas a branch não continha a correção dos `infos` do Flutter Client (que falhava por padrão do Flutter estável tratando info como fatal). Resultado no CI: `Flutter Client Analyze & Test` falhou.
   - **PR #3** corrigiu o Flutter Client (`--no-fatal-infos`, `Material` em `ListTile`s, `CardThemeData`), mas foi gerado a partir de `742533c` sem as correções do PR #2 em `core_crypto` e `transport`. Resultado no CI: `Core Crypto` e `Transport` falharam.
   - **PRs #4 a #10** foram todos ramificados a partir do commit base `742533c`, sem conter simultaneamente as correções de #2 e #3. Por isso, todos falharam no CI em pelo menos um dos jobs Dart/Flutter.
3. **Comprovação Empírica de Compatibilidade:**
   - Ao integrar a base de #2 e #3 em conjunto com os demais PRs, **todas as cinco verificações equivalentes do CI passaram com 100% de sucesso localmente** (`./scripts/verify_privacy_matrix.sh`, `go vet` + `go test -race`, `dart analyze --fatal-infos` + `dart test` em ambos os módulos e `flutter analyze --no-fatal-infos` + `flutter test`). Não há incompatibilidade de código; tratava-se apenas de dependência de base entre os PRs.

---

## 3. PARECER TÉCNICO INDIVIDUAL POR PULL REQUEST

### 🔹 Pull Request #2
- **Título:** `fix(crypto,transport): resolve strict analyzer errors blocking CI`
- **Branch / Head PR:** `origin/pr/2` (`5682e47`) → **Merge:** `8618b79`
- **Autor:** @gabrielmaialva33
- **Arquivos modificados:**
  - `modules/core_crypto/lib/nix_core_crypto.dart`
  - `modules/transport/lib/nix_transport.dart`
- **Análise Técnica:**
  - Corrige erros e alertas de tipagem estrita nos módulos Dart puros (`dart analyze --fatal-infos`).
  - Ajusta anotações de biblioteca e tratamento de streams.
- **Risco de Regressão:** Zero. Preserva toda a lógica criptográfica e contratos de transporte.
- **Testes Executados após Merge:** `cd modules/core_crypto && dart analyze --fatal-infos && dart test` (8/8 passaram), `cd modules/transport && dart analyze --fatal-infos && dart test` (19/19 passaram, já incluindo probe da Issue #11).
- **Parecer:** `ALREADY_INTEGRATED` (`8618b79`). Desbloqueador essencial da camada Dart no CI.

---

### 🔹 Pull Request #3
- **Título:** `fix(client): restore green Flutter analyze and tests on current stable`
- **Branch / Head PR:** `origin/pr/3` (`743d7fd`) → **Merge:** `f54b857`
- **Autor:** @gabrielmaialva33
- **Arquivos modificados:**
  - `.github/workflows/ci.yml`
  - `apps/nix_client/lib/core/security/anti_forensic_shredder.dart`
  - `apps/nix_client/lib/core/security/key_vault.dart`
  - `apps/nix_client/lib/core/theme.dart`
  - `apps/nix_client/lib/features/home/home_sidebar.dart`
  - `apps/nix_client/lib/features/navigation/channels_sidebar.dart`
  - `apps/nix_client/lib/features/onboarding/sovereign_onboarding_flow.dart`
  - `apps/nix_client/lib/features/settings/settings_center.dart`
  - `apps/nix_client/test/database_and_vault_test.dart`
- **Análise Técnica:**
  - Atualiza `.github/workflows/ci.yml` para usar `flutter analyze --no-fatal-infos`.
  - Atualiza `CardTheme` e `DialogTheme` para `CardThemeData` e `DialogThemeData` (APIs modernas do Flutter).
  - Envolve `ListTile`s em containers `Material(type: MaterialType.transparency)` na sidebar e configurações, eliminando asserções silenciosas de layout.
  - Remove imports não utilizados.
- **Risco de Regressão:** Baixo. Melhora estabilidade da árvore de widgets.
- **Testes Executados após Merge:** `flutter analyze --no-fatal-infos` (0 erros, 0 warnings; 100 infos existentes), `flutter test` em ambiente isolado (48/48 passaram em duas rodadas consecutivas).
- **Parecer:** `ALREADY_INTEGRATED` (`f54b857`). Desbloqueador essencial da camada Flutter no CI.

---

### 🔹 Pull Request #4
- **Título:** `fix(client): confine panicWipeAccount to customBaseDir and overwrite files in place`
- **Branch / Head PR:** `origin/pr/4` (`0a848d3`) → **Merge:** `5d83e77`
- **Autor:** @gabrielmaialva33
- **Dependência:** Depende de #3 (compartilha `anti_forensic_shredder.dart`).
- **Arquivos modificados:**
  - `apps/nix_client/lib/core/security/anti_forensic_shredder.dart`
  - `apps/nix_client/test/helpers/panic_wipe.dart`
  - `apps/nix_client/test/shredder_confinement_probe_test.dart`
- **Análise Técnica:**
  - **Segurança Crítica:** Restringe `panicWipeAccount` quando `customBaseDir` é informado, garantindo que testes ou perfis isolados nunca apaguem acidentalmente `$HOME/.local/share/nix`.
  - Altera a abertura de arquivo para `FileMode.writeOnlyAppend` com `setPosition(0)` durante as passagens de sobregravação, evitando truncamento precoce.
  - Adiciona suíte exaustiva de testes de confinamento e destruição prioritária do bootstrap.
- **Risco de Regressão:** Zero. Aumenta substancialmente a segurança do sistema e dos testes.
- **Testes Executados após Merge:** `test/shredder_confinement_probe_test.dart` aprovado dentro da suíte completa (48/48), comprovando dados reais em `~/.local/share/nix` intactos.
- **Parecer:** `ALREADY_INTEGRATED` (`5d83e77`).

---

### 🔹 Pull Request #5
- **Título:** `fix(transport): isolate Tor port probes and terminate children on bootstrap timeout`
- **Branch / Head PR:** `origin/pr/5` (`537d653`) → **Merge:** `c7dd88d`
- **Autor:** @gabrielmaialva33
- **Dependência:** Depende de #2 (módulo `transport`).
- **Arquivos modificados:**
  - `modules/transport/lib/nix_embedded_tor.dart`
  - `modules/transport/test/embedded_tor_isolation_probe_test.dart`
  - `modules/transport/test/embedded_tor_test.dart`
- **Análise Técnica:**
  - Injeta `portProbe` e `processStarter` no construtor de `EmbeddedTorManager`, permitindo testes unitários isolados sem colidir com portas ou daemons Tor ativos.
  - Encerra processos-filhos do Tor em timeout de bootstrap e preserva `LD_LIBRARY_PATH`.
- **Risco de Regressão:** Zero.
- **Testes Executados após Merge:** Incluído nos 19/19 testes aprovados de `modules/transport`.
- **Parecer:** `ALREADY_INTEGRATED` (`c7dd88d`).

---

### 🔹 Pull Request #6
- **Título:** `fix(p0-2): report honest SQLCipher state and enforce migration checksums`
- **Branch / Head PR:** `origin/pr/6` (`08beeb3`) → **Merge:** `7677a0b`
- **Autor:** @gabrielmaialva33
- **Dependência:** Depende de #3.
- **Arquivos modificados:**
  - `apps/nix_client/lib/core/database/local_database.dart`
  - `apps/nix_client/test/local_database_probe_test.dart`
- **Análise Técnica:**
  - **Transparência de Segurança:** Se `PRAGMA cipher_version` retornar nulo/vazio, define honestamente `isEncrypted: false` e motor `SQLite-Development-Clearnet`.
  - Valida fail-closed o checksum SHA-256 de todas as migrações SQL pendentes antes de aplicar alterações no banco.
  - Remove caminho hardcoded de desenvolvimento (`/home/gus/...`).
- **Risco de Regressão:** Baixo.
- **Testes Executados após Merge:** `test/local_database_probe_test.dart` aprovado na suíte do cliente (48/48).
- **Parecer:** `ALREADY_INTEGRATED` (`7677a0b`).

---

### 🔹 Pull Request #7
- **Título:** `fix(relay): propagate persistence errors from fetch, ack and sweep`
- **Branch / Head PR:** `origin/pr/7` (`ce1beb5`) → **Merge:** `4a13daa`
- **Autor:** @gabrielmaialva33
- **Sobreposição:** Compartilha `services/nix_relay/cmd/relay/main.go` com PR #8.
- **Arquivos modificados:**
  - `services/nix_relay/cmd/relay/main.go`
  - `services/nix_relay/cmd/relay/persistence_probe_test.go`
  - `services/nix_relay/internal/buffer/autopruner.go`
  - `services/nix_relay/internal/buffer/probe_test.go`
  - `services/nix_relay/internal/buffer/store.go`
- **Análise Técnica:**
  - Propaga erros de persistência em disco no relay (`ErrPersistence`) retornando HTTP `500 Internal Server Error`, sem vazar caminhos internos.
  - Implementa rollback atômico de cotas/contadores em memória se falhar a persistência em disco.
- **Risco de Regressão:** Baixo.
- **Testes Executados após Merge Combinado (#7 + #8):** `go vet ./...` e `go test -race -count=1 ./...` com Go 1.23.4 aprovados nos pacotes `cmd/relay` e `internal/buffer`.
- **Parecer:** `ALREADY_INTEGRATED` (`4a13daa`).

---

### 🔹 Pull Request #8
- **Título:** `fix(relay): size the request body limit from the attachment cap`
- **Branch / Head PR:** `origin/pr/8` (`fdd8745`) → **Merge:** `f1dffd1`
- **Autor:** @gabrielmaialva33
- **Sobreposição:** Compartilha `services/nix_relay/cmd/relay/main.go` com PR #7.
- **Arquivos modificados:**
  - `services/nix_relay/cmd/relay/attachment_probe_test.go`
  - `services/nix_relay/cmd/relay/main.go`
- **Análise Técnica:**
  - Dimensiona `http.MaxBytesReader` dinamicamente a partir de `MaxAttachmentSizeBytes` + overhead Base64/JSON e rejeita múltiplos objetos JSON concatenados.
- **Risco de Regressão:** Baixo.
- **Testes Executados após Merge Combinado (#7 + #8):** `go vet ./...` e `go test -race -count=1 ./...` com Go 1.23.4 aprovados (`attachment_probe_test.go` verde).
- **Parecer:** `ALREADY_INTEGRATED` (`f1dffd1`).

---

### 🔹 Pull Request #9
- **Título:** `fix(client): strip WebP/GIF metadata and trailing data, fail closed on malformed images`
- **Branch / Head PR:** `origin/pr/9` (`f453cdc`) → **Merge:** `6199fc7`
- **Autor:** @gabrielmaialva33
- **Dependência:** Depende de #3.
- **Arquivos modificados:**
  - `apps/nix_client/lib/core/security/local_image_helper.dart`
  - `apps/nix_client/test/local_image_helper_probe_test.dart`
- **Análise Técnica:**
  - Adiciona remoção completa de metadados e trailing data para JPEG, PNG, WebP e GIF, recusando contêineres malformados (*fail-closed*).
- **Risco de Regressão:** Zero.
- **Testes Executados após Merge:** `test/local_image_helper_probe_test.dart` aprovado na suíte do cliente (48/48).
- **Parecer:** `ALREADY_INTEGRATED` (`6199fc7`).

---

### 🔹 Pull Request #10
- **Título:** `docs: correct AGENTS.md for the current codebase and warn about destructive tests`
- **Branch / Head PR:** `origin/pr/10` (`eff64e3`) → **Merge:** `1799597`
- **Autor:** @gabrielmaialva33
- **Arquivos modificados:**
  - `AGENTS.md`
- **Análise Técnica:**
  - Documenta aviso de isolamento de `$HOME` para testes, corrige detalhes de arquitetura do cliente/transporte/relay e foi atualizado posteriormente em `main` para refletir o tratamento fail-closed da Issue #11.
- **Risco de Regressão:** Zero.
- **Parecer:** `ALREADY_INTEGRATED` (`1799597`).

---

### 🔹 Pull Requests #13 a #18 (Integração de Hardening Adicional — 19/11/2026)

| PR | Título & Escopo | Autor | Parecer |
|---|---|---|---|
| **#13** | `fix(privacy): make the I-A and I-S gate checks enforce what they report` (`scripts/verify_privacy_matrix.sh`: bloqueia `RemoteAddr`, `X-Forwarded-For`, `X-Real-IP` no relay e permissões civis Android) | @gabrielmaialva33 | `ALREADY_INTEGRATED` |
| **#14** | `fix(client): quote FTS5 terms in media search` (`repositories.dart` + `media_search_fts5_probe_test.dart`) | @gabrielmaialva33 | `ALREADY_INTEGRATED` |
| **#15** | `fix(client): release Tor, mesh, database and vault in NixState.dispose` (`nix_state.dart` + `nixstate_dispose_probe_test.dart` + zeroização `_activeMasterKey`) | @gabrielmaialva33 | `ALREADY_INTEGRATED` |
| **#16** | `fix(android): disable automatic backup of app data` (`AndroidManifest.xml`: `allowBackup="false"`, `fullBackupContent="false"`) | @gabrielmaialva33 | `ALREADY_INTEGRATED` |
| **#17** | `chore(dx): remove hardcoded developer paths and expand ~ in relay base_dir` (`.vscode/settings.json`, `relay.local.yaml`, `config.go`, `config_test.go`) | @gabrielmaialva33 | `ALREADY_INTEGRATED` |
| **#18** | `fix(client): sanitize Starwire ZIP filenames against path traversal` (`github_discovery_view.dart` + `starwire_zip_filename_test.dart`) | @gabrielmaialva33 | `ALREADY_INTEGRATED` |

---

## 4. ANÁLISE DETALHADA DAS ISSUES E AÇÕES EXECUTADAS

### ✅ Issue #11 — [BUG] HTTPS over SOCKS fails with NoSuchMethodError (_detachRaw)
- **Autor:** @gabrielmaialva33
- **Módulo:** `modules/transport` (`nix_transport.dart`)
- **Prioridade:** P0 (Interoperabilidade de Transporte)
- **Estado Atual:** **Resolvida em código e testes** (`Socks5Connector.connectRaw` + `RawSecureSocket.secure` em `RelayClient._socksHttp`).
- **Descrição e Solução Executada:**
  - `Socks5Connector.connectRaw` realiza o handshake SOCKS5 (`ATYP 0x03`, zero leak DNS) sobre `dart:io` `RawSocket`, destacando a subscrição controlada via `SocksRawConnection`, permitindo o upgrade nativo `RawSecureSocket.secure` para `https://`.
  - Mantido o bloqueio *fail-closed* contra certificados TLS inválidos por padrão (`onBadCertificate` omitido) e `UnsupportedTransportSchemeException` para qualquer esquema distinto de `http`/`https`.
  - Validado contra servidor `HttpServer.bindSecure` real atrás de proxy SOCKS5 em `modules/transport/test/https_over_socks_probe_test.dart`.

---

### 🛡️ Issue #12 — Request: private channel for security reports (SECURITY.md §3)
- **Autor:** @gabrielmaialva33
- **Módulo:** Governança / Segurança do Repositório
- **Prioridade:** P1
- **Estado Atual:** **Encerrada e atendida** (`enabled: true` no GitHub Private Vulnerability Reporting).
- **Ações Executadas:**
  1. Ativado **GitHub Private Vulnerability Reporting** via API oficial e documentado em `SECURITY.md` e `docs/INCIDENT_RESPONSE.md`.

---

## 5. MATRIZ DE DEPENDÊNCIAS E SOBREPOSIÇÕES

```mermaid
graph TD
    subgraph CI_Foundation["Camada 1: Desbloqueio do CI"]
        PR2["PR #2: Crypto & Transport CI"]
        PR3["PR #3: Flutter Client CI"]
    end

    subgraph Hardening_Client["Camada 2: Hardening do Cliente"]
        PR4["PR #4: Shredder Confinement"]
        PR6["PR #6: SQLCipher & Checksums"]
        PR9["PR #9: Sanitização de Imagens"]
    end

    subgraph Hardening_Transport["Camada 3: Hardening de Transporte"]
        PR5["PR #5: Tor Test Isolation"]
        ISSUE11["Issue #11: Fix HTTPS via SOCKS"]
    end

    subgraph Hardening_Relay["Camada 4: Hardening do Relay (Go)"]
        PR7["PR #7: Relay Persistence Errors"]
        PR8["PR #8: Relay Body Limit"]
    end

    subgraph Docs_Alignment["Camada 5: Documentação & Alinhamento"]
        PR10["PR #10: AGENTS.md Atualizado"]
    end

    PR3 --> PR4
    PR3 --> PR6
    PR3 --> PR9
    PR2 --> PR5
    PR2 --> ISSUE11
    PR7 -.->|Mesmo arquivo: main.go| PR8
    PR2 & PR3 & PR4 & PR5 & PR6 & PR7 & PR8 & PR9 --> PR10
```

---

## 6. ORDEM EXECUTADA DE INTEGRAÇÃO (19/11/2026)

1. **Etapa 1 — Base de CI:** PR #2 (`8618b79`) e PR #3 (`f54b857`) integrados em conjunto via `--no-ff`.
2. **Etapa 2 — Transporte e Tor:** PR #5 (`c7dd88d`).
3. **Etapa 3 — Núcleo do Cliente e Segurança Local:** PR #4 (`5d83e77`), PR #6 (`7677a0b`) e PR #9 (`6199fc7`).
4. **Etapa 4 — Relay Go:** PR #7 (`4a13daa`) e PR #8 (`f1dffd1`) combinados sem conflitos em `cmd/relay/main.go`.
5. **Etapa 5 — Documentação Compartilhada:** PR #10 (`1799597`).
6. **Etapa 6 — Correções P0/Segurança e Estabilização de Testes:**
   - Exceção tipada `UnsupportedTransportSchemeException` e `https_over_socks_probe_test.dart` (Issue #11).
   - Isolamento por `pid` de `nix_test_onboarding_state_$pid.json` em `sovereign_onboarding_model.dart` (elimina race entre processos paralelos no `flutter test`).
   - Ativação do **Private Vulnerability Reporting** + atualização de `SECURITY.md`, `docs/INCIDENT_RESPONSE.md` e `AGENTS.md` (Issue #12).
7. **Etapa 7 — Entrega Completa dos Marcos P0/P1 das Fases 0 a 9:**
   - Issue #11: TLS real `RawSecureSocket` sobre SOCKS5 + verificação SOCKS5 em `TorDiagnostics`.
   - Fase 1: `SQLCipher 4.10.0`, `libsecret`/`AndroidKeyStore`, `SeedRecoveryManager` (24 palavras c/ checksum), `Duress PIN`, carregamento pós-reinício e bloqueio *fail-closed* de clearnet em `sendSovereignMessage`.
   - Fase 2: Abstração `RelayStore`, capabilities duráveis SHA-256 com escopo/revogação, `PostgresMailboxStore` (PostgreSQL 17), bloqueio não-loopback em admin, `provision_vps.sh` e teste vivo em Tor `0.4.9.15` Onion v3.
   - Fase 3: `SovereignMessenger` + `gate3_two_client_e2ee_test.dart` (OOB Card ID, alerta de troca de chave, X3DH + Double Ratchet fora de ordem, Commit-before-ACK, retry Outbox, chunks com EXIF strip, Sender Keys época, expiração distribuída).
   - Fases 4–9: Simulador 50 clientes + 2 MB (`docs/PERFORMANCE.md`), Rádio `<=240B` / Duty Cycle / MBTiles / ATAK CoT, Monero Ed25519 + isolamento Seed A/B, Nix Archive v1 XSS/integrity, Nix Media FTS5/magnet gate, `PqxdhCombiner`, SBOM CycloneDX, assinador `SignedReleaseManifest` e `PRIVACY_MATRIX.md` + `THIRD_PARTY_LICENSES.md`.
8. **Etapa 8 — Integração dos PRs #13 a #18 & Encerramento Formal da Issue #11:**
   - Merge limpo e resolução de conflitos em `nix_state.dart`, `config.go` e `relay.local.yaml` preservando as suítes completas (`68/68` no cliente, `10/10` crypto, `22/22` transport, Go `-race` e privacy gate).
   - Issue #11 formalmente comentada e encerrada no GitHub (`completed`).

---

## 7. PRÓXIMAS TAREFAS OPERACIONAIS / HARDWARE REMANESCENTES

1. **Soak Contínuo de 60 Minutos em VPS Externa:** Provisionar Debian 13 via `services/nix_relay/deploy/provision_vps.sh` e rodar `./bench -clients 50 -duration 60m`.
2. **Hardware Físico Android / LoRa:** Validar APK Android em dispositivo real com hardware StrongBox/TEE, pareamento Bluetooth físico BLE mesh e adaptadores LoRa/RNode seriais.
3. **Auditoria Externa Independente:** Submeter relatório SBOM + matriz de privacidade + suítes E2EE antes de release beta pública.

---

## 8. AUDITORIA DOS PULL REQUESTS #20 A #30 E ISSUE #19 (19/11/2026)

| Item | Tipo | Autor | Escopo / Mudanças | Status da Auditoria |
|---|---|---|---|---|
| **#19** | Issue | @foros049695 | Prevenção de criação de cofre com frase-passe randômica descartada quando chaveiro do SO falha | **RESOLVIDO** (Validado via PR #30 + guarda de UI + 7 testes) |
| **#20** | PR | @gabrielmaialva33 | Relato honesto de falhas parciais de destruição no botão de pânico das configurações | **VALIDADO E TESTADO** (100% verde) |
| **#21** | PR | @gabrielmaialva33 | Extensão da destruição anti-forense a todos os diretórios locais sem seguir symlinks | **VALIDADO E TESTADO** (+ paralisia síncrona do Tor) |
| **#22** | PR | @gabrielmaialva33 | Proteção contra gaps assíncronos de `BuildContext` e remoção de await redundante | **VALIDADO E TESTADO** |
| **#23** | PR | @gabrielmaialva33 | Rejeição *fail-closed* no Relay Go caso arquivo `-config` explícito falhe | **VALIDADO E TESTADO** (`go test -race` 100% verde) |
| **#24** | PR | @gabrielmaialva33 | Roteamento de relatos de vulnerabilidades para Private Advisories no GitHub | **VALIDADO E DOCUMENTADO** |
| **#25** | PR | @gabrielmaialva33 | Documentação de diretórios placeholder e correção de comentário no `.gitattributes` | **VALIDADO E DOCUMENTADO** |
| **#26** | PR | @gabrielmaialva33 | README detalhado do `nix_client` com setup Linux e segurança de testes em `HOME` isolado | **VALIDADO E DOCUMENTADO** |
| **#27** | PR | @gabrielmaialva33 | ADR 0005 (driver PostgreSQL `lib/pq`) e ADR 0006 (FFI SQLCipher e renderizador QR offline) | **VALIDADO E DOCUMENTADO** |
| **#28** | PR | @gabrielmaialva33 | Reorganização de `modules/core_crypto` com implementações em `lib/src` preservando barrel | **VALIDADO E TESTADO** (13/13 testes aprovados) |
| **#29** | PR | @gabrielmaialva33 | Separação dos 12 repositórios SQLite em arquivos modulares sob barrel `repositories.dart` | **VALIDADO E TESTADO** (barrel probe aprovado) |
| **#30** | PR | @gabrielmaialva33 | Rollback atômico do cofre caso o vínculo com o chaveiro nativo do SO retorne falso | **VALIDADO E TESTADO** (7/7 testes de probe aprovados) |

---

## 9. ROTINA AUTOMATIZADA PERSISTENTE A CADA 4 HORAS (FASE 16)

- **Workflow GitHub Actions:** `.github/workflows/nix_maintenance_audit.yml` (agendamento `0 */4 * * *` e manual via `workflow_dispatch`).
- **Auditor Autônomo:** `scripts/run_maintenance_audit.py` com relatórios em `docs/automation/MAINTENANCE_REPORT.md` e snapshots em `docs/automation/history/`.
- **Relatório Completo de Resolução:** [`docs/ISSUES_PRS_RESOLUTION_REPORT.md`](ISSUES_PRS_RESOLUTION_REPORT.md).

---

## 10. AUDITORIA E IMPLEMENTAÇÃO DOS PULL REQUESTS #31 A #34 E ISSUE #35 (19/11/2026)

| Item | Tipo | Autor | Escopo / Mudanças | Status da Auditoria & Implementação |
|---|---|---|---|---|
| **#31** | PR | @gabrielmaialva33 | Fixação de versões de GitHub Actions por commit SHA imutável, permissões mínimas (`contents: read`), cancelamento de concorrência em PRs e timeouts explícitos | **INTEGRADO E VALIDADO** (Hardening aplicado em `ci.yml`, `security-audit.yml` e `nix_maintenance_audit.yml`) |
| **#32** | PR | @gabrielmaialva33 | Ativação de análise estática estrita em Dart (`strict-inference: true`, `unawaited_futures`, `only_throw_errors`, `avoid_dynamic_calls`) nos módulos `core_crypto` e `transport` | **INTEGRADO E TESTADO** (0 erros, 0 warnings; 13/13 testes em crypto e 22/22 em transport aprovados) |
| **#33** | PR | @gabrielmaialva33 | Limpeza e zeramento incondicional de estado sensível em memória (`panicWipeAllData`): descarte de identidades derivadas (`_moneroMarketIdentity`, `_fallbackArchiveIdentity`), caches e cancelamento de timers | **INTEGRADO E TESTADO** (10/10 pontos do ciclo de vida aprovados em `panic_derived_identities_probe_test.dart`) |
| **#34** | PR | @gabrielmaialva33 | Sincronização técnica completa do `AGENTS.md` com driver PostgreSQL `lib/pq`, relay local, API pública crypto, repositórios SQL, ViewModels e rotina 4h | **INTEGRADO E SINCRONIZADO** (`AGENTS.md` 100% atualizado) |
| **#35** | Issue | @foros049695 | Decomposição incremental de `NixState`: extração de `CallViewModel`, `PeerHoverViewModel`, `StarwireFilterViewModel` e `MoneroOrderFilterViewModel` mantendo fachada compatível | **RESOLVIDO E TESTADO** (11/11 testes em `view_models_test.dart`, isolamento comprovado de timers e recomposições) |


