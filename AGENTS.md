# AGENTS.md

Guidance for coding agents (Claude Code, Codex, Gemini CLI, Cursor, Copilot and similar) working in this repository. `CLAUDE.md` and `GEMINI.md` only import this file: edit it here.

## What this is

Projeto Nix is a pre-alpha, local-first privacy messenger with a planned archive, media library and Monero wallet. It is a monorepo with no root build tool: each package is built and tested from its own directory. Most docs and code comments are in Portuguese (pt-BR), and commit messages mix pt-BR and English. Match the language of the file you are editing, and write new docs and ADRs in pt-BR like the rest of `docs/`.

Work is organized by the P0/P1/P2 milestones in `ROADMAP.md` and the README maturity matrix. Commit scopes follow those milestones (`feat(p0-2): …`, `fix(p0-4): …`) or a component (`fix(relay): …`). The README and docs often describe the *target* design, not what the code does today. Check the code before you trust a doc claim (see "Doc vs. code drift").

## Packages and commands

| Package | Language | Dir | Commands (run inside the dir) |
|---|---|---|---|
| Client app | Flutter | `apps/nix_client` | `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run -d linux` |
| Crypto core | Dart | `modules/core_crypto` | `dart pub get`, `dart analyze`, `dart test` |
| Tor transport | Dart | `modules/transport` | `dart pub get`, `dart analyze`, `dart test` |
| Relay | Go (stdlib only, `go 1.22`) | `services/nix_relay` | `go vet ./...`, `go test -race ./...`, `go run ./cmd/relay -config <file>.yaml` |

To run the relay locally, copy `services/nix_relay/configs/relay.example.yaml` and point `storage.base_dir` at a writable directory. Both shipped configs hardcode a `base_dir` (`/var/lib/...` or a development-machine home path), so the relay exits at startup elsewhere.

Run a single test:
- Dart/Flutter: `dart test test/core_crypto_test.dart --name "<substring>"` or `flutter test test/widget_test.dart --plain-name "<substring>"`
- Go: `go test -race -run TestName ./internal/buffer/`

Privacy gate, from the repo root (CI runs it on every push): `./scripts/verify_privacy_matrix.sh`. It greps the whole tree, excluding `assets/`, for analytics and crash-reporting SDK names (the list is `FORBIDDEN_PATTERNS` in the script itself), and fails if any `.go` file under `services/nix_relay` mentions `r.RemoteAddr`. Even a comment or doc line that names one of those SDKs breaks the build, this file included: don't write the names here.

CI (`.github/workflows/ci.yml`, Go 1.23 and Flutter stable) runs the privacy gate, relay `go vet` + `go test -race`, `dart analyze` + `dart test` for both modules, and `flutter analyze` + `flutter test` for the client.

## Architecture

**Dependency direction:** `apps/nix_client` → `modules/core_crypto` and `modules/transport`, as path dependencies. The modules do not depend on each other or on Flutter. `modules/{archive,index,media,offgrid,wallet}` hold only a README, as placeholders for later milestones.

**`modules/core_crypto`** (`lib/nix_core_crypto.dart`, one file) is built on the `cryptography` package. It provides Ed25519/X25519 identities, XChaCha20-Poly1305 `SealedEnvelope`, Argon2id, X3DH prekey bundles, `DoubleRatchet`, `SignedRecord` and `ReplayGuard`. ADR 0004 sets invariants you must keep:
- `DoubleRatchet.decrypt` computes DH ratchet steps and skipped keys on a candidate state copy. The session is mutated only after AEAD verification succeeds, so a forged message must leave the state untouched.
- `SignedRecord` canonicalization sorts map keys recursively at every nesting level and keeps list order.
- `ReplayGuard` purges every expired nonce. Never assume insertion order matches expiry order.
- Skipped message keys are capped at 256 per session.

**`modules/transport`** (`lib/nix_transport.dart`, one file) is fail-closed by design. It includes a SOCKS5 connector with remote DNS (no local resolution leaks), a Tor ControlPort client, strict `.onion` v3 address policy, and an HTTP client for relay mailboxes that supports TLS over SOCKS and chunked transfer. A private-profile connection must never fall back to clearnet when Tor is unavailable.

**`services/nix_relay`** is a blind store-and-forward mailbox:
- `cmd/relay/main.go` builds `NewMux` (public API) and `NewAdminMux`, which serves only `/metrics` on a separate listener at `metrics.listen_addr`. That address defaults to `127.0.0.1:9090`, but the code does not enforce loopback.
- `internal/buffer/store.go` holds `BlindMailboxStore`. It stores opaque `payload_b64` envelopes per mailbox and enforces in-flight quotas per `X-Nix-Quota-Token`. `GET .../envelopes` and `POST .../ack` require a bearer token: `ValidateCapability` binds the first token presented for a mailbox (in memory, trust on first use) and compares later ones in constant time. Its `scope` argument is not checked yet, and `POST .../envelopes` takes no bearer token. Quotas are rebuilt from disk on restart.
- `internal/buffer/autopruner.go` holds `AutoPruner`, which tightens TTL and the attachment cap as disk usage rises, with hysteresis: NORMAL → LIGHT_RELIEF ≥75% → SEVERE_RELIEF ≥85% → CRITICAL_BLOCK ≥92%, returning to NORMAL below 70%.
- `internal/buffer/config.go` has a hand-written YAML-subset parser. go.mod has no dependencies, and adding one needs an ADR (see CONTRIBUTING).
- The relay must never log or store client IPs; the privacy gate enforces this.

**`apps/nix_client`** centers on a single `ChangeNotifier`, `NixState` (`lib/state/nix_state.dart`, ~2k lines), provided at the root via `provider`. Widgets read it with `context.select`/`watch`.
- UI is grouped by feature under `lib/features/*`. Domain models live in `lib/core/models`. Theming lives in `lib/core/theme*`: `NixPalette`, `NixColors.sync(...)` (global colors that `main.dart` re-syncs on every build), and `NixTokens` for radii.
- Most UI runs on `MockData` (`lib/state/mock_data.dart`) and is not connected to the crypto, transport or database layers yet (the "UI_ONLY" state in the README). UI preferences are saved as plain JSON at `~/.local/share/nix/client_prefs_v4.json`, which is skipped when `FLUTTER_TEST=true`.
- `lib/core/security/key_vault.dart` is the `KeyVault`: a random 32-byte master key wrapped with an Argon2id-derived key (64 MiB, 3 iterations) plus XChaCha20-Poly1305. The bootstrap file never holds the key in cleartext.
- `lib/core/database/local_database.dart` is `LocalDatabase`. It uses `sqflite_common_ffi`, applies `PRAGMA key` with the raw vault key, and reports through `cipherInfo` whether SQLCipher is actually active. `repositories.dart` holds the domain repositories (Identity, Contact, Conversation, Message, Outbox, Media, Preferences). `NixState` imports these but does not use them yet.

**Database migrations** (`database/`):
- `schema/{local,relay}.sql` are the target schemas, `migrations/*.sql` are the ordered migrations, and `examples/` holds synthetic data and backup/restore scripts.
- `LocalDatabase` checks each local migration file against a SHA-256 constant (`checksumMigration001/002`). Any byte change to `local_00X_*.sql` needs the matching constant updated; `test/database_and_vault_test.dart` asserts those constants.
- The client finds migration files by paths relative to the current directory (`database/migrations/` or `../../database/migrations/`), so run client tests from `apps/nix_client`.

**Protobuf** (`proto/nix/v1/*.proto`): the VS Code task "Proto: Compile Schemas" would generate code into `services/nix_relay/internal/pb` and `apps/nix_client/lib/core/pb`. Neither directory exists yet, and nothing imports generated code.

## Doc vs. code drift

These are known gaps; don't "fix" docs or code to match the other without checking first:
- The README and the relay architecture describe PostgreSQL 17 storage and `/api/v1/envelopes` routes. The relay as built persists one JSON file per mailbox in `storage.base_dir` (atomic tmp + rename, `0600`), and its routes are `/v1/mailboxes/{id}/envelopes` and `/v1/mailboxes/{id}/ack`. `database/schema/relay.sql` is the PostgreSQL target, not yet wired in.
- SQLCipher encryption depends on the runtime: plain `sqflite_common_ffi` loads the system SQLite. Check `cipherInfo.isEncrypted` instead of assuming the database is encrypted.
- `LocalDatabase._loadMigrationFile` includes a hardcoded absolute path from a development machine among its candidate paths, and `configs/relay.local.yaml` hardcodes `storage.base_dir` the same way.

## Non-negotiable project rules (CONTRIBUTING.md)

Changes that break these are rejected:
- No telemetry, analytics, third-party SDKs or automated crash reporting.
- Never require or suggest phone, SMS, email, government ID (CPF) or contact-list access.
- No homemade crypto primitives; audited libraries only.
- The messenger identity (**Seed A**) must never derive from, share keys with, or talk to the Monero wallet key (**Seed B**). See ADR 0003.
- Private network traffic fails closed. Never add a fallback that bypasses Tor or the proxy.
- New external dependencies need an ADR in `docs/adr/` first.

Regression probes (`*_probe_test.dart`, `probe_test.go`) reproduce audit findings such as the CRY01 ratchet corruption and the SOCKS stream re-listen bug. Keep them passing, and when you fix an audit finding, add a probe for it.
