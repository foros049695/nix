# 📡 Protocolo de Comunicação & Schemas — Nix

## 1. Estrutura de Envelopes

As mensagens trocadas entre clientes e relays utilizam schemas padronizados em Protocol Buffers v3 (`proto/nix/v1/`).

### Envelope de Mensagem (`message.proto`)
- `version`: Inteiro indicando a revisão do protocolo (atualmente `1`).
- `recipient_box`: Hash da chave pública de entrega (caixa de correio opaca).
- `ephemeral_pubkey`: Chave pública efêmera X25519 para a catraca de chaves.
- `nonce`: Nonce único de 192 bits para XChaCha20-Poly1305.
- `encrypted_payload`: Texto e metadados cifrados ponta a ponta.
- `created_at`: Timestamp Unix de criação.
- `ttl_seconds`: Tempo de vida solicitado (máximo 604800 segundos = 7 dias).

---

## 2. Mitigação de Ataques Replay & Reordenação

- Cada sessão Double Ratchet mantém contadores sequenciais de mensagens e cadeias de saltos de chaves (*skipped keys*).
- O relay armazena mensagens por ID de envelope temporário com deduplicação de mensagens idênticas.
- O cliente decifra e valida a integridade antes de processar eventos na interface.
