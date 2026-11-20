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
