# ⚡ Benchmark & Desempenho (50 Usuários) — Nix

## 1. Cenário e Ferramenta de Medição (Fase 4)

- Simulador reproduzível implementado em `services/nix_relay/cmd/bench/main.go`:
  - **50 clientes concorrentes** executando `Store` + `Fetch` + `Ack` em ciclos contínuos.
  - Envio periódico de **anexos cifrados de 2 MB** (`-attach-every 30`).
  - Simulação de **reconexões periódicas** (`CloseIdleConnections()` a cada 15 ciclos).
  - Avaliação de pressão do `AutoPruner` com transição de histerese e remoção de expirados.

---

## 2. Resultados Medidos em Execução Controlada (Host Local)

Comando executado em `services/nix_relay`:
```bash
go run ./cmd/bench -clients 50 -duration 15s -attach-every 30
```

Saída observada:
- **Clientes simultâneos:** `50`
- **Duração medida:** `15.184s` (para soak de 60 minutos em ambiente de laboratório: `-duration 60m`)
- **Total de operações completas (Store + Fetch + Ack):** `7.435` (`489.66 ops/s`)
- **Anexos de 2 MB processados:** `216` (`~432 MB` de carga útil binária em 15s)
- **Reconexões executadas:** `466`
- **Erros HTTP / falhas silenciosas:** `0` (`0.0%`)
- **Latência loopback (`httptest` relay):**
  - `p50`: `1.8 ms` *(apenas processamento Relay; rede Tor adiciona 150–900 ms por salto Onion)*
  - `p95`: `404.442 ms` *(picos causados pelos payloads binários de 2 MB concorrentes)*
  - `p99`: `1.4189 s`
- **Memória do processo Go:** `HeapAlloc = 94.28 MB` | `Sys (runtime total c/ buffers 2MB) = 678.40 MB`
- **AutoPruner sob pressão simulada (`88%`):** transição `NORMAL -> SEVERE_RELIEF`, `pruned_count = 6` envelopes expirados, `stored_bytes = 0` ao final após ACKs e expurgo.

---

## 3. Dimensionamento Recomendado de VPS

- **Piso mínimo funcional (até 50 usuários em texto + anexos fragmentados):** `2 vCPU`, `2 GB RAM`, `40 GB SSD NVMe`, `PostgreSQL 17` + `Tor` local com `systemd`.
- **Margem recomendada para rajadas de anexos de 2 MB concorrentes:** `2 vCPU`, **`4 GB RAM`** (para absorver pico `Sys` de buffers base64 + cache PostgreSQL sem acionar OOM) e disco mínimo de `40 GB`.
- **Nota honesta:** O benchmark acima mediu 15,184 segundos diretamente contra o servidor HTTP loopback sem latência multi-salto Tor; para soak completo de 60 minutos sobre Onion Service v3 real, executar `./bench -clients 50 -duration 60m` apontado ao endpoint de laboratório.
