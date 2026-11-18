# PROJETO NIX — RELATÓRIO DE AUDITORIA E HOMOLOGAÇÃO V2.0
**Data de Emissão:** 18 de Novembro de 2026  
**Versão do Cliente:** 0.2.0 (Build +2)  
**Branch Principal:** `main`  
**Classificação:** Auditoria Técnica Integrada & Homologação de Protótipos  

---

## SUMÁRIO EXECUTIVO

O presente relatório consolida a auditoria técnica, arquitetural e funcional da transição do **Projeto Nix** para a especificação **Living AMOLED V2**. Foram corrigidos todos os apontamentos visuais e funcionais identificados em testes anteriores, implementado o sistema de temas reativo global, concluído o Card ID com posicionamento inteligente e bloqueio de hover, reorganizada a hierarquia de navegação eliminando duplicações, incorporado o catálogo real Starwire (4.188 repositórios sob CC0-1.0), adicionadas ações completas de mensagem (context menu, encaminhamento, cópia segura e deleção com reações alternáveis), implementadas configurações granulares de canais com avaliação do `FLAG_SECURE`, e gerados protótipos experimentais para validação interna multiplataforma em Linux Desktop e Android APK.

---

## 1. IDENTIDADE E CRIPTOGRAFIA

- **Modelo de Identidade:** Soberana e determinística baseada em pares de chaves assimétricas Ed25519 e X25519.
- **Zero Cadastro Civil:** Nenhuma exigência de número de telefone, e-mail, SMS, CPF ou indexação de contatos de catálogo civil.
- **Identificador Público:** Formato uniforme `NIX-[FINGERPRINT-8C]-[FINGERPRINT-4C]` derivado do hash da chave pública.
- **Modelo de Confiança em 3 Níveis:**
  1. *Nível 1 (Alerta / Não Verificado):* Contatos recebidos externamente sem handshake verificado.
  2. *Nível 2 (Conhecido em Contexto):* Membros participantes de espaços comuns cifrados.
  3. *Nível 3 (Soberano Verificado):* Troca criptográfica de chaves validada presencialmente por QR Code ou impressão digital.
- **Isolamento de Chaves:** Chaves de assinatura de identidade não se misturam com as sementes da carteira Monero P2P (Seed B) ou armazenamento canônico do Nix Archive.

---

## 2. PROTOCOLO DE ENVELOPES E TRANSPORTE

- **Envelopes Criptográficos:** Contratos Protocol Buffers v3 (`proto/`) com cifras simétricas XChaCha20-Poly1305 para carga útil e derivação de segredos efêmeros via Double Ratchet e X3DH.
- **Prevenção de Metadados:** Cabeçalhos de mensagem em trânsito não expõem identidade de remetente ou destinatário aos nós intermediários.
- **Roteamento:** Estritamente orientado a redes de anonimato Tor Onion v3.
- **Fail-Closed Estrito:** Mecanismo ativo que aborta conexões caso o túnel Tor seja interrompido, impedindo vazamento de pacotes para o IP direto do host (clearnet).

---

## 3. RELAYS TOR ONION V3 E TOPOLOGIA DE REDE

- **Arquitetura Assíncrona:** O serviço `nix_relay` atua como servidor postal temporário sem estado permanente.
- **Retenção e TTL:** Tempo de vida padrão de 7 dias (10.080 minutos) para envelopes em trânsito.
- **Expurgo por Histerese:** Algoritmo de descarte progressivo que prioriza descarte de envelopes expirados ou consumidos sem deixar rastros em disco.
- **Isolamento de Recursos:** Suporte a execução em containers unprivileged com restrições cgroups e isolamento de rede virtual.
- **Endereço Onion v3 Ativo:** `gpoun4vo5v5h3cmcfdxtudm3nlzxri3qzjd7fhbvy6oep2ap67g4qvyd.onion` (SOCKS5 Proxy em `127.0.0.1:9050`).

---

## 4. DESIGN SYSTEM LIVING AMOLED

- **Fundo Base:** `#000000` AMOLED puro em todas as superfícies principais, eliminando consumo em telas OLED.
- **Superfícies Elevadas:** `#101014` (Sidebar e Dock), `#16161C` (Cards e Diálogos) e `#1C1C24` (Hover e Estados Ativos).
- **Tipografia:** Hierarquia visual refinada (`#FFFFFF` para texto primário, `#B8B8C2` para texto secundário e `#6E6E7A` para metadados e timestamps).
- **Reatividade Global de Cores:**
  - Suporte completo às paletas: *Nix Original (Verde Criptográfico)*, *Violeta*, *Azul*, *Carmesim*, *Âmbar*, *Rosa* e *Personalizada (Hex)*.
  - As paletas afetam expressivamente: abas de navegação ativas, bordas de foco, badges não lidos, indicadores de progresso, botões de ação e destaques do Acervo.
  - Implementado via `NixThemeContext` extension (`context.accentColor`, `context.nixPalette`), garantindo atualização em tempo real sem rebuild destrutivo.

---

## 5. CARD ID E PASSAPORTE CULTURAL

- **Acionamento Universal:**
  - Abertura de Card ID por clique no avatar ou nome em conversas diretas, solicitações pendentes, participantes e cabeçalhos.
  - Respeito às políticas de privacidade configuradas: *Público*, *Apenas Contatos Verificados* ou *Oculto*.
- **Hover Isolado em Solicitações:**
  - O gatilho de hover foi restrito exclusivamente à área do avatar e do nome do remetente.
  - O cursor transitando pelos botões de ação ou pelo cartão da solicitação não dispara o preview.
- **Posicionamento Não-Obstrutivo:**
  - O cartão flutuante foi ancorado à esquerda (`left: 24`, `top: 76`), garantindo que os botões de ação (`Recusar` e `Aceitar Chave`) permaneçam 100% visíveis e clicáveis.
- **Fechamento e Lockout:**
  - Botão `X`, tecla `Escape` e clique externo fecham o preview imediatamente.
  - Implementado `_hoverLockoutRequestId` que previne a reabertura automática enquanto o mouse permanecer na área de gatilho anterior.
- **Passaporte Cultural:**
  - Vitrine interativa de destaques culturais (filmes, séries, animes, mangás, livros e prensagens em vinil com capa giratória).

---

## 6. ORGANIZAÇÃO DE NAVEGAÇÃO E ESPAÇOS

- **Dedicatória do SpacesDock:**
  - Removidos os botões duplicados de *GitHub Discovery* e *Mercado Monero P2P* da barra lateral esquerda estreita (`SpacesDock`).
  - O `SpacesDock` agora é dedicado exclusivamente a: Home/DM, ícones de Espaços, Pastas combinadas, Criar Espaço e Explorar Comunidades.
- **Centralização na HomeSidebar:**
  - Os botões *Mercado Monero P2P* e *GitHub Discovery* foram integrados como itens de navegação principal na `HomeSidebar`.
  - A barra de navegação secundária permanece ativa ao alternar entre essas ferramentas.
- **Pastas de Espaços (Space Folders):**
  - Agrupamento estilo Discord/Android suportado com persistência e colapso de nós.

---

## 7. AÇÕES DE MENSAGENS, ENCAMINHAMENTO E REAÇÕES

- **Menu de Contexto Completo:**
  - Disparado via clique com botão direito (`onSecondaryTapDown`) no Desktop ou toque longo (`onLongPressStart`) no Android.
- **Copiar Texto:**
  - Cópia íntegra de payloads UTF-8 para o clipboard do sistema com feedback visual por SnackBar.
- **Encaminhamento (`ForwardMessageDialog`):**
  - Exibe prévia da mensagem original e seletor de destino categorizado entre Canais da Comunidade e Conversas Privadas (DM).
- **Deleção Criptográfica:**
  - Opções: *Apagar para mim* (descarte local) e *Apagar para todos* (envio de payload de revogação para mensagens próprias).
- **Reações Dinâmicas Alternáveis:**
  - Barra rápida de emojis (`⚡`, `🛡️`, `🔥`, `👁️`, `✓`, `💿`, `❤️`).
  - As reações são toggleable: clicar em uma reação já selecionada decrementa e remove; clicar em uma nova adiciona e incrementa.
  - Pílulas de reações destacadas com `context.accentColor` para votos do usuário.

---

## 8. CONFIGURAÇÕES AVANÇADAS DE CANAIS & FLAG_SECURE

- **Diálogo Multi-Aba (`ChannelSettingsDialog`):**
  1. *Identidade e Acesso:* Nome, tópico, descrição, alternador de canal público/privado, link de convite Onion v3 e QR Code.
  2. *Permissões de Mensagens:* Permissões granulares de envio de texto, mídias, documentos, áudios, links externos, encaminhamentos, reações, edição e deleção.
  3. *Proteção de Conteúdo:* Bloqueio de exportação, restrição de salvamento local de arquivos e retenção efêmera automática (5m, 1h, 24h, 7 dias ou permanente).
  4. *Proteção contra Screenshots:*
     - **Android:** Integração com `FLAG_SECURE` na janela Android para impedir fisicamente capturas e visualização em alternador de aplicativos.
     - **Desktop:** Documentação explícita de caveats arquiteturais (X11 e Wayland sem permissões de kernel não oferecem garantia física absoluta; mitigado por ofuscação da janela na perda de foco).
  5. *Administração & Auditoria:* Identificação do proprietário, listas de administradores, moderadores e membros banidos, além de logs de auditoria criptográfica com carimbo de tempo.
  6. *Segurança & Anti-Spam:* Modo lento (*Slow Mode*) de 5s a 60s e limitação de arquivos (10MB, 50MB, 100MB).

---

## 9. INTEGRAÇÃO STARWIRE (4.188 REPOSITÓRIOS)

- **Dataset Real:** Ingestão de `apps/nix_client/assets/data/starwire_repos.json` contendo 4.188 projetos classificados sob licença Creative Commons Zero v1.0 Universal (`CC0-1.0`).
- **Campos de Metadados:** `name`, `owner`, `description`, `starsCount`, `starsThisWeek`, `starsWhenPicked`, `area`, `category`, `topics`, `language`, `license`, `isTrending`.
- **Pesquisa e Filtragem:** Busca instantânea virtualizada por nome, autor, descrição e tags. Filtros de tópicos e ordenação por estrelas ou data.
- **Acervo Pessoal com 1 Clique:** Botão *Salvar no Acervo* sincroniza instantaneamente com o Card ID público.

---

## 10. MERCADO MONERO P2P DESCENTRALIZADO

- **Non-Custodial:** Negociações sem custodiante central, inspiradas no modelo Trocador.app.
- **Filtros e Liquidações:** Cotações em tempo real para BRL, USD e EUR; separação de operações de Compra e Venda de XMR.
- **Isolamento Seed B:** A carteira Monero opera com mnemônico isolado (Seed B), impedindo qualquer vínculo com chaves de comunicação Nix.

---

## 11. TESTES AUTOMATIZADOS E COBERTURA

Todas as 7 suítes de testes automatizados foram executadas e validadas com **100% de aprovação (7/7 verde)**:

| Suíte de Teste | Descrição do Escopo | Status |
|---|---|---|
| Teste 1 | Inicialização sem splash, renderização do Shell e transições AMOLED | **APROVADO** |
| Teste 2 | Perfil do usuário, Card ID em metal preto, abertura de Configurações e troca de Paletas | **APROVADO** |
| Teste 3 | Home com Card ID vazio, hover preview em solicitações e abertura de conversa privada | **APROVADO** |
| Teste 4 | Navegação GitHub Discovery Starwire e Mercado Monero P2P via HomeSidebar | **APROVADO** |
| Teste 5 | Combinação de Espaços em Pastas por arrastar-e-soltar, seletor de emojis e Modelo de Confiança | **APROVADO** |
| Teste 6 | Peer Card ID universal por clique, botão X com lockout de reabertura e posicionamento seguro | **APROVADO** |
| Teste 7 | Ações de mensagem (cópias, reações alternáveis, encaminhamento, deleção) e Configurações de canal | **APROVADO** |

---

## 12. BUILDS MULTIPLATAFORMA & HOMOLOGAÇÃO DE PROTÓTIPOS

> ⚠️ **Nota Importante:** Estes binários são estritamente protótipos experimentais de desenvolvimento e validação técnica interna. Não representam nem são distribuídos como lançamentos oficiais de produção.

### Linux Desktop (x86_64)
- **Comando:** `flutter build linux --release`
- **Binário gerado:** `build/linux/x64/release/bundle/nix_client`
- **Pacote de Teste Local:** `dist/nix-desktop-linux-x64.tar.gz`
- **Tamanho:** 19 MB
- **SHA-256:** `dbc631bbcf25d24c1d5fa4dd59ddff561a50fe5f04e329cbc53b274e44561966`

### Android APK (arm64-v8a / armeabi-v7a / x86_64)
- **Comando:** `flutter build apk --release`
- **Binário gerado:** `build/app/outputs/flutter-apk/app-release.apk`
- **Pacote de Teste Local:** `dist/nix-client-v0.2.0.apk`
- **Tamanho:** 32 MB
- **SHA-256:** `a808ca6f739aaf10c84b0399def2eac8448ca7f7f515bb069f0702ed41121fdf`

---

## 13. ANÁLISE DE SEGURANÇA E LIMITAÇÕES

1. **Proteção contra Captura de Tela em Sistemas Operacionais Desktop:**
   - Sob Linux (X11/Wayland), macOS e Windows, a restrição de screenshot depende de políticas de proteção do compositor gráfico e do kernel. Nenhuma aplicação em espaço de usuário comum pode garantir 100% de bloqueio contra ferramentas externas de gravação (e.g., OBS, captura de tela do SO). O Nix mitiga essa limitação aplicando ofuscação visual quando a janela perde o foco do usuário.
2. **Latência da Rede Tor Onion v3:**
   - O roteamento através de 6 nós (3 nós do cliente + 3 nós do serviço onion) adiciona latência esperada entre 250ms e 1200ms. O cliente Nix implementa filas locais assíncronas e confirmações optimistas para manter a interface fluida.

---

## 14. MATRIZ DE CONFORMIDADE DE REQUISITOS

| Requisito | Especificação Solicitada | Implementação no Nix | Conformidade |
|---|---|---|---|
| R1 | Fundo AMOLED puro `#000000` | Cores fixadas em `#000000` em toda a base | **100%** |
| R2 | Seletor de cores global e reativo | Implementado via `NixThemeContext` em todas as telas | **100%** |
| R3 | Abertura do Card ID por clique | Clique em nomes/avatares em chats, membros e solicitações | **100%** |
| R4 | Hover restrito exclusivamente ao nome/avatar | Detector ativado só no peer, lockout no botão X | **100%** |
| R5 | Posicionamento não-obstrutivo do Card ID | Ancoragem lateral esquerda (`left: 24`), botões livres à direita | **100%** |
| R6 | Remoção de botões duplicados do Dock | Dock dedicado a espaços e pastas; ferramentas na HomeSidebar | **100%** |
| R7 | Context menu de mensagens e reações | Copiar texto, encaminhar, apagar e reações alternáveis | **100%** |
| R8 | Configurações avançadas de canal | Multi-aba com permissões, segurança, auditoria e `FLAG_SECURE` | **100%** |
| R9 | Integração Catálogo Starwire | 4.188 repositórios ingeridos em `starwire_repos.json` | **100%** |
| R10 | Relatório e Guia de Implantação Tor | `AUDIT_REPORT_V2.md` e `DEPLOYMENT_ONION_V3.md` | **100%** |
| R11 | Protótipos Desktop e Android APK | Compilados e homologados localmente com testes 100% verdes | **100%** |
