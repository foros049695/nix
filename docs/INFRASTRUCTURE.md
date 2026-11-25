# 🖥️ Infraestrutura & Hospedagem — Projeto NIX

## 1. Especificação da VPS de Referência

Baseado nos testes de integração e benchmark da Fase 4:
- **CPU:** 2 vCPU (x86_64 ou ARM64)
- **RAM:** 2 GB mínimo (4 GB recomendado para rajadas concorrentes de anexos de 2 MB com folga de buffer)
- **Disco:** 40 GB SSD / NVMe
- **Sistema Operacional:** Debian 13 (Trixie) ou Alpine Linux hardened (`services/nix_relay/deploy/provision_vps.sh`)
- **Persistência:** Arquivos atômicos JSON (`BlindMailboxStore`) ou **PostgreSQL 17+ (`pgcrypto`)** via `storage.postgres_dsn` / `NIX_RELAY_PG_DSN`

---

## 2. Separação de Listeners & Tor Onion v3

1. **Superfície Pública Onion (`NewMux`):**
   - Vinculada em `127.0.0.1:8080` e exposta exclusivamente via Tor `HiddenServicePort 80 127.0.0.1:8080` (`services/nix_relay/deploy/torrc.onion.snippet`).
   - Firewall (`ufw`/`nftables`) bloqueia todo tráfego HTTP externo direto; apenas SSH administrativo e rede Tor de saída são permitidos.
2. **Listener Administrativo & Métricas (`NewAdminMux`):**
   - `ValidateAdminListenAddr` recusa iniciar se `metrics.listen_addr` não apontar para endereço loopback (`127.0.0.1`, `::1` ou `localhost`).
   - Expõe `/metrics` (Prometheus sem identificadores/IPs) e `/admin/capabilities` (`POST` / `DELETE` para provisionamento e revogação de capabilities SHA-256 com escopo).
3. **Hardening Systemd (`services/nix_relay/deploy/nix-relay.service`):**
   - Executa sob usuário sem shell (`nixrelay`), com `NoNewPrivileges=yes`, `PrivateTmp=yes`, `ProtectSystem=strict`, `ProtectHome=yes` e nenhuma capability Linux (`CapabilityBoundingSet=`).
4. **Backup e Restauração PostgreSQL (`database/examples/backup_metadata.sh`, `restore_metadata.sh`):**
   - Backups de metadados excluem estritamente payloads (`--exclude-table-data=nix.envelopes`).
   - O script de restauração reconcilia contadores (`used_bytes=0`, `pending_count=0`) e purga capabilities expiradas/revogadas antes de reabrir o serviço.


### Cotas do relay em PostgreSQL

A inicialização padrão do relay aplica a migração `relay_002_durable_quota.sql`.
Quando o banco é provisionado separadamente, aplique a migração após a
`relay_001_initial.sql` e conceda ao papel do relay `EXECUTE` na função
`nix.put_envelope_with_quota(text,uuid,bytea,integer,bytea,bigint)`.

Atualize todas as instâncias que compartilham o banco no mesmo rollout. A cota
soma os bytes pendentes e ainda válidos do mesmo hash de token em todas as
mailboxes. ACK e expiração liberam o consumo. Envelopes anteriores à migração
seguem sujeitos aos limites global e da mailbox. O vínculo a um token de cota
começa nas novas inserções.

---

## 3. Mapeamento Arquitetural: RustDesk (HBBS / HBBR) vs. Projeto Nix

Ao analisar soluções de conexão soberana e remota como o [RustDesk Server](https://github.com/rustdesk/rustdesk-server), identificam-se dois papéis fundamentais de infraestrutura:

| Conceito RustDesk | Papel Funcional | Equivalente Arquitetural no Nix | Protocolo e Segurança Nix |
|---|---|---|---|
| **HBBS** | Servidor de Identificação, Descoberta e Rendezvous (registro de ID público, negociação de sessão, sinalização NAT punching) | **Diretório de Identidades & Descoberta Onion v3** | Endpoints Onion v3 efêmeros, verificação Ed25519, chaveiro de identidades e rendezvous soberano sem vazamento de IP real. |
| **HBBR** | Servidor de Relay (retransmissão cega de tráfego quando a conexão direta não é viável) | **Nix Relay (`services/nix_relay`)** | Store-and-forward cego em Go com autopruner de 4 estágios, histerese de RAM/disco, envelopes E2EE XChaCha20-Poly1305 e confirmação atômica via `POST /ack`. |
| **Conexão Direta (P2P)** | Enlace direto ponta a ponta sem intermediários | **Conexão P2P Direta (Onion mútuo ou LAN)** | Envelopes cifrados via Double Ratchet transitando direto entre nós autorizados, ativando fallback de relay somente sob contenção de rota. |

> **Nota de Auditoria:** Os binários do RustDesk operam sobre protocolos próprios para streaming de desktop remoto. No Nix, adota-se o mesmo modelo conceitual desacoplado (Rendezvous vs. Relay cego), porém utilizando transporte com fail-closed para Tor Onion v3, criptografia de envelope Double Ratchet com XChaCha20-Poly1305 e sem custódia de dados.

---

## 4. Auditoria da Infraestrutura de Rede e Comunicações do Nix

A tabela abaixo documenta o status medido e a maturidade de cada módulo de rede:

| Componente | Função | Implementação | Estado Real | Requisitos / Notas |
|---|---|---|---|---|
| **`services/nix_relay`** | Relay Store-and-Forward cego | Go (mux, autopruner, postgres/memory) | `IMPLEMENTED` / `VERIFIED_LOCAL` | Executa localmente atrás do Tor em `127.0.0.1:8080`. Pronto para deploy em VPS. |
| **Tor Onion v3 Client** | Túnel fail-closed para o Relay | Dart `Socks5Connector` + `SocksSocket` | `VERIFIED_LOCAL` | Testado com daemon Tor local ativo em `127.0.0.1:9050`. Proteção fail-closed estrita. |
| **P2P Direto Onion** | Troca direta entre serviços ocultos | Dart `SealedEnvelope` + sockets Tor | `IMPLEMENTED` / `VERIFIED_LOCAL` | Comunicação direta entre dois nós com endereços .onion mútuos sem intermediários. |
| **P2P Rede Local (Wi-Fi / Ethernet)** | Sockets TCP locais e descoberta opt-in | Dart TCP Socket Server/Client | `IMPLEMENTED` / `VERIFIED_LOCAL` | Requer que ambos os nós estejam na mesma sub-rede e autorizem descoberta local. |
| **Bluetooth Low Energy (BLE)** | Enlace de proximidade BTP Mesh | `BluetoothMeshManager` + Kotlin Bridge | `VERIFIED_LOCAL` / `VERIFIED_REAL_DEVICE` (Android) | Fragmentação de pacotes NIXB (<= 64 KiB), scanner e advertiser GATT testados no Android. Exige hardware BLE físico. |
| **Rádio Off-Grid (LoRa / RNode)** | Transmissão de emergência de texto curto | `RadioPacketCodec` + `DutyCycleGovernor` | `VERIFIED_LOCAL` / `PARTIAL` | Codec com teto estrito de 240 bytes, rejeição de mídia binária e controle de duty cycle. Exige hardware USB-OTG/BLE KISS conectado. |

---

## 5. Arquitetura de Rede Híbrida do Nix (Camadas A–G)

O Projeto Nix adota uma arquitetura em 7 camadas hierárquicas coordenadas por `HybridNetworkCoordinator`:

1. **Camada A — Servidor Principal VPS:** Comunicação assíncrona blind store-and-forward via Tor Onion v3.
2. **Camada B — Comunicação P2P Direta:** Túnel autenticado direto ponta a ponta quando ambos os nós estão online.
3. **Camada C — Relay Alternativo / Secundário:** Nó de contingência cego ativado em caso de falha da VPS principal.
4. **Camada D — Rede Local Wi-Fi:** Troca direta na mesma rede Wi-Fi sem depender da internet pública (opt-in).
5. **Camada E — Ethernet Cabeada:** Transporte LAN de alta velocidade e baixa latência para redes locais seguras.
6. **Camada F — Bluetooth Low Energy (Mesh):** Comunicação sem infraestrutura por proximidade (raio de até 30m).
7. **Camada G — Rádio Off-Grid (LoRa / Reticulum):** Mensagens curtas críticas de até 240 bytes via hardware dedicado.

### Failover Real e Fila Offline Criptografada (Seção 11)

Quando a conexão com o servidor principal ou a internet for interrompida:
1. O envelope cifrado via Double Ratchet é retido atomicamente na tabela SQLite `outbox` local com o status **`waiting_route`** (`Aguardando conexão com o destinatário`).
2. O coordenador tenta sucessivamente as camadas ativas seguintes (Relay secundário -> P2P -> Wi-Fi/Ethernet -> BLE -> Rádio).
3. Se nenhuma rota física viável estiver disponível, o aplicativo **não declara falsamente que a mensagem foi enviada ou entregue**: ela permanece com o badge relógio e tooltip explicativo.
4. Assim que qualquer camada operacional recuperar conexão, a fila offline é drenada de forma idempotente com proteção contra replay (deduplicação por hash SHA-256 e UUID de entrega).
