# Módulo `core_crypto` (`nix_core_crypto`)

Primitivas criptográficas em Dart puro sobre `package:cryptography` para o Project Nix.

## Primitivas Implementadas

| Classe | Algoritmo / Função | Papel |
|---|---|---|
| `NixIdentity` | `Ed25519` + `X25519` | Chaves compartimentalizadas de assinatura e troca DH, além de `publicId` determinístico (`NIX-XXXX-...`). |
| `SealedEnvelope` | `XChaCha20-Poly1305` | Criptografia autenticada (AEAD) com nonce estendido de 24 bytes e suporte a AAD. |
| `PassphraseKdf` | `Argon2id` | Derivação de chaves resistente a GPU/ASIC para cofre e bloqueio local. |
| `X3dh` | `X25519` + `HKDF-SHA256` | Estabelecimento assíncrono de segredo compartilhado inicial (3-DH e 4-DH com one-time prekey). |
| `DoubleRatchet` | `X25519` + `HMAC-SHA256` + `XChaCha20-Poly1305` | Avanço contínuo de cadeias (forward secrecy e recuperação pós-compromisso) com cache limitado para entrega fora de ordem. |
| `SignedRecord` / `ReplayGuard` | `Ed25519` + cache de nonce com TTL | Assinatura canônica de anúncios/registros com expiração e proteção anti-replay. |

## Verificação Local

```bash
dart analyze
dart test
```

> **Escopo:** Implementação em Dart puro voltada a prototipagem verificável e testes unitários. Para endurecimento contra ataques de canal lateral ou zeroização garantida em memória nativa, integradores devem acoplar FFI dedicada (`libsodium`/Rust) nas camadas de produção.
