# CHANGELOG — Projeto Nix

> Todas as compilações documentadas aqui referem-se a **protótipos experimentais em fase pre-alpha** para validação técnica e testes internos; não constituem lançamentos públicos finais para produção.

---

## [0.4.0-dev] - 2026-11-18

### Identidade Visual, Marca & Design System V4
- Vetorização e isolamento com fundo 100% transparente da nova gravura oficial do Nix (`scripts/brand/process_logo.py`) em variantes `ink`, `light` e `medallion`, distribuídas para desktop, web e mipmaps Android.
- Implementação de **Nix Dark Yellow** (`#08090B` / `#17191E` / `#292C33` / `#FFC928`, padrão inicial) e **Nix Light Yellow** (`#FFFFFF` / `#F6F7F9` / `#E9EBEF` / `#FFC928`), mantendo **AMOLED** (`#000000`) e modo **Sistema** + personalização de cor de destaque em `Configurações → Aparência → Temas`.
- Correção na geração de temas (`NixTheme.buildTheme`) impedindo que a construção do tema escuro alternativo sobrescrevesse `NixColors` durante o uso de **Light Yellow**.

### Mensageiro em 3 Áreas & Janela Desktop
- Reorganização compacta estilo Telegram Desktop (`SpacesDock` com pastas personalizáveis por ícone/cor, reordenação, drag-and-drop e exclusão não-destrutiva + lista de conversas com filtros/busca e **Mensagens Salvas**).
- Remoção de nomes pessoais hardcoded em `MockData` e `UserProfile`.
- Janela desktop iniciando não maximizada (`1152x720`, mínimo `720x500`) com 8 alças de redimensionamento horizontal, vertical e diagonal e remoção de afirmações enganosas de proteção contra fingerprinting por modo janela.

### Card ID, Hover Seguro & Sanitização Local
- Remoção do status `"Assistindo"` e do botão QR duplicado no topo do Card ID; fallback determinístico `NX-XXXX` quando o username estiver em branco.
- Suporte a avatar e capas culturais locais (PNG, JPEG, WebP) com recorte, remoção e sanitização de metadados EXIF/chunks em `LocalImageHelper`.
- Correção do Card ID flutuante em Solicitações: ativação restrita a avatar+nome, posicionamento lateral médio-direito sem obstruir `Recusar` / `Aceitar Chave`, máquina de estados anti-flickering e lockout no botão `X`.
- Enforcement no estado da regra `Privacidade → Visibilidade do Card ID` (`getAuthorizedPeerCardData`).

### Mensageria, Descoberta Starwire, Monero P2P & Offline Share
- Implementação de respostas, edição com selo `"editada"`, fixação/desafixação de mensagens com salto no banner, multi-seleção em lote, encaminhamento inclusive para **Mensagens Salvas** e Emoji Picker pesquisável inserindo na posição do cursor.
- Novo `ConversationInfoPanel` (acionado pelo clique no cabeçalho) indexando mídias, arquivos, áudios, links, mensagens fixadas e busca histórica.
- `ChannelSettingsDialog` ampliado com permissões granulares (incluindo `allowVideos`, `protectPreviews`), QR Code de convite Onion v3 e ações de administração (`applyAdminAction`).
- `GithubDiscoveryView`: gráficos com contagens reais do catálogo Starwire (`4.188` repositórios), ordenação `'trending'`, cópia de URL/`git clone`, diálogo Releases e download ZIP com proteção fail-closed contra vazamento clearnet.
- `MoneroP2pView`: validação de assinatura Ed25519 simulada/verificada (`verifyMoneroOrder`), expiração de ordens, proteção por nonce e aviso não custodial.
- Novo `ShareAppOfflineDialog` (estilo Briar) servindo pacote APK em rede local via HTTP efêmero com verificação SHA-256 e encerramento seguro no `dispose`.

### Núcleo Criptográfico, Transporte Tor Fail-Closed & Nix Relay (Go)
- Implementação completa do pacote Dart `modules/core_crypto` (`NixIdentity`, `SealedEnvelope`, `PassphraseKdf`, `X3dh`, `DoubleRatchet`, `SignedRecord`, `ReplayGuard`) com 5 suítes de teste.
- Implementação do pacote Dart `modules/transport` (`TransportPolicy` fail-closed, `Socks5Connector` ATYP `0x03`, `TorControlClient`, `TorDiagnostics`, `RelayClient`) com 4 suítes de teste.
- Implementação dos endpoints Store-and-Forward (`/healthz`, `/metrics`, `/v1/mailboxes/{id}/envelopes`, `/ack`), carregamento YAML e `AutoPruner` em 4 bandas com histerese em `services/nix_relay`.

---

## [0.2.0] - 2026-11-18

- Refatoração inicial Living AMOLED, catálogo Starwire CC0-1.0 e base do protótipo multiplataforma.
