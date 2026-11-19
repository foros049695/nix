#!/usr/bin/env bash
# Script reproduzível de provisionamento do Nix Relay em Debian 13 (Trixie) / Linux hardened
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Execute como root (sudo) para instalar serviço systemd e Onion Service v3." >&2
  exit 1
fi

apt-get update
apt-get install -y --no-install-recommends tor postgresql ufw postgresql-contrib ca-certificates

# Cria usuário dedicado sem shell interativo
if ! id -u nixrelay >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/nix_relay --shell /usr/sbin/nologin nixrelay
fi

install -d -m 0700 -o nixrelay -g nixrelay /var/lib/nix_relay/data
install -d -m 0750 -o root -g nixrelay /etc/nix_relay
install -d -m 0700 -o debian-tor -g debian-tor /var/lib/tor/nix_relay_onion

# Copia binário e systemd unit se disponíveis no diretório atual
if [[ -f ./nix-relay ]]; then
  install -m 0755 ./nix-relay /usr/local/bin/nix-relay
fi
if [[ -f ./deploy/nix-relay.service ]]; then
  install -m 0644 ./deploy/nix-relay.service /etc/systemd/system/nix-relay.service
fi
if [[ -f ./configs/relay.example.yaml ]] && [[ ! -f /etc/nix_relay/relay.yaml ]]; then
  install -m 0640 -o root -g nixrelay ./configs/relay.example.yaml /etc/nix_relay/relay.yaml
fi
if [[ -f ./deploy/torrc.onion.snippet ]]; then
  install -m 0644 ./deploy/torrc.onion.snippet /etc/tor/torrc.d/nix-relay.conf || true
fi

# Firewall restritivo: ZERO tráfego HTTP público direto ao relay (apenas Onion via Tor loopback)
ufw default deny incoming
ufw allow ssh
ufw --force enable

systemctl daemon-reload
systemctl enable --now tor
systemctl enable --now nix-relay

if [[ -f /var/lib/tor/nix_relay_onion/hostname ]]; then
  echo "Onion Service v3 ativo em: $(cat /var/lib/tor/nix_relay_onion/hostname)"
fi
