# GUIA DE IMPLANTAÇÃO E OPERAÇÃO DE RELAYS NIX SOB TOR ONION V3
**Documento Técnico:** Nix Network Operations Manual  
**Alvo:** Servidores de Relay Assíncronos Nix (`services/nix_relay`)  
**Topologia:** Tor Hidden Service v3 com Transporte Criptografado  

---

## 1. VISÃO GERAL DA ARQUITETURA DE RELAY

O **Nix Relay** é um serviço postal assíncrono projetado para receber, armazenar temporariamente e despachar envelopes criptografados sem nunca ter acesso às chaves de sessão ou ao conteúdo em texto plano.

### Princípios de Operação:
1. **Zero Logging de IP:** Todas as conexões de clientes e outros nós chegam exclusivamente através de um circuito Tor Onion v3.
2. **Retenção Efêmera por Padrão (TTL 7 Dias):** Envelopes expiram e são descartados progressivamente por histerese de memória/disco.
3. **Fail-Closed de Rede:** Se o daemon Tor parar ou a interface do Hidden Service falhar, o serviço não tenta escutar em interfaces públicas (clearnet).

---

## 2. REQUISITOS DE HARDWARE E SISTEMA OPERACIONAL

| Recurso | Mínimo Recomendado | Produção para Alta Demanda |
|---|---|---|
| **SO** | Debian 12/13 ou Ubuntu 22.04/24.04 LTS (Kernel 6.1+) | Debian 13 hardened |
| **CPU** | 2 vCPUs (x86_64 ou ARM64) | 4+ vCPUs com aceleração AES/SHA |
| **RAM** | 2 GB | 4 GB a 8 GB |
| **Armazenamento** | 20 GB SSD/NVMe (banco temporário de envelopes) | 100 GB NVMe |
| **Banda** | 10 Mbps simétricos | 100+ Mbps |

---

## 3. INSTALAÇÃO E CONFIGURAÇÃO DO DAEMON TOR

### Passo 3.1: Instalar o pacote oficial do Tor Project
```bash
sudo apt update && sudo apt install -y apt-transport-https gnupg curl

# Adiciona o repositório oficial do Tor Project
curl -fsSL https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/torproject.gpg

echo "deb [signed-by=/etc/apt/trusted.gpg.d/torproject.gpg] https://deb.torproject.org/torproject.org $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/tor.list

sudo apt update && sudo apt install -y tor deb.torproject.org-keyring
```

### Passo 3.2: Configurar o Serviço Oculto v3 (`/etc/tor/torrc`)
Edite o arquivo `/etc/tor/torrc` com as diretivas de isolamento estrito:

```text
## Nix Relay Tor Onion v3 Configuration
RunAsDaemon 1
DataDirectory /var/lib/tor

# Desativa completamente operação como nó de saída ou relé público clearnet
ExitRelay 0
ExitPolicy reject *:*
ClientOnly 0

# Configuração do Hidden Service v3 para o Relay Nix
HiddenServiceDir /var/lib/tor/nix_relay_service/
HiddenServiceVersion 3
HiddenServicePort 8443 127.0.0.1:8443

# Proteções contra ataques de DoS no Onion Service
HiddenServicePoWDefensesEnabled 1
HiddenServicePoWQueueRate 25
HiddenServicePoWQueueBurst 100

# Limitação de conexões
MaxOnionsPending 100
ConnLimit 4096
```

### Passo 3.3: Iniciar o Tor e Obter o Endereço `.onion`
```bash
sudo systemctl restart tor
sudo systemctl enable tor

# Aguarda inicialização do circuito
sleep 5

# Extrai o endereço Onion v3 gerado
sudo cat /var/lib/tor/nix_relay_service/hostname
# Exemplo de saída:
# 7e3a9f01c45b289dabcdef0123456789abcdef0123456789abcdef0123456789.onion
```

> **IMPORTANTE:** Faça backup seguro das chaves criptográficas em `/var/lib/tor/nix_relay_service/hs_ed25519_secret_key`. Essa chave define permanentemente a identidade do relay.

---

## 4. COMPILAÇÃO E IMPLANTAÇÃO DO NIX RELAY

### Passo 4.1: Compilar o Binário do Serviço
No repositório do Projeto Nix:
```bash
cd services/nix_relay
# Se for a implementação em Go:
go build -ldflags="-s -w" -o /opt/nix/bin/nix_relay ./cmd/relay
# Se for em Rust:
# cargo build --release && cp target/release/nix_relay /opt/nix/bin/nix_relay
```

### Passo 4.2: Arquivo de Configuração do Relay (`/etc/nix/relay.conf`)
```ini
[relay]
bind_address = "127.0.0.1"
bind_port = 8443
onion_hostname_file = "/var/lib/tor/nix_relay_service/hostname"

[storage]
data_dir = "/var/lib/nix/mailbox"
max_mailbox_size_mb = 10240
envelope_ttl_days = 7
purge_interval_minutes = 60

[network]
max_simultaneous_connections = 2048
max_envelope_size_kb = 1024
rate_limit_requests_per_minute = 120
fail_closed = true
```

---

## 5. GERENCIAMENTO COMO SERVIÇO SYSTEMD

Crie o arquivo `/etc/systemd/system/nix-relay.service`:

```ini
[Unit]
Description=Nix Network Onion v3 Asynchronous Relay
After=network.target tor.service
Requires=tor.service

[Service]
Type=simple
User=nixrelay
Group=nixrelay
ExecStart=/opt/nix/bin/nix_relay --config /etc/nix/relay.conf
Restart=always
RestartSec=5s

# Hardening e Sandbox no Systemd
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictRealtime=true
RestrictNamespaces=true
MemoryDenyWriteExecute=true
ReadWritePaths=/var/lib/nix/mailbox

[Install]
WantedBy=multi-user.target
```

Ative e inicie o serviço:
```bash
sudo useradd -r -s /bin/false nixrelay
sudo mkdir -p /var/lib/nix/mailbox
sudo chown -R nixrelay:nixrelay /var/lib/nix

sudo systemctl daemon-reload
sudo systemctl enable nix-relay
sudo systemctl start nix-relay
sudo systemctl status nix-relay
```

---

## 6. HARDENING DO SISTEMA E FIREWALL FAIL-CLOSED

Para garantir que o servidor de relay jamais aceite conexões diretas via clearnet na porta do serviço, configure o `iptables` ou `nftables`:

```bash
# Permite tráfego local (loopback) entre Tor e nix_relay
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT

# Permite tráfego SSH restrito (para administração remota)
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Bloqueia qualquer tráfego de entrada externo na porta 8443
sudo iptables -A INPUT -p tcp --dport 8443 -j DROP

# Permite saída estabelecida para o daemon Tor
sudo iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
```

---

## 7. MONITORAMENTO E ROTINAS OPERACIONAIS

### Logs de Operação
```bash
# Monitora a fila de entrega postal e expurgo
journalctl -u nix-relay -f --no-tail
```

### Verificação do Status do Circuito Tor
```bash
sudo -u debian-tor nyx
```

### Procedimento de Rotação de Envelopes
A cada 60 minutos, o worker de manutenção executa:
1. `SELECT id FROM envelopes WHERE created_at < NOW() - INTERVAL '7 days'`: marcação para remoção.
2. Sobrescrita de blocos de disco alocados (`shred` de buffers).
3. `VACUUM` do banco SQLite de caixas postais para evitar inchaço de arquivos no sistema de arquivos.
