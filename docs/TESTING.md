# 🧪 Estratégia de Testes & Portões de Qualidade — Nix

## 1. Suítes Executáveis e Verificadas no Monorepo

- **`modules/core_crypto` (`dart analyze --fatal-infos && dart test`):**
  - Ed25519/X25519, Argon2id, X3DH, Double Ratchet (forward secrecy + out-of-order + serialização + atomicidade), `ReplayGuard`, `PqxdhCombiner` e `SignedReleaseManifest`.
- **`modules/transport` (`dart analyze --fatal-infos && dart test`):**
  - SOCKS5 `ATYP 0x03` sem DNS local, **HTTPS/TLS real sobre SOCKS5 (`RawSecureSocket`)**, `UnsupportedTransportSchemeException` fail-closed, `TorDiagnostics.probeSocks5Proxy`, `EmbeddedTorManager`, Bluetooth Mesh `NIXB` e **Off-Grid Radio `<=240B` / Duty Cycle / ATAK CoT com consentimento explícito**.
- **`services/nix_relay` (`go test -v -race ./...`):**
  - Endpoints HTTP, limites 413 de corpo base64, falhas de persistência 500, histerese AutoPruner, capabilities SHA-256 duráveis + escopos + revogação (`/admin/capabilities`), isolamento loopback obrigatório e **PostgreSQL 17 real com concorrência e GC (`NIX_TEST_PG_DSN`)**.
- **`apps/nix_client` (`flutter analyze --no-fatal-infos && HOME="$TMP_HOME" FLUTTER_TEST=true flutter test` — 89 testes):**
  - **SQLCipher 4.10.0 & Rejeição de SQLite comum (`plain_sqlite_rejection_probe_test.dart`, `audit_integration_verification_test.dart`):** zero plaintext em disco, chave incorreta rejeitada e bloqueio fail-closed (`requireEncryption: true`) quando carregado `libsqlite3.so.0` comum mesmo com chave de 32 bytes.
  - **Consistência Transacional & Mensageria Real via UI (`transactional_messaging_fault_test.dart`):** injeção de falhas nos 6 estágios (`beforeSessionSave`, `afterSessionSave`, `afterMessageInsert`, `duringOutboxInsert`, `duringRelaySend`, `afterRemoteAcceptBeforeLocalConfirm`), troca bidirecional entre duas instâncias independentes de `NixState` via relay + SOCKS5 locais, diferenciação de Mensagens Salvas e recuperação de outbox após reinicialização.
  - **Seed A, KeyVault, Onboarding, Monero P2P, Anexos, Archive, Media, Starwire e APK Offline (`milestone_b_security_test.dart`, `gate3_two_client_e2ee_test.dart`, `audit_integration_verification_test.dart`, `widget_test.dart`):** backup/restore cifrado do KeyVault, verificação ativa fail-closed do Tor no onboarding, assinatura/verificação Ed25519 isolada da Seed A no mercado Monero P2P, `FilePickerAdapter` portável, cancelamento de anexos com limpeza de chunks, rotação de Sender Keys em kick/ban, tokenizador HTML anti-XSS + ciclo completo de publicações canônicas, conectores de mídia opt-in sob política Tor, proibição de bypass clearnet no Starwire e verificação Ed25519 `SignedReleaseManifest` na transferência HTTP local de APK.
- **Portão Estático de Privacidade & Supply Chain:**
  - `./scripts/verify_privacy_matrix.sh` + `./scripts/generate_sbom.sh` (CycloneDX 1.5).

Consulte o relatório detalhado de execução em [`docs/LOCAL_INTEGRATION_TEST_REPORT.md`](LOCAL_INTEGRATION_TEST_REPORT.md).
