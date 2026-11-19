# Próximos Passos Fora do Escopo de Laboratório Local — Projeto Nix

**Data:** 19/11/2026  
**Pré-requisito atendido:** Todas as correções P0 e P1 executáveis em ambiente local foram implementadas, integradas e verificadas por suítes reproduzíveis (`verify_privacy_matrix.sh`, `go test -race`, `core_crypto` 10/10, `transport` 22/22 e `nix_client` 89/89).

Este plano cobre exclusivamente as etapas que dependem de **infraestrutura externa, hardware físico ou auditoria de terceiros**.

---

## 1. Infraestrutura Externa (VPS Debian 13 & Rede Tor Pública)

1. **Provisionamento do Relay em VPS Debian 13:**
   - Executar `services/nix_relay/deploy/provision_vps.sh` em servidor dedicado (mínimo recomendado em `docs/PERFORMANCE.md`: `2 vCPU`, `4 GB RAM`, `40 GB NVMe`).
   - Configurar PostgreSQL 17 com `database/schema/relay.sql` e confirmar isolamento do listener admin em `127.0.0.1`.
   - Configurar `torrc.onion.snippet` para expor exclusivamente a API pública (`/v1/mailboxes/...`) via Onion Service v3.
2. **Soak Test Multi-Salto (60 minutos):**
   - Executar `services/nix_relay/cmd/bench` com `-clients 50 -duration 60m` roteado através do circuito Onion v3 real, validando latência p95/p99, estabilidade de memória e ciclos do `AutoPruner`.
3. **Teste Interativo entre Dois Clientes Reais via Tor Público:**
   - Conectar duas máquinas físicas distintas ao Onion Service v3 da VPS usando o cliente desktop Linux com Tor embutido, trocando mensagens de texto, anexos cifrados e rotação de grupos.

---

## 2. Dispositivos Móveis Físicos (Android APK + NDK)

1. **Build de Release Android Assinada:**
   - Compilar APK ARM64/ARMv7 com `sqlcipher_flutter_libs` e empacotamento do binário Tor ARM para Android.
   - Gerar manifesto assinado Ed25519 via `scripts/sign_release.dart` (`nix-client.apk.sig.json`) e validar instalação offline via `ShareAppOfflineDialog` entre dois aparelhos na mesma rede Wi-Fi/hotspot.
2. **Validação em Hardware Android Real:**
   - Confirmar `PRAGMA cipher_version` não nulo com `requireEncryption: true` (`NIX_REQUIRE_SQLCIPHER=true`).
   - Validar proteção de chave em `AndroidKeyStore` TEE/StrongBox (`MainActivity.kt`), comportamento sob reinicialização do aparelho e desativação efetiva de backup na nuvem (PR `#16`).

---

## 3. Hardware Off-Grid (Bluetooth BLE e Rádio LoRa)

1. **Bluetooth Mesh (`NIXB`):**
   - Integrar driver BLE nativo (Linux BlueZ / Android BluetoothGatt) à camada `modules/transport/lib/nix_bluetooth_mesh.dart` e validar descoberta + troca de envelopes cifrados entre dois celulares/laptops fora da rede.
2. **Rádio LoRa / Meshtastic / Reticulum RNode:**
   - Acoplar transporte serial/USB/BLE ao `RadioPacketCodec` (`<=240B`, CRC16-CCITT) e `DutyCycleGovernor`, validando envio real entre dois transceptores LoRa físicos.

---

## 4. Integrações Externas Não Custodiais e Replicação

1. **Monero Wallet RPC Externo (`Seed B`):**
   - Conectar o cliente a um processo `monero-wallet-rpc` externo em rede `stagenet` (restrito a loopback ou `.onion` via `MoneroIsolationPolicy`), validando consulta de saldo somente leitura e fluxo não custodial sem compartilhar material da `Seed A`.
2. **Conectores Opt-In de Mídia via Tor:**
   - Implementar os executores HTTP sobre SOCKS5 (`RawSecureSocket`) para `OptInMediaConnectorKind` (`tmdb`, `anilist`, `jellyfin`) mantendo todos desativados por padrão.
3. **Replicação Distribuída do Nix Archive:**
   - Integrar sincronização voluntária de objetos canônicos `nix.archive.article.v1` entre réplicas externas S3/IPFS com validação Ed25519 + SHA-256 na ingestão.

---

## 5. Governança, Release e Auditoria Externa

1. **Publicação e Merge no GitHub:**
   - Revisar `git diff` completo com o proprietário do repositório antes de qualquer commit, branch, Pull Request ou merge em `origin/main`.
2. **SBOM e Auditoria Criptográfica Independente:**
   - Atualizar SBOM CycloneDX 1.5 (`./scripts/generate_sbom.sh`) junto às builds assinadas e submeter o núcleo criptográfico + mensageria transacional a auditoria independente antes de qualquer release beta pública.
