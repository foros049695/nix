# 🤝 Relação Arquitetural com Briar & Cwtch — Nix

## 1. Inspiração em Briar
- **Local-First:** Persistência primária no dispositivo e arquitetura resiliente a quedas de rede.
- **Transporte Híbrido:** Capacidade de alternar entre Tor para longa distância e Wi-Fi local/Bluetooth para ambientes sem internet.
- **Diferenças Nix:** O Nix adiciona integração nativa com rádio LoRa/Reticulum em Protobuf, ponte ATAK-CIV, carteira Monero isolada e editor canônico Nix Archive.

---

## 2. Inspiração em Cwtch
- **Separação de Perfis:** Isolamento estrito entre personas sem identificador unificado.
- **Onion Services:** Utilização de serviços Tor v3 para comunicação ponto a ponto sem servidores centrais permanentes.
- **Diferenças Nix:** O Nix define infraestrutura de relay temporário dinâmico com auto-limpeza em histerese e catálogo modular de mídia e indexação.
