# 🖥️ Infraestrutura & Hospedagem — Projeto NIX

## 1. Especificação da VPS de Referência

A configuração inicial de referência visa provar que o Nix Relay opera com alta eficiência e baixo custo:
- **CPU:** 2 vCPU (x86_64 ou ARM64)
- **RAM:** 2 GB
- **Disco:** 40 GB SSD / NVMe
- **Sistema Operacional:** Alpine Linux ou Debian Minimal
- **Orçamento Alvo:** US$ 5 a US$ 10 / mês
- **Capacidade Inicial:** 50 usuários simultâneos com tráfego ativo de mensagens e anexos.

---

## 2. Separação de Serviços

A VPS de referência destina-se **exclusivamente** ao Relay de mensagens temporárias e ao bucket S3/MinIO local.
- **Não inclui:** Nó completo de Monero (XMR), servidores de streaming de vídeo, renderizadores pesados ou indexadores públicos de torrents. Esses serviços exigem dimensionamento e nós dedicados independentes.

---

## 3. Endurecimento do Servidor

1. **Firewall com `nftables`:**
   - Bloquear todo o tráfego de entrada, exceto a porta local do daemon Tor e porta SSH administrativa restrita por chave Ed25519.
   - Desabilitar totalmente login por senha (`PasswordAuthentication no`).
2. **Tor Hidden Service:**
   - O relay escuta em um socket local associado a um Onion Service v3 configurado no `/etc/tor/torrc`.
   - O endereço IP público da VPS não precisa ser exposto para os clientes Nix.
3. **Métricas Prometheus Seguras:**
   - Métricas expostas apenas em `127.0.0.1:9090` (ou acessíveis via SSH tunnel).
   - Proibido o uso de labels como IP, User ID, Message ID ou dados de sessão.
   - Apenas contadores agregados (ex: `nix_relay_active_connections_total`, `nix_relay_disk_bytes_used`).
