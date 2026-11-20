# 🛡️ Matriz de Privacidade — 21 Requisitos Verificáveis

Cada requisito possui código, guarda fail-closed e vínculo explícito com suíte de testes automatizada ou procedimento auditável em CI/laboratório.

| ID | Eixo | Contexto | Requisito Verificável | Verificação Real no Código / Teste | Situação Atual |
|---|---|---|---|---|---|
| **L-A** | Linkability | Account | Personas distintas (Seed A vs Seed B, Archive vs Mensageria) sem correlação. | `milestone_b_security_test.dart`, `phases_5_to_9_test.dart` (`MoneroIsolationPolicy`, `NixArchiveService`) | **VALIDADO** |
| **L-U** | Linkability | Usage | Tráfego encapsulado via SOCKS5 Tor sem leak DNS local. | `transport_test.dart` (ATYP `0x03` sem DNS local), `https_over_socks_probe_test.dart`, `gate3_two_client_e2ee_test.dart` | **VALIDADO** |
| **L-S** | Linkability | Service | Zero SDKs de telemetria, analytics ou rastreamento de terceiros. | `./scripts/verify_privacy_matrix.sh` (`[L-S]`) em cada push no CI | **VALIDADO** |
| **I-A** | Identifiability | Account | Cadastro local soberano sem telefone, e-mail, SMS ou PII civil. | `./scripts/verify_privacy_matrix.sh` (`[I-A]`), `sovereign_onboarding_flow.dart` | **VALIDADO** |
| **I-U** | Identifiability | Usage | Comportamento fail-closed se SOCKS5 Tor indisponível ou esquema inseguro. | `https_over_socks_probe_test.dart` (`UnsupportedTransportSchemeException`), `embedded_tor_isolation_probe_test.dart` | **VALIDADO** |
| **I-S** | Identifiability | Service | Zero `r.RemoteAddr`, nomes ou IPs de clientes gravados no Relay Go. | `./scripts/verify_privacy_matrix.sh` (`[I-S]`), `persistence_probe_test.go` | **VALIDADO** |
| **N-A** | Nonrepudiation | Account | Chaves X25519 efêmeras / Double Ratchet + Card ID assinável out-of-band. | `core_crypto_test.dart` (`DoubleRatchet`), `gate3_two_client_e2ee_test.dart` | **VALIDADO** |
| **N-U** | Nonrepudiation | Usage | Endereçamento cego de caixas postais e capabilities com hash SHA-256. | `fase2_relay_test.go`, `admin_capabilities_test.go` | **VALIDADO** |
| **N-S** | Nonrepudiation | Service | Expurgo comprovado após TTL (disco & PostgreSQL) e histerese AutoPruner. | `autopruner_test.go`, `probe_test.go`, `fase2_relay_test.go` (`SweepExpired`) | **VALIDADO** |
| **D-A** | Detectability | Account | Geração local da Seed A e inicialização SQLCipher totalmente offline. | `milestone_b_security_test.dart`, `phases_5_to_9_test.dart` | **VALIDADO** |
| **D-U** | Detectability | Usage | Tor integrado (`EmbeddedTorManager`) com sonda real SOCKS5/ControlPort. | `transport_test.dart` (`probeSocks5Proxy`), lab Onion v3 com Tor `0.4.9.15` | **VALIDADO** |
| **D-S** | Detectability | Service | Métricas `/metrics` e `/admin/capabilities` restritas estritamente a loopback. | `main_test.go`, `admin_capabilities_test.go`, `ValidateAdminListenAddr` (`0.0.0.0` recusado) | **VALIDADO** |
| **DD-A** | Data Disclosure | Account | KeyVault Argon2id + SQLCipher 4.10.0 em repouso + proteção OS Keyring / Duress PIN. | `milestone_b_security_test.dart`, `local_database_probe_test.dart`, `key_vault` probe | **VALIDADO** |
| **DD-U** | Data Disclosure | Usage | Cifragem E2EE fail-closed em Outbox, Ratchet, chunks e TLS-over-SOCKS5. | `milestone_b_security_test.dart`, `gate3_two_client_e2ee_test.dart`, `https_over_socks_probe_test.dart` | **VALIDADO** |
| **DD-S** | Data Disclosure | Service | Código aberto, zero plaintexts no relay e zero secrets hardcoded em `.capabilities.json`/logs. | `fase2_relay_test.go`, `database/schema/relay.sql` (`nix.put_envelope`) | **VALIDADO** |
| **U-A** | Unawareness | Account | Escopo estrito entre Seed A (mensageria) e Seed B (Monero) + PQXDH híbrido. | `phases_5_to_9_test.dart` (`MoneroIsolationPolicy`), `pqxdh_release_test.dart` | **VALIDADO** |
| **U-U** | Unawareness | Usage | Bloqueio por padrão de mídia em rádio <=240B, ATAK UDP e magnet DHT em claro. | `offgrid_radio_test.dart`, `phases_5_to_9_test.dart` (`MediaCatalogService`) | **VALIDADO** |
| **U-S** | Unawareness | Service | Alinhamento contínuo entre arquitetura, PostgreSQL 17, limits e docs. | `docs/ARCHITECTURE.md`, `docs/INFRASTRUCTURE.md`, `docs/COLLABORATION_STATUS.md` | **VALIDADO** |
| **C-A** | Noncompliance | Account | Panic Wipe anti-forense + PIN de coação + limpeza keyring (documentado limite wear-leveling SSD). | `anti_forensic_shredder_test.dart`, `shredder_confinement_probe_test.dart`, `milestone_b_security_test.dart` | **VALIDADO** |
| **C-U** | Noncompliance | Usage | Magnet/wallet-RPC clearnet bloqueados se usuário não optar explicitamente por isolamento. | `phases_5_to_9_test.dart` (`MediaCatalogService`, `MoneroIsolationPolicy`) | **VALIDADO** |
| **C-S** | Noncompliance | Service | Protocolo de resposta a incidentes + GitHub Private Vulnerability Reporting ativo + SBOM. | `SECURITY.md`, `docs/INCIDENT_RESPONSE.md`, `scripts/generate_sbom.sh`, GitHub PVR `enabled=true` | **VALIDADO** |

## Novos caminhos locais

Credenciais de relay no SQLCipher. O diagnóstico de microfone descarta PCM em memória e encerra a captura ao sair. O Windows usa credencial do usuário. Os limites da homologação estão no [aceite incremental](FINAL_ACCEPTANCE_REPORT.md).
