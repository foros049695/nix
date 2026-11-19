# AGENTS.md

Guidance for coding agents (Claude Code, Codex, Gemini CLI, Cursor, Copilot and similar) working in this repository. `CLAUDE.md` and `GEMINI.md` only import this file: edit it here.

## What this is

Projeto Nix is a pre-alpha, local-first privacy messenger with a planned archive, media library and Monero wallet. It is a monorepo with no root build tool: each package is built and tested from its own directory. Most docs and code comments are in Portuguese (pt-BR), and commit messages mix pt-BR and English. Match the language of the file you are editing, and write new docs and ADRs in pt-BR like the rest of `docs/`.

Work is organized by the P0/P1/P2 milestones in `ROADMAP.md` and the README maturity matrix. Commit scopes follow those milestones (`feat(p0-2): …`, `fix(p0-4): …`) or a component (`fix(relay): …`). The README and docs often describe the *target* design, not what the code does today. Check the code before you trust a doc claim (see "Doc vs. code drift").

## Packages and commands

**Test safety:** Run client tests with an isolated HOME: the account panic-wipe path targets `~/.local/share/nix`. Run transport tests in an isolated network namespace where no service listens on `127.0.0.1:9050`; the embedded Tor manager can reuse an existing listener. Use temporary data directories and simulated processes, not a real Tor daemon, for lifecycle tests.

| Package | Language | Dir | Commands (run inside the dir) |
|---|---|---|---|
| Client app | Flutter | `apps/nix_client` | `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run -d linux` |
| Crypto core | Dart | `modules/core_crypto` | `dart pub get`, `dart analyze`, `dart test` |
| Tor transport | Dart | `modules/transport` | `dart pub get`, `dart analyze`, `dart test` |
| Relay | Go (stdlib only, `go 1.22`) | `services/nix_relay` | `go vet ./...`, `go test -race ./...`, `go run ./cmd/relay -config <file>.yaml` |

Flutter's analyzer treats informational diagnostics as fatal by default. Check the SDK version and `.github/workflows/ci.yml` for the analysis policy; distinguish existing infos from errors and warnings when reporting results.

To run the relay locally, copy `services/nix_relay/configs/relay.example.yaml` and point `storage.base_dir` at a writable directory. Both shipped configs hardcode a `base_dir` (`/var/lib/...` or a development-machine home path), so the relay exits at startup elsewhere.

Run a single test:
- Dart/Flutter: `dart test test/core_crypto_test.dart --name "<substring>"` or `flutter test test/widget_test.dart --plain-name "<substring>"`
- Go: `go test -race -run TestName ./internal/buffer/`

Privacy gate, from the repo root: `./scripts/verify_privacy_matrix.sh`. It greps the whole tree, excluding `assets/`, for analytics and crash-reporting SDK names (the list is `FORBIDDEN_PATTERNS` in the script itself), and fails if any `.go` file under `services/nix_relay` mentions `r.RemoteAddr`. Even a comment or doc line that names one of those SDKs breaks the build, this file included: don't write the names here.

CI (`.github/workflows/ci.yml`, Go 1.23 and Flutter stable) runs the privacy gate, relay `go vet` + `go test -race`, `dart analyze` + `dart test` for both modules, and `flutter analyze` + `flutter test` for the client. It triggers on pushes to `main`, `develop`, and `feature/**`, and PRs targeting `main` or `develop`. Analysis precedes tests within each Dart/Flutter job, so analysis failures prevent those test steps from running.

## Architecture

**Dependency direction:** `apps/nix_client` → `modules/core_crypto` and `modules/transport`, as path dependencies. The modules do not depend on each other or on Flutter. `modules/{archive,index,media,offgrid,wallet}` hold only a README, as placeholders for later milestones.

**`modules/core_crypto`** (`lib/nix_core_crypto.dart`, one file) is built on the `cryptography` package. It provides Ed25519/X25519 identities, XChaCha20-Poly1305 `SealedEnvelope`, Argon2id, X3DH prekey bundles, `DoubleRatchet`, `SignedRecord` and `ReplayGuard`. ADR 0004 sets invariants you must keep:
- `DoubleRatchet.decrypt` computes DH ratchet steps and skipped keys on a candidate state copy. The session is mutated only after AEAD verification succeeds, so a forged message must leave the state untouched.
- `SignedRecord` canonicalization sorts map keys recursively at every nesting level and keeps list order.
- `ReplayGuard` purges every expired nonce. Never assume insertion order matches expiry order.
- Skipped message keys are capped at 256 per session.

**`modules/transport`** has four library files: `nix_transport.dart`, `nix_bluetooth_mesh.dart`, `nix_embedded_tor.dart`, and `nix_offgrid_radio.dart`. It includes a SOCKS5 connector with remote DNS (`ATYP = 0x03`), native TLS over SOCKS5 (`Socks5Connector.connectRaw` + `RawSecureSocket.secure`, Issue #11 resolved; `test/https_over_socks_probe_test.dart`), a Tor ControlPort client, strict `.onion` v3 address policy, a relay HTTP/HTTPS client with chunked transfer, mesh transport, off-grid radio framing, and an embedded Tor manager with ControlPort bootstrap verification (`verifyOperationalState`). Non-`http`/`https` schemes are rejected fail-closed with `UnsupportedTransportSchemeException` before opening a socket. A private-profile connection must never fall back to clearnet when Tor is unavailable.

**`services/nix_relay`** is a blind store-and-forward mailbox:
- `cmd/relay/main.go` builds `NewMux` (public API) and `NewAdminMux`, which serves `/metrics` and `/admin/capabilities` on a separate listener at `metrics.listen_addr`. `ValidateAdminListenAddr` enforces loopback binding (`127.0.0.1` / `::1` / `localhost`).
- `internal/buffer/` holds `RelayStore` implemented by both `BlindMailboxStore` (atomic JSON per mailbox in `storage.base_dir` + `.capabilities.json` SHA-256) and `PostgresMailboxStore` (PostgreSQL 17 using `database/schema/relay.sql`). It stores opaque `payload_b64` envelopes per mailbox, enforces in-flight quotas per `X-Nix-Quota-Token`, and enforces durable scoped bearer capabilities (`write`, `read_ack`, `admin`) with expiration and revocation.
- `internal/buffer/autopruner.go` holds `AutoPruner`, which tightens TTL and the attachment cap as disk usage rises, with hysteresis: NORMAL → LIGHT_RELIEF ≥75% → SEVERE_RELIEF ≥85% → CRITICAL_BLOCK ≥92%, returning to NORMAL below 70%.
- `internal/buffer/config.go` has a hand-written YAML-subset parser with `~` expansion for `storage.base_dir`.
- The relay must never log or store client IPs; the privacy gate enforces this.

**`apps/nix_client`** centers on a single `ChangeNotifier`, `NixState` (`lib/state/nix_state.dart`), provided at the root via `provider`. Widgets read it with `context.select`/`watch`.
- UI is grouped by feature under `lib/features/*`. Domain models live in `lib/core/models`. Theming lives in `lib/core/theme*`: `NixPalette`, `NixColors.sync(...)` (global colors that `main.dart` re-syncs on every build), and `NixTokens` for radii.
- `NixState.sendDirectMessage()` and `NixState.syncWithRelay()` route remote DMs through `SovereignMessenger` (`lib/core/messaging/sovereign_messenger.dart`) with X3DH/Double Ratchet sessions, atomic SQLite transactions (`sessions` + `messages` + `attachments` + `outbox`), honest delivery states (`queued`, `accepted`, `delivered`, `failed`), and strict separation from local Saved Messages (`saved`). Production starts with a clean local state; `MockData` (`lib/state/mock_data.dart`) is selected by `loadMockData` or by default when `FLUTTER_TEST=true`. UI preferences are saved as plain JSON at `~/.local/share/nix/client_prefs_v4.json`, which is skipped when `FLUTTER_TEST=true`.
- `lib/core/security/key_vault.dart` is the `KeyVault`: a random 32-byte master key wrapped with an Argon2id-derived key (64 MiB, 3 iterations) plus XChaCha20-Poly1305, optional OS keyring binding (`libsecret` / `AndroidKeyStore`), Duress PIN, atomic rollback (`rollbackFreshBootstrap`), and encrypted backup/restore bundles (`exportEncryptedBackupBundle` / `importEncryptedBackupBundle`). There is no default hardcoded passphrase (`initializeEncryptedDatabase` requires `passphrase`).
- `lib/core/database/local_database.dart` is `LocalDatabase`. It uses `sqflite_common_ffi`, prioritizes real SQLCipher libraries, applies `PRAGMA key` with the raw vault key, exposes `cipherInfo` (`cipherVersion != null`), and rejects unencrypted SQLite fail-closed when `requireEncryption: true` (or `NIX_REQUIRE_SQLCIPHER=true`). `repositories.dart` holds the domain repositories.
- `lib/core/security/anti_forensic_shredder.dart` implements account-file wiping confined to `customBaseDir` and vault locking; see the test-safety warning above. `lib/features/onboarding/sovereign_onboarding_flow.dart` owns 9-step onboarding with active Tor/fail-closed verification (`verifyTorTransportAndFailClosed`), atomic snapshot writes (`tmp + rename`), and prerequisite enforcement in `completeOnboarding`.
- `lib/core/p2p/monero_ad_verifier.dart`, `lib/core/archive/nix_archive_service.dart`, `lib/core/media/media_catalog_service.dart`, `lib/core/security/file_picker_adapter.dart`, `lib/features/discovery/github_discovery_view.dart`, and `lib/features/offline/share_app_offline_dialog.dart` implement Ed25519-signed Monero P2P ads (isolated from Seed A), deterministic HTML-sanitized canonical publications, local FTS5 + opt-in media connectors, portable file picking, strict Tor download enforcement (no clearnet bypass), and Ed25519 `SignedReleaseManifest` verification for offline APK sharing.

**Database migrations** (`database/` and `apps/nix_client/assets/migrations/`):
- `schema/{local,relay}.sql` are the target schemas, `migrations/*.sql` are the ordered migrations, and `examples/` holds synthetic data and backup/restore scripts.
- Keep `LocalDatabase.checksumMigration001/002` and `apps/nix_client/assets/migrations/*.sql` in sync with the SHA-256 of `database/migrations/local_00X_*.sql`: any byte change to a migration needs the matching constant and bundled asset updated.
- The client loads migrations from bundled Flutter assets first (`assets/migrations/`), falling back to relative paths (`database/migrations/` or `../../database/migrations/`).

**Protobuf** (`proto/nix/v1/*.proto`): the VS Code task "Proto: Compile Schemas" would generate code into `services/nix_relay/internal/pb` and `apps/nix_client/lib/core/pb`. Neither directory exists yet, and nothing imports generated code.

## Doc vs. code drift

Keep these verified boundaries in mind:
- `services/nix_relay` routes are `/v1/mailboxes/{id}/envelopes` and `/v1/mailboxes/{id}/ack` (not `/api/v1/envelopes`), and supports both `BlindMailboxStore` (file-backed) and `PostgresMailboxStore` (PostgreSQL 17).
- SQLCipher encryption depends on the runtime library: `LocalDatabase.open(..., requireEncryption: true)` rejects plain SQLite fail-closed. In headless CI without `libsqlcipher`, dev mode reports `isEncrypted: false` (`SQLite-Development-Clearnet`) honestly.
- Real VPS deployment (Debian 13 + 60m Onion v3 soak), physical Android APK/NDK testing, physical Bluetooth BLE / LoRa RF hardware, and live `monero-wallet-rpc` stagenet/mainnet settlement remain outside local-lab verification (see `docs/IMPLEMENTATION_NEXT_STEPS.md`).

## Non-negotiable project rules (CONTRIBUTING.md)

Changes that break these are rejected:
- No telemetry, analytics, third-party SDKs or automated crash reporting.
- Never require or suggest phone, SMS, email, government ID (CPF) or contact-list access.
- No homemade crypto primitives; audited libraries only.
- The messenger identity (**Seed A**) must never derive from, share keys with, or talk to the Monero wallet key (**Seed B**). See ADR 0003.
- Private network traffic fails closed. Never add a fallback that bypasses Tor or the proxy.
- New external dependencies need an ADR in `docs/adr/` first.

Regression probes (`*_probe_test.dart`, `probe_test.go`) reproduce audit findings such as the CRY01 ratchet corruption and the SOCKS stream re-listen bug. Keep them passing, and when you fix an audit finding, add a probe for it.
