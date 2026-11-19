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

1. **Validação em Hardware Android Real (APK já compilado com `libtor.so` + `libsqlcipher.so` + TEE + BLE + RNode):**
   - Concluir o **Onboarding + SQLCipher + AndroidKeyStore TEE/StrongBox** nos 2 celulares físicos (criando Seed A com frase-passe vazia para validar vínculo automático no TEE e reabertura após reinicialização).
   - Confirmar `PRAGMA cipher_version` não nulo com `requireEncryption: true` (ativo por padrão fora de `FLUTTER_TEST`) e `allowBackup=false` + `data_extraction_rules.xml`.
   - Assinar release de produção com keystore dedicada (substituindo a assinatura de desenvolvimento atual) e manifesto Ed25519 antes de distribuição pública.

---

## 3. Hardware Off-Grid (Bluetooth BLE e Rádio LoRa)

1. **Bluetooth BLE Físico (`NIXB`):**
   - Driver nativo `NixBleMeshController.kt` (GATT Server/Client + Advertiser + Scanner) já empacotado no APK e integrado ao **Modo Off-Grid Estrito (BLE / LoRa · Zero Internet)**; **pendente de validação física entre os 2 celulares Android reais** (descoberta RSSI e troca bidirecional de envelopes `NIXB` assinados).
2. **Rádio LoRa / Reticulum RNode:**
   - Driver nativo `NixRNodeRadioController.kt` (USB-OTG Serial + BLE Nordic UART KISS) já empacotado no APK; **validado até o momento apenas o enquadramento local `NX` (`<=240B`, CRC16-CCITT) + `KissFrameCodec`**, pendente de teste TX/RX real com dois transceptores LoRa físicos.

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
