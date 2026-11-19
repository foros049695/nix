# Verificação e Rastreabilidade de Issues e Pull Requests — Projeto Nix

**Repositório:** `https://github.com/foros049695/nix`  
**Commit de referência inicial:** `115f3894b3f9d08609c95bc4b5c85b2bb1417038` (19/11/2026)  
**Estado consultado no GitHub:** 0 PRs abertos · 16 PRs integrados (`#1`–`#10`, `#13`–`#18`) · 2 Issues encerradas (`#11`, `#12`).

---

## 1. Auditoria Independente das Issues Encerradas

### Issue `#11` — HTTPS sobre SOCKS5 (`RelayClient`)
- **Arquivos inspecionados:**
  - `modules/transport/lib/nix_transport.dart` (`Socks5Connector.connectRaw`, `RelayClient._socksHttp`, `UnsupportedTransportSchemeException`)
  - `modules/transport/test/https_over_socks_probe_test.dart`
- **Verificações executadas:**
  1. **Handshake TLS nativo sobre SOCKS5:** `Socks5Connector.connectRaw` estabelece o túnel TCP diretamente em `RawSocket` e entrega `SocksRawConnection(socket, subscription)` para `RawSecureSocket.secure(..., host: uri.host, context: tlsContext, onBadCertificate: onBadCertificate ?? (_) => false)` (evitando `_detachRaw`).
  2. **Rejeição de certificados inválidos:** Testado e aprovado (`onBadCertificate` retorna `false` por padrão; certificado autoassinado não confiado falha fechado).
  3. **DNS remoto (sem vazamento local):** `Socks5Connector.connectRaw` valida `.onion` v3 de 56 caracteres e envia `ATYP = 0x03` (hostname) ao proxy SOCKS5 sem resolução DNS local.
  4. **Ausência de fallback direto e tratamento de erros:** `TransportPolicy.assertAllowedUri` rejeita qualquer host clearnet em `torFailClosed`, e esquemas não-`http`/`https` lançam `UnsupportedTransportSchemeException` antes de abrir socket.
  5. **Execução do teste local:** `cd modules/transport && dart analyze --fatal-infos && dart test` → **22/22 aprovados**, incluindo todos os casos de `https_over_socks_probe_test.dart`.
- **Classificação:** **RESOLVIDO.**

### Issue `#12` — Canal Confidencial para Divulgação de Vulnerabilidades
- **Configuração autenticada verificada via API GitHub:**
  - `GET /repos/foros049695/nix/private-vulnerability-reporting` → `HTTP 200`, payload `{"enabled": true}`.
- **Coerência documental verificada:**
  - `SECURITY.md` §3 direciona explicitamente para `https://github.com/foros049695/nix/security/advisories/new` (GitHub Private Vulnerability Reporting) e proíbe abertura de issues públicas para vulnerabilidades não corrigidas.
  - `docs/INCIDENT_RESPONSE.md` §1 mantém exatamente o mesmo canal oficial, declara transparentemente que ainda não há chave PGP/Age publicada e referencia a política de divulgação coordenada.
  - Nenhuma credencial, token ou dado confidencial foi exposto.
- **Classificação:** **RESOLVIDO.**

---

## 2. Rastreabilidade Individual de Todos os 16 Pull Requests Integrados

| PR | Commit Base / Merge (`main`) | Arquivos Alterados | Alterações Presentes no Código Atual? | Testes Associados Executados | Regressões Detectadas | Classificação |
|---|---|---|---|---|---|---|
| **#1** | `879c53b` / `789cf92` | `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` | Sim (`CLAUDE.md` e `GEMINI.md` importam `AGENTS.md`). | Revisão manual + `verify_privacy_matrix.sh`. | Drift documental corrigido na Fase 10. | **Resolvido** |
| **#2** | `5682e47` / `8618b79` | `modules/core_crypto/lib/nix_core_crypto.dart`, `modules/transport/lib/nix_transport.dart` | Sim. | `dart analyze --fatal-infos` + `dart test` em `core_crypto` (10/10) e `transport` (22/22). | Nenhuma. | **Resolvido** |
| **#3** | `743d7fd` / `f54b857` | `.github/workflows/ci.yml`, `anti_forensic_shredder.dart`, `key_vault.dart`, `theme.dart`, `home_sidebar.dart`, `channels_sidebar.dart`, `sovereign_onboarding_flow.dart`, `settings_center.dart`, `database_and_vault_test.dart` | Sim. | `flutter analyze --no-fatal-infos` (0 erros/warnings) + `flutter test` completo. | Nenhuma. | **Resolvido** |
| **#4** | `0a848d3` / `5d83e77` | `apps/nix_client/lib/core/security/anti_forensic_shredder.dart`, `test/helpers/panic_wipe.dart`, `test/shredder_confinement_probe_test.dart` | Sim. | `test/shredder_confinement_probe_test.dart` (aprovado com `$HOME` isolado). | Nenhuma. | **Resolvido** |
| **#5** | `537d653` / `c7dd88d` | `modules/transport/lib/nix_embedded_tor.dart`, `test/embedded_tor_isolation_probe_test.dart`, `test/embedded_tor_test.dart` | Sim (aprimorado na Fase 6 com verificação de bootstrap ControlPort). | `modules/transport`: `embedded_tor_isolation_probe_test.dart` + `embedded_tor_test.dart` (aprovados). | Nenhuma. | **Resolvido** |
| **#6** | `08beeb3` / `7677a0b` | `apps/nix_client/lib/core/database/local_database.dart`, `test/local_database_probe_test.dart` | Sim (estendido na Fase 5 com `requireEncryption: true` fail-closed). | `test/local_database_probe_test.dart` + `test/audit_integration_verification_test.dart`. | Nenhuma. | **Resolvido** |
| **#7** | `ce1beb5` / `4a13daa` | `services/nix_relay/cmd/relay/main.go`, `persistence_probe_test.go`, `internal/buffer/autopruner.go`, `probe_test.go`, `store.go` | Sim. | `go vet ./...` + `go test -race ./...` em `services/nix_relay`. | Nenhuma. | **Resolvido** |
| **#8** | `fdd8745` / `f1dffd1` | `services/nix_relay/cmd/relay/main.go`, `attachment_probe_test.go` | Sim. | `go test -race ./...` (`attachment_probe_test.go` aprovado). | Nenhuma. | **Resolvido** |
| **#9** | `f453cdc` / `6199fc7` | `apps/nix_client/lib/core/security/local_image_helper.dart`, `test/local_image_helper_probe_test.dart` | Sim (preservado integralmente ao adicionar `FilePickerAdapter` na Fase 8). | `test/local_image_helper_probe_test.dart` (aprovado). | Nenhuma. | **Resolvido** |
| **#10** | `eff64e3` / `1799597` | `AGENTS.md` | Sim (atualizado na Fase 10 para refletir o estado pós-auditoria). | Revisão de conformidade + `verify_privacy_matrix.sh`. | Nenhuma. | **Resolvido** |
| **#13** | `a0910df` / `807e93b` | `scripts/verify_privacy_matrix.sh` | Sim. | `./scripts/verify_privacy_matrix.sh` (L-S, I-S e I-A aprovados). | Nenhuma. | **Resolvido** |
| **#14** | `7d88cc4` / `134c159` | `apps/nix_client/lib/core/database/repositories.dart`, `test/media_search_fts5_probe_test.dart` | Sim. | `test/media_search_fts5_probe_test.dart` (aprovado). | Nenhuma. | **Resolvido** |
| **#15** | `7554ca7` / `ab308e7` | `apps/nix_client/lib/state/nix_state.dart`, `test/nixstate_dispose_probe_test.dart` | Sim. | `test/nixstate_dispose_probe_test.dart` (aprovado). | Nenhuma. | **Resolvido** |
| **#16** | `6fa04b0` / `98c2228` | `apps/nix_client/android/app/src/main/AndroidManifest.xml` | Sim (`android:allowBackup="false"`, `android:fullBackupContent="false"`, `android:dataExtractionRules` preservados). | Inspeção do manifesto + `./scripts/verify_privacy_matrix.sh`. | Nenhuma (validação em aparelho Android físico permanece fora do escopo local). | **Resolvido** |
| **#17** | `1e1013b` / `f2effa4` | `.vscode/settings.json`, `services/nix_relay/configs/relay.local.yaml`, `internal/buffer/config.go`, `config_test.go` | Sim. | `go test -race ./...` (`config_test.go` aprovado). | Nenhuma. | **Resolvido** |
| **#18** | `9419e47` / `54b6f2a` | `apps/nix_client/lib/features/discovery/github_discovery_view.dart`, `test/starwire_zip_filename_test.dart` | Sim (estendido na Fase 9.3 proibindo bypass clearnet sob Tor estrito). | `test/starwire_zip_filename_test.dart` + `test/audit_integration_verification_test.dart`. | Nenhuma. | **Resolvido** |
