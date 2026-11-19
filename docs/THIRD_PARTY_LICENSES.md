# 📜 Licenças & Dependências de Terceiros — Projeto Nix

Todas as dependências diretas e de compilação inspecionadas nos arquivos de manifesto e caches do monorepo são código aberto permissivo (MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0):

| Ecossistema | Pacote / Versão Travada | Licença (SPDX verificada) | Componente Nix |
|---|---|---|---|
| **Go (`services/nix_relay`)** | `github.com/lib/pq v1.12.3` | MIT License | `PostgresMailboxStore` (driver PostgreSQL 17+) |
| **Go stdlib** | Go 1.22 / 1.23 | BSD-3-Clause | HTTP, crypto/sha256, crypto/subtle, sync, encoding/json |
| **Dart (`core_crypto`)** | `cryptography 2.9.0` | Apache-2.0 | Ed25519, X25519, XChaCha20-Poly1305, Argon2id, HKDF-SHA256 |
| **Dart (`core_crypto`, `transport`, `nix_client`)** | `crypto 3.0.8` | BSD-3-Clause | SHA-256 canônico e digests HMAC |
| **Flutter (`nix_client`)** | `sqflite_common_ffi 2.3.4+4` | BSD-2-Clause | Interface SQLite/SQLCipher local FFI |
| **Flutter (`nix_client`)** | `sqlite3 2.9.4` | MIT | Bindings nativos `sqlite3/open.dart` |
| **Flutter (`nix_client`)** | `sqlcipher_flutter_libs 0.6.8` | MIT (plugin) / BSD-3-Clause (SQLCipher Community) | Motor **SQLCipher 4.10.0 community** criptografado em repouso |
| **Flutter (`nix_client`)** | `ffi 2.1.3` | BSD-3-Clause | Integração FFI `libsecret-1.so.0` / `libglib-2.0.so.0` (Linux) |
| **Flutter (`nix_client`)** | `protobuf 3.1.0` | BSD-3-Clause | Mensagens binárias compactas / proto |
| **Flutter (`nix_client`)** | `provider 6.1.5+1` | MIT | Gerenciamento de estado reativo (`NixState`) |
| **Flutter (`nix_client`)** | `qr_flutter 4.1.0` | BSD-3-Clause | Renderização visual de Card ID & URI local |
| **Dev/Test** | `test 1.26.3`, `lints 5.1.1`, `flutter_lints 5.0.0` | BSD-3-Clause | Executores e analisadores estáticos |
| **Rede (externo embutível)** | Tor Daemon `0.4.9.15` + `libevent 2.1.13` | BSD-3-Clause (Tor / Libevent) | Camada anônima SOCKS5 e HiddenService v3 |

> Para gerar o SBOM reproduzível atualizado no formato **CycloneDX 1.5** cobrindo todas as 90+ dependências diretas e transitivas:
> ```bash
> ./scripts/generate_sbom.sh
> ```
