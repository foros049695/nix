# 🔑 Gerenciamento de Chaves & Ciclo de Vida — Nix

## 1. Inventário Real de Chaves Criptográficas

| Tipo de Chave | Algoritmo | Proteção em Repouso & Ciclo de Vida |
|---|---|---|
| **Master Key SQLCipher (32B)** | CSPRNG + envelopamento Argon2id (64 MiB, 3 it) + XChaCha20-Poly1305 | Arquivo atômico `vault_bootstrap.json` + unlock opcional via **`libsecret`** (Linux) / **`AndroidKeyStore` AES-256-GCM** (Android); nunca gravada em claro em disco. |
| **Seed A (Mensageria - 24 palavras)** | 23 bytes entropia + 1 byte checksum SHA-256 -> HKDF-SHA256 | Derivação determinística de **Ed25519** + **X25519** (`SeedRecoveryManager`); chaves privadas envelopadas em `key_material` dentro do **SQLCipher 4.10.0**. |
| **Signed Prekey & Session Blobs** | X25519 + Double Ratchet | Envelopadas com AAD vinculada à conversa/dispositivo nas tabelas `prekeys`, `sessions` e `skipped_keys`. |
| **Capabilities do Relay** | Tokens aleatórios persistidos apenas por digest **SHA-256** | Comparação constant-time (`crypto/subtle`), escopo estrito (`read_ack`, `write`, `admin`), TTL e revogação. |
| **Duress PIN (Coação)** | Verificador Argon2id independente | Validação na tela de desbloqueio aciona `AntiForensicShredder.panicWipeAccount` (sobreescrita de arquivos + limpeza keyring OS + zeramento em memória). |
| **Seed B (Monero P2P)** | Domínio financeiro separado (`ADR-0003`) | Isolada em processo/carteira própria; `MoneroIsolationPolicy` impede derivação ou compartilhamento com Seed A. |

---

## 2. Limitações Honestas de Memória e Armazenamento Físico

- **Zeroização em Dart VM:** buffers `Uint8List` manipulados em Dart são sobrescritos explicitamente (`fillRange(0, length, 0)`) no encerramento/pânico, porém cópias transitórias criadas pelo GC ou strings imutáveis (`Passphrase` como `String`) só deixam a RAM quando coletadas/encerrado o processo.
- **Wear-leveling em Flash/SSD:** a sobreescrita multi-passagem do `AntiForensicShredder` reduz drasticamente a recuperação lógica no sistema de arquivos, mas **não garante eliminação de páginas físicas realocadas pelo controlador SSD/NAND (flash wear-leveling)** — por isso a proteção primária em repouso repousa na cifra autenticada SQLCipher + KeyVault Argon2id antes da destruição das chaves.
