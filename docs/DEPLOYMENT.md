# 🚀 Guia de Implantação Reproduzível — Nix

## 1. Builds Reproduzíveis

- Os binários do Nix Relay e do Nix Client são compilados utilizando contêineres OCI com ambientes herméticos e timestamps fixos (`SOURCE_DATE_EPOCH`).
- Toda release publicada no GitHub inclui arquivo de hashes `SHA256SUMS` assinado digitalmente com `minisign`.

---

## 2. Deploy do Relay em VPS Debian/Alpine

```bash
# 1. Instalar Tor
sudo apt update && sudo apt install -y tor

# 2. Configurar Onion Service no /etc/tor/torrc:
# HiddenServiceDir /var/lib/tor/nix_relay/
# HiddenServicePort 80 127.0.0.1:8080

# 3. Executar o binário do Nix Relay
./bin/nix_relay -config configs/relay.yaml
```
