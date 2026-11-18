# 🌐 Perfis de Transporte & Política Fail-Closed — Nix

## 1. Perfis de Rede Definidos

| Perfil de Transporte | Mecanismo | Condição de Segurança Mandatória |
|---|---|---|
| **Privado (Padrão)** | Tor Integrado / Onion v3 | **Fail-Closed:** Se o Tor cair, toda conexão é bloqueada. Sem fallback para IP direto. |
| **Local / Proximidade** | Wi-Fi Local (LAN) ou Bluetooth | Ativado apenas sob consentimento. Exibe aviso de identificadores locais visíveis na rede. |
| **IP Direto (Opcional)** | WebSocket TLS 1.3 / WireGuard | Mudança explícita requer confirmação do usuário (alerta: seu IP fica visível para os pares/servidor). |
| **Off-Grid Rádio** | LoRa / Reticulum via BLE | Somente tráfego curto de texto/alertas autorizado. Sem transmissão de arquivos. |

---

## 2. Isolamento de Circuitos SOCKS5

Quando em execução sob Tor, o cliente isola os circuitos SOCKS5 para cada módulo:
- O tráfego do **Nix Messenger** utiliza credenciais de isolamento distintas das consultas do **Nix Media** e das sincronizações da **Nix Wallet**, dificultando correlação de atividade pelo nó de saída Tor ou relay.
