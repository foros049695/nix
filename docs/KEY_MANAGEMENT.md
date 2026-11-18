# 🔑 Gerenciamento de Chaves & Ciclo de Vida — Nix

## 1. Inventário de Chaves Criptográficas

| Tipo de Chave | Algoritmo | Finalidade | Escopo de Armazenamento |
|---|---|---|---|
| **Identity Key (IK)** | Ed25519 | Identidade de rede no mensageiro | SQLCipher local |
| **Signed Prekey (SPK)** | X25519 | Handshake inicial de sessão | Publicada no relay com rotação periódica |
| **One-Time Prekeys (OPK)** | X25519 | Proteção de sessões assíncronas | Consumidas e eliminadas após uso |
| **Ratchet Keys** | X25519 | Avanço da catraca Double Ratchet | Efêmeras em memória; eliminadas ao avançar |
| **Archive Persona Key** | Ed25519 | Assinatura de artigos canônicos | Cofre separado do Archive |
| **Monero Spend & View Keys** | Monero ed25519 | Transações e auditoria financeira | Processo isolado da carteira (Seed B) |

---

## 2. Exclusão Criptográfica & Memória Segura

- Buffers contendo chaves privadas são limpos via `sodium_memzero` ou rotina equivalente que impeça otimizações do compilador.
- A destruição das chaves de descriptografia do banco SQLCipher invalida o acesso aos dados em disco sem necessidade de sobrescrita física completa de memória flash.
