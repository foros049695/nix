# 🔮 Trilha Criptográfica Pós-Quântica (PQXDH) — Nix

## 1. Arquitetura do Handshake Híbrido Implementado (`modules/core_crypto/lib/nix_pqxdh.dart`)

- O Nix utiliza **X3DH + Double Ratchet** como base clássica autenticada em produção e disponibiliza o combinador híbrido **`PqxdhCombiner` (`Nix-PQXDH-Hybrid-v1`)** para acoplamento modular de algoritmos KEM pós-quânticos (ex.: ML-KEM-768 / FIPS 203):
  - **Entrada IKM:** concatenação estrita `K_X3DH (32 bytes) || K_PQKEM (>= 32 bytes)`.
  - **Vínculo ao Transcript (Nonce/Salt):** `SHA-256("Nix-PQXDH-Hybrid-v1" || IK_Initiator_Ed25519 || IK_Responder_Ed25519 || Ciphertext_PQKEM)`.
  - **Rejeição Fail-Closed:** segredos KEM zerados (`all zero`) ou truncados disparam erro imediato antes de derivar a chave raiz.
- **Proteção Contra Downgrade:** identidades de ambas as pontas e o ciphertext KEM participam do salt HKDF; comprometer apenas a primitiva clássica **ou** apenas a primitiva PQ não permite reconstruir a chave híbrida resultante.
- **Restrição em Enlace Rádio (`<= 240B`):** o enlace LoRa/Meshtastic opera estritamente com frames compactos pós-handshake (`RadioPacketCodec`), enquanto handshakes PQXDH completos trafegam via Tor Onion v3 ou Bluetooth Mesh (`NIXB`).
