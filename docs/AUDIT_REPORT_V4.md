# PROJETO NIX — RELATÓRIO DE AUDITORIA TÉCNICA E HOMOLOGAÇÃO V4

**Data de Referência:** 18 de Novembro de 2026  
**Versão do Protótipo:** `0.4.0-dev` (Pacote Flutter `0.2.0+2`)  
**Branch de Desenvolvimento:** `feature/v4-telegram-layout-yellow` (integrada à `main`)  
**Classificação:** Auditoria Técnica de Protótipo Experimental (*Pre-Alpha* — Não é Lançamento Oficial)

---

## 1. SUMÁRIO EXECUTIVO E POSTURA DE TRANSPARÊNCIA

Este documento registra as modificações arquiteturais, implementações funcionais, resultados exatos de testes automatizados, hashes SHA-256 dos artefatos de prototipação e limitações técnicas verificadas na entrega **Projeto Nix V4**.

> ⚠️ **Aviso de Estágio:** Os binários desktop e APK descritos neste relatório são **protótipos de desenvolvimento e verificação técnica local**. O APK Android utiliza a chave de assinatura `debug` padrão configurada em `apps/nix_client/android/app/build.gradle`, não devendo ser distribuído como lançamento oficial de produção.

---

## 2. MUDANÇAS ARQUITETURAIS E DESIGN SYSTEM V4

### 2.1 Novo Emblema Vetorizado Transparente
- Processamento automatizado via `scripts/brand/process_logo.py` (remoção de fundo com `alpha=0` em todos os cantos, preservação da gravura original por vetorização `potrace`, reconstrução sem pixelização).
- Entrega em PNGs transparentes e variantes (`ink`, `light`, `medallion`) para desktop, navegação, splash e `mipmap-*` Android.

### 2.2 Temas Oficiais Dark Yellow, Light Yellow e AMOLED
- **Nix Dark Yellow** *(padrão inicial)*: fundo `#08090B`, superfície `#17191E`, elevada `#292C33`, destaque `#FFC928`, texto `#FFFFFF` / `#B7BAC4`.
- **Nix Light Yellow**: fundo `#FFFFFF`, superfície `#F6F7F9`, elevada `#E9EBEF`, destaque `#FFC928`, texto `#17191E` / `#60646C`.
- **AMOLED Puro** *(opcional)*: `#000000` e **Seguir Tema do Sistema** via `ThemeData`, `ColorScheme`, `ThemeExtension<NixThemeExtension>` e sincronização reativa em `NixColors`.
- Seletor completo em **Configurações → Aparência → Temas** com pré-visualização e persistência local (`~/.local/share/nix/client_prefs_v4.json`, isolada fora de execuções `FLUTTER_TEST`).

### 2.3 Mensageiro em 3 Áreas, Janela Desktop e Card ID
- **Estrutura Telegram-like:** Rail compacta à esquerda (`SpacesDock`) com pastas personalizáveis (ícone, cor, edição, reordenação, arrastar-e-soltar e exclusão preservando conversas), coluna intermediária com pesquisa/filtros/**Mensagens Salvas**, e palco principal.
- **Janela Desktop:** Redimensionamento nas 8 bordas/cantos (`minWidth: 720`, `minHeight: 500`), início não maximizado (`1152x720`) e remoção de promessas falsas sobre proteção anti-fingerprinting baseada apenas no tamanho da janela.
- **Card ID & Hover sem Flickering:** Remoção de QR duplicado e status `"Assistindo"`, fallback determinístico `NX-7E3A`, editor/sanitizador EXIF local (`LocalImageHelper`), posicionamento do preview flutuante à direita da identidade sem cobrir `Recusar` / `Aceitar Chave`, trava anti-flickering e enforcement no estado para `Privacidade → Visibilidade do Card ID`.

---

## 3. NÚCLEO CRIPTOGRÁFICO, TRANSPORTE E RELAY GO

| Módulo | Caminho | Capacidades Implementadas e Testadas | Status dos Testes |
|---|---|---|---|
| **Core Crypto** | `modules/core_crypto/` | `NixIdentity` (`Ed25519` + `X25519`), `SealedEnvelope` (`XChaCha20-Poly1305`), `PassphraseKdf` (`Argon2id`), `X3dh`, `DoubleRatchet` (incluindo mensagens fora de ordem) e `SignedRecord` + `ReplayGuard` | **5/5 Verde** (`dart test`) · `dart analyze` 0 problemas |
| **Transport** | `modules/transport/` | `TransportPolicy` *fail-closed* (rejeita clearnet/IPs fora `.onion` v3 sem fallback), `Socks5Connector` RFC 1928 com `ATYP 0x03` sem vazamento de DNS, `TorControlClient`, `TorDiagnostics` e `RelayClient` | **4/4 Verde** (`dart test`) · `dart analyze` 0 problemas |
| **Nix Relay** | `services/nix_relay/` | API HTTP (`/healthz`, `/metrics`, `/v1/mailboxes/{id}/envelopes`, `/ack`), armazenamento cego em disco com TTL 7 dias e `AutoPruner` em 4 bandas com histerese (`75/85/92/<70%`) | **2/2 Pacotes Go Verde** (`go test ./...`) + smoke test binário HTTP OK |

---

## 4. VALIDAÇÃO DA INTERFACE FLUTTER (`apps/nix_client`)

- Análise estática: `/home/gus/.local/bin/flutter analyze --no-fatal-infos` — **0 erros, 0 avisos** (69 infos pré-existentes).
- Testes de widgets e integração de estado: `/home/gus/.local/bin/flutter test -r expanded` — **7/7 suítes aprovadas**:
  1. Splash -> Shell V4 **Dark Yellow** padrão (`#08090B`, `#17191E`, `#292C33`, `#FFC928`).
  2. Troca dinâmica de temas (**Light Yellow**, **AMOLED**, **Sistema**, paletas de destaque) e navegação pelas categorias de Configurações.
  3. Card ID limpo (sem QR duplicado e sem `"Assistindo"`), fallback determinístico `NX-XXXX` e remoção de segmentos EXIF em JPEG.
  4. **Mensagens Salvas**, máquina de estados anti-flickering no hover em Solicitações, não-sobreposição do cartão aos botões e enforcement no estado para `Visibilidade do Card ID`.
  5. Pastas com criação/filtragem e exclusão não destrutiva das conversas.
  6. Ações completas de mensagens (editar com badge `"editada"`, fixar/desafixar, reagir, encaminhar para Mensagens Salvas), Emoji Picker e `ConversationInfoPanel` clicável no cabeçalho.
  7. Gráficos com dados reais do catálogo Starwire (`4.188` repositórios), salvamento privado no Acervo, verificação de assinatura/expiração no Mercado Monero P2P e abertura segura de `ShareAppOfflineDialog`.

---

## 5. ARTEFATOS DE PROTÓTIPO COMPILADOS & CHECKSUMS SHA-256

> Compilação apenas para homologação interna (não publicados como releases oficiais no GitHub).

| Alvo | Comando | Artefato | Tamanho | SHA-256 |
|---|---|---|---|---|
| **Linux Desktop** | `flutter build linux --release` | `apps/nix_client/build/linux/x64/release/bundle/nix_client` | 24 KB (binário launcher) | `175da0d569a314481824c2e5e77cde7e6c1505f56e2a99f9bdc25859c940e95d` |
| **Linux Bundle** | `tar -czf dist/nix-desktop-linux-x64.tar.gz ...` | `dist/nix-desktop-linux-x64.tar.gz` | 13 MB | `75f6751f6c82e8223229b8219f50d5834f93986088c706acd87f1402c56e5adf` |
| **Android APK** | `flutter build apk --release` | `dist/nix-client-v0.4.0.apk` (e `app-release.apk`) | 26 MB (27.2 MB Gradle, assinado `debug`) | `c386d1ecbd2026849f8416ec75612af2459a5d99839faad040b49aac40fdb720` |
| **Nix Relay (Go)** | `go build -ldflags="-s -w" -o bin/nix_relay ./cmd/relay` | `services/nix_relay/bin/nix_relay` | 6,0 MB | `80e305f4a970ca71227dd73b78fee5ba4acf9e4186c1af0f6f969ceda78b1a85` |

---

## 6. LIMITAÇÕES TÉCNICAS CONHECIDAS (HONESTIDADE CRIPTOGRÁFICA & DE PLATAFORMA)

1. **Bloqueio de Capturas de Tela em Desktop:** Enquanto no Android `FLAG_SECURE` atua na janela do sistema, em Linux (X11/Wayland), Windows e macOS aplicações em espaço de usuário não conseguem impedir capturas externas ou registro físico por câmera; tratamos opções de privacidade como mitigações auxiliares, nunca garantia absoluta.
2. **Acoplamento Progressivo do Cliente Flutter aos Módulos Backend:** As implementações reais de criptografia (`modules/core_crypto`), transporte Tor *fail-closed* (`modules/transport`) e relay (`services/nix_relay`) foram implementadas e testadas isoladamente; o estado da UI em `apps/nix_client` ainda utiliza dados simulados e sonda TCP real de diagnóstico do daemon Tor local (`127.0.0.1:9050`), exigindo a fase seguinte de integração ponta a ponta entre UI Flutter -> `core_crypto` -> `transport` -> `nix_relay` ativo.
3. **Assinatura Android de Produção & Plataformas Sem SDK Local:** O APK gerado utiliza `signingConfigs.debug`. Compilações nativas de macOS e iOS não puderam ser executadas neste ambiente Linux por ausência de toolchain Apple/Xcode.
4. **Limites do Anonimato:** Uso de Tor Onion v3 e minimização de metadados mitigam correlação de rede trivial, mas não garantem anonimato absoluto contra adversários globais passivos ou comprometimento do dispositivo final.
