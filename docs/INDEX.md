# 🔍 Nix Index — Descoberta de Fontes & Magnets

## 1. Separação Mandatória de Três Atividades

O Nix Index estabelece uma distinção rigorosa de segurança entre três ações frequentemente confundidas:

1. **Pesquisar Metadados:** Consultar manifests e títulos textuais de fontes autorizadas via Tor.
2. **Resolver um Magnet Link:** Obter o arquivo de metadados `.torrent` a partir de uma URI `magnet:?xt=...`.
3. **Transferir Conteúdo:** Conectar-se a peers BitTorrent para baixar os bytes reais.

---

## 2. Proteção Contra Vazamento BitTorrent

> ⚠️ **Aviso Oficial (Tor Project):** BitTorrent sobre a rede Tor **não** é seguro e frequentemente expõe o endereço IP real do cliente através de conexões UDP/DHT e tráfego de swarm.

- No perfil privado do Nix, **o cliente nunca ingressa automaticamente em swarms BitTorrent ou ativa DHT pública**.
- A busca e resolução de magnets permanece puramente textual até que o usuário autorize explicitamente uma transferência em um perfil de rede dedicado ou exporte o link para um cliente externo consciente dos riscos.
