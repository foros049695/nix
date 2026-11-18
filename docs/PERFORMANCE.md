# ⚡ Benchmark & Desempenho (50 Usuários) — Nix

## 1. Hipótese de Carga da Fase 4

- **Cenário de Teste:** 50 nós ativos simultaneamente conectados via Onion Services ao Relay em uma VPS de 2 vCPU e 2 GB RAM.
- **Tráfego Simulado:**
  - Envio contínuo de mensagens de texto (1 mensagem a cada 5 segundos por par).
  - Envio intermitente de anexos de imagem (2 MB) a cada 2 minutos.
  - Reconexões periódicas de nós simulando perda de conectividade Tor/móvel.

---

## 2. Metas de Métricas (SLOs)

- **RSS da Aplicação Relay (Go):** `< 500 MB` estável após 60 minutos de teste.
- **Uso de CPU:** Médio `< 40%` das 2 vCPUs durante picos de sincronização.
- **Latência de Entrega (Rede Tor):**
  - p50: `< 1500 ms`
  - p95: `< 5000 ms`
- **Taxa de Perda Silenciosa:** `0.0%`. Mensagens não entregues devem permanecer na fila store-and-forward até atingir o TTL.
