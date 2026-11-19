# 🧪 Estratégia de Testes & Portões de Qualidade — Nix

## 1. Suítes Executáveis e Verificadas no Monorepo

- **`modules/core_crypto` (`dart analyze --fatal-infos && dart test`):**
  - Ed25519/X25519, Argon2id, X3DH, Double Ratchet (forward secrecy + out-of-order + serialização + atomicidade), `ReplayGuard`, `PqxdhCombiner` e `SignedReleaseManifest`.
- **`modules/transport` (`dart analyze --fatal-infos && dart test`):**
  - SOCKS5 `ATYP 0x03` sem DNS local, **HTTPS/TLS real sobre SOCKS5 (`RawSecureSocket`)**, `UnsupportedTransportSchemeException` fail-closed, `TorDiagnostics.probeSocks5Proxy`, `EmbeddedTorManager`, Bluetooth Mesh `NIXB` e **Off-Grid Radio `<=240B` / Duty Cycle / ATAK CoT com consentimento explícito**.
- **`services/nix_relay` (`go test -v -race ./...`):**
  - Endpoints HTTP, limites 413 de corpo base64, falhas de persistência 500, histerese AutoPruner, capabilities SHA-256 duráveis + escopos + revogação (`/admin/capabilities`), isolamento loopback obrigatório e **PostgreSQL 17 real com concorrência e GC (`NIX_TEST_PG_DSN`)**.
- **`apps/nix_client` (`flutter analyze --no-fatal-infos && FLUTTER_TEST=true flutter test` com `HOME` isolado):**
  - **SQLCipher 4.10.0** em disco (zero plaintext, wrong-key rejeitada), `SeedRecoveryManager` 24 palavras + checksum, `KeyVault` Duress PIN + OS Keyring + reload pós-reinicialização, **pipeline completo Alice & Bob E2EE via SOCKS5** (X3DH, Ratchet fora-de-ordem, Outbox retry, Commit-before-ACK crash recovery, chunks + EXIF strip, Sender Keys época, TTL efêmero), MBTiles offline, Monero Ed25519/Seed A-B, Nix Archive v1 XSS/integrity e Nix Media FTS5/magnet gate.
- **Portão Estático de Privacidade & Supply Chain:**
  - `./scripts/verify_privacy_matrix.sh` + `./scripts/generate_sbom.sh` (CycloneDX 1.5).
