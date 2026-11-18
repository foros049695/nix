# 📦 Réplicas Voluntárias & Persistência — Nix Archive

## 1. Réplicas Opt-In

- O Nix Archive não impõe armazenamento perpétuo aos relays de mensagens.
- A persistência duradoura de publicações depende de nós voluntários que realizam **pinning** explícito de CIDs.
- Um nó pode a qualquer momento revogar a replicação de um objeto sem comprometer a integridade criptográfica da rede.

---

## 2. Riscos de DHT Pública & Mitigação

- Conectar diretamente a DHTs públicas do IPFS ou BitTorrent pode vazar interesses e histórico de navegação.
- No Nix, consultas e sincronizações de réplicas utilizam proxies onion ou nós indexadores confiáveis autorizados pelo usuário.
