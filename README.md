# 🏴‍☠️ PROJETO NIX

> **Comunicação inviolável, publicação de conhecimento imutável e transações financeiras soberanas com privacidade verificável por padrão.**

[![Licença: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Status: Pre-Alpha em Refatoração P0](https://img.shields.io/badge/Status-Pre--Alpha%20%7C%20Refatora%C3%A7%C3%A3o%20P0-FFC928.svg)](ROADMAP.md)
[![Design: Nix Yellow V4.1](https://img.shields.io/badge/Design-Nix%20Yellow%20V4.1-FFC928.svg)](docs/AUDIT_REPORT_V4.md)
[![Transporte: Tor Onion v3 Fail-Closed](https://img.shields.io/badge/Network-Tor%20Fail--Closed-purple.svg)](docs/DEPLOYMENT_ONION_V3.md)
[![Criptografia: XMR Only](https://img.shields.io/badge/Finan%C3%A7as-Monero%20(XMR)-FF6600.svg)](docs/WALLET.md)

---

## 🧭 Sumário Executivo & Transparência Técnica

O **Nix** é um ecossistema modular, auto-hospedável e de código aberto projetado para assegurar comunicação confidencial, publicação descentralizada de conhecimento, acervo local de mídia e transações financeiras não custodiais exclusivamente em Monero (XMR).

> ⚠️ **Aviso de Engenharia:** O Nix encontra-se atualmente em **fase pre-alpha de desenvolvimento ativo e homologação arquitetural**. A auditoria técnica formal realizada em Novembro de 2026 identificou que, embora o protótipo apresente uma interface gráfica rica e módulos isolados, a **mensageria fim a fim e a camada de transporte estão em fase de refatoração crítica (Marcos P0)**. Nenhum binário atual deve ser considerado pronto para uso em ambientes de risco elevado antes da conclusão dos gates criptográficos e de rede.

---

## Identidade visual e Pager

O cliente usa molduras arredondadas com sombras deslocadas, títulos em pixel
art e texto de leitura contínua em uma fonte sem serifa. O desktop oferece um
painel central e colunas redimensionáveis para espaços, conversas e detalhes.
No mobile, o cabeçalho, a barra inferior e o menu lateral usam painéis
translúcidos. As áreas continuam acessíveis pela navegação flutuante.
As configurações abrem cada seção em tela cheia. O modo de movimento reduzido
desativa os efeitos de perspectiva e a animação da assistente no Pager.

Em **Aparência**, escolha **Preto / Roxo**, **Branco / Amarelo** ou **Verde /
Roxo**. Também é possível ajustar a superfície e a cor de destaque separadamente.

O Pager interativo está no acesso ao app e no perfil. A primeira página reúne
foto, nome, QR e atalhos para grupos, canais e amigos. Em **Menu do Pager →
Cores do Pager**, escolha a cor da carcaça e a do visor separadamente. Em
**Personalizar contemplação**, escolha uma imagem local ou GIF, ative o fundo em
todas as telas e ajuste o desfoque e o escurecimento. Arraste a foto no visor
para mudar sua posição ou desative-a para contemplar somente o fundo. Em
**Editar avatar**, escolha entre moldura circular e quadrada arredondada.
A música exibida pode ser inserida no editor de perfil. No Android, **Menu
do Pager → Playlist do Pager** permite adicionar e reproduzir faixas locais
autorizadas. A mesma playlist aceita WAV no Windows e no Linux. O passaporte
cultural e o acervo ficam abaixo do Pager. **Buscar no catálogo** preenche a ficha da
obra a partir do banco local. A estante mostra discos, livros com lombada e
páginas, e pôsteres. As capas vêm do pacote quando há uma imagem embutida.
As referências de capa do catálogo inicial geram ilustrações locais.

A busca musical usa metadados CC0 do MusicBrainz. Em **Acervo → Buscar no
catálogo**, pesquise por título, artista ou álbum e adicione o resultado ao
passaporte. O **Nix Media Index** também oferece filtros para álbuns e faixas.
O recorte inicial é distribuído com o app. A busca, as ilustrações e a ficha
funcionam offline, sem consulta a API ou envio de histórico. A base não
distribui gravações ou capas comerciais.
[Dump principal do MusicBrainz](https://musicbrainz.org/doc/MusicBrainz_Database/Download)

Para ampliar o catálogo, restaure o dump principal do MusicBrainz no PostgreSQL
local e use a exportação abaixo. O importador pode ser incluído no fluxo de
publicação de um pacote assinado do Nix.

```sh
psql -q -d musicbrainz -f tools/metadata_builder/importers/musicbrainz_export.sql > /tmp/nix-musicbrainz.tsv
python3 tools/metadata_builder/build_catalog.py --seed \
  --musicbrainz-tsv /tmp/nix-musicbrainz.tsv \
  --out-db /tmp/nix-catalog.db --out-manifest /tmp/nix-catalog.json --report ""
```

O exportador seleciona álbuns e gravações do dump central. Para publicar com a
chave já provisionada, acrescente `--production`, `--version` com uma versão
superior à publicada e o parâmetro de assinatura usado pelo projeto.


---


## 🧱 Arquitetura Geral do Sistema (C4 Containers)

O Nix opera no modelo **local-first**: todo o código, chaves privadas e mensagens residem no dispositivo do usuário em banco de dados cifrado. A VPS do relay atua unicamente como um buffer opaco e cego de armazenamento temporário.

```mermaid
flowchart TB
  subgraph Dispositivo["Limite do Dispositivo Local"]
    APP["Cliente Nix (Flutter Multiplataforma)"]
    VAULT["Cofre de Chaves do SO (Keystore / Keychain / Secret Service)"]
    DB[("Banco Local Cifrado (SQLCipher + FTS5)")]
    TOR_LOCAL["Daemon Tor Local (Proxy SOCKS5 127.0.0.1:9050)"]

    APP --> VAULT
    APP --> DB
    APP --> TOR_LOCAL
  end

  subgraph RedeTor["Rede de Transporte Tor Onion v3 (Fail-Closed)"]
    CIRCUIT["Circuitos Criptografados Onion (.onion)"]
  end

  subgraph ServidorRelay["VPS do Relay Voluntário (Debian 13)"]
    TOR_SRV["Tor Onion Service (Hidden Service Port 80/443)"]
    RELAY_APP["API nix_relay (Go HTTP + Capabilities Auth)"]
    PG[("PostgreSQL 17 (Envelopes Efêmeros + AutoPruner 7d)")]
    ADMIN["Listener Admin / Métricas Local (127.0.0.1:9091)"]

    TOR_SRV --> RELAY_APP
    RELAY_APP --> PG
    ADMIN -.-> RELAY_APP
  end

  subgraph ServicosExternos["Ecossistema Descentralizado"]
    PEER["Outro Cliente Nix (Conexão Direta Onion-to-Onion)"]
    ARCHIVE["Réplicas Voluntárias do Archive (CAS Imutável)"]
    XMR["Daemon Monero P2P (Processo Isolado - Seed B)"]
  end

  TOR_LOCAL <--> CIRCUIT
  CIRCUIT <--> TOR_SRV
  CIRCUIT <--> PEER
  APP -.-> ARCHIVE
  APP -.-> XMR
```

---

## 🔒 Política de Transporte Tor & Isolamento Fail-Closed

O princípio fundamental de transporte do Nix é o **Fail-Closed**: nenhum dado privado trafega pela rede se o circuito Tor estiver indisponível. Conexões diretas via IP clearnet são terminantemente bloqueadas no perfil de segurança padrão.

```mermaid
flowchart TD
  REQ["Disparo de Ação de Rede (Envio, Sync ou Download)"] --> POL{"Perfil de Rede Ativo"}
  
  POL -- "Perfil Privado (Padrão)" --> PROXY["Conectar via SOCKS5 (127.0.0.1:9050)"]
  POL -- "Perfil LAN / Descoberta Local" --> WARN["Exibir Alerta de Exposição Local (RF / Wi-Fi)"]
  
  PROXY --> CHECK{"Daemon Tor Operacional?"}
  CHECK -- "Sim" --> ONION["Encapsular Requisição em Onion v3 (.onion)"]
  CHECK -- "Não" --> BLOCK["BLOQUEIO FAIL-CLOSED (Conexão Abortada)"]
  
  BLOCK --> NOTIF["Notificar Usuário: Sem Conexão Tor"]
  ONION --> RELAY_SEND["Transmitir para Relay / Peer"]
```

---

## 📬 Ciclo de Vida da Mensageria E2EE & Buffer Efêmero

As mensagens são protegidas por criptografia de ponta a ponta (Double Ratchet + X3DH + XChaCha20-Poly1305) com commits transacionais no dispositivo e expurgo automático no relay.

```mermaid
sequenceDiagram
  autonumber
  actor Alice as Alice (Cliente A)
  participant DB_A as SQLCipher Local (A)
  participant Relay as Relay Nix (PostgreSQL)
  participant DB_B as SQLCipher Local (B)
  actor Bob as Bob (Cliente B)

  Note over Alice,DB_A: 1. Gravação Atômica Pré-Envio
  Alice->>DB_A: Iniciar Transação (Outbox + Estado Candidato Ratchet)
  DB_A-->>Alice: Commit Confirmado
  
  Note over Alice,Relay: 2. Transmissão Cifrada via Tor
  Alice->>Relay: POST /v1/mailboxes/{id}/envelopes (Payload Cifrado + Quota Token)
  Relay->>Relay: Validar Cota Atômica e Gravar com TTL 7 Dias
  Relay-->>Alice: HTTP 202 Accepted (Envelope Armazenado)
  
  Note over Bob,Relay: 3. Recepção & Validação
  Bob->>Relay: GET /v1/mailboxes/{id}/envelopes (Autenticado por Capability)
  Relay-->>Bob: Retornar Envelopes Cifrados
  
  Note over Bob,DB_B: 4. Autenticação AEAD & Commit Pré-ACK
  Bob->>Bob: Validar AEAD em Cópia Candidata de Estado
  alt Mensagem Autêntica
    Bob->>DB_B: Gravar Mensagem + Avançar Ratchet + Salvar Dedup
    DB_B-->>Bob: Commit Confirmado
    Bob->>Relay: POST /v1/mailboxes/{id}/ack (Confirmar Recebimento)
    Relay->>Relay: Remover Envelopes Confirmados (Commit-before-ACK)
  else Mensagem Adulterada / Forjada
    Bob->>Bob: Rejeitar Mensagem e Descartar Estado Candidato (Sem Corrupção)
  end
```

---

## 🔑 Modelo de Identidade Compartimentada (Seed A vs Seed B)

Para mitigar correlação financeira e vazamento cruzado de privacidade, o Nix impõe a separação criptográfica absoluta entre a identidade de comunicação e a carteira financeira.

```mermaid
flowchart LR
  subgraph SeedA["Identidade de Comunicação (Seed A)"]
    direction TB
    ID_KEY["Chave Mestra Ed25519 (Identidade & Assinaturas de Rede)"]
    DH_KEY["Chaves Efêmeras X25519 (Double Ratchet & Prekeys X3DH)"]
    ARCH_KEY["Persona Editorial Archive (Assinatura de Publicações)"]
    
    ID_KEY --- DH_KEY
    ID_KEY --- ARCH_KEY
  end

  subgraph Barreira["Fronteira Estrita de Isolamento"]
    WALL["Isolamento de Processo & Memória Zeroizada"]
  end

  subgraph SeedB["Soberania Financeira (Seed B)"]
    direction TB
    XMR_VIEW["Chave de Visualização Privada Monero (Audit / Saldo)"]
    XMR_SPEND["Chave de Gasto Privada Monero (Transações P2P)"]
    
    XMR_VIEW --- XMR_SPEND
  end

  SeedA -. "Zero Compartilhamento de Chaves" .- Barreira
  Barreira -. "Zero Custódia pelo Mensageiro" .- SeedB
```

---

## 📊 Estado Real dos Módulos (Auditoria Técnica Local — Nov/2026)

Após a integração dos PRs `#1`–`#18`, fechamento das Issues `#11` e `#12` e conclusão das correções P0/P1 de laboratório local:

| Componente | Estado Verificado | Evidência Principal |
|---|---|---|
| **Core Criptográfico (`modules/core_crypto`)** | `VERIFIED` | Ed25519/X25519, AEAD XChaCha20-Poly1305, Argon2id, X3DH, Double Ratchet atômico, `SignedRecord`, `ReplayGuard`, `PqxdhCombiner`, `SignedReleaseManifest` (`dart test` 10/10). |
| **Transporte Tor / SOCKS5 / TLS (`modules/transport`)** | `FIXED & VERIFIED` | SOCKS5 `ATYP 0x03`, TLS real via `RawSecureSocket` (Issue `#11`), `EmbeddedTorManager` com verificação ControlPort, Mesh `NIXB` e Radio `<=240B` (`dart test` 22/22). |
| **Relay Cego Go (`services/nix_relay`)** | `VERIFIED` | `BlindMailboxStore` + `PostgresMailboxStore` (PG 17), capabilities SHA-256 com escopos/revogação, `AutoPruner`, admin isolado em loopback (`go test -race ./...`). |
| **Mensageria UI + Transacionalidade (`apps/nix_client`)** | `FIXED & VERIFIED` | `NixState.sendDirectMessage` → `SovereignMessenger` unificado, transação SQLite atômica, injeção de falhas nos 6 estágios, troca real entre 2 instâncias via relay+SOCKS5 e recuperação pós-reinício (`flutter test` 89/89). |
| **SQLCipher, KeyVault, Onboarding, Monero P2P, Archive, Media, Starwire, APK Offline** | `FIXED & VERIFIED` (local) | `requireEncryption` bloqueando SQLite comum, backup/restore cifrado, verificação fail-closed ativa no onboarding, anúncios Monero assinados Ed25519 isolados da Seed A, tokenizador HTML anti-XSS, conectores opt-in, proibição de bypass clearnet e APK autenticado Ed25519. |
| **Infraestrutura Externa & Hardware Físico** | `UNVERIFIED` / `PARTIAL` | VPS Debian 13 (soak 60 min Onion v3), APK Android físico (NDK/TEE), Bluetooth BLE / LoRa RF físicos, `monero-wallet-rpc` stagenet/mainnet e replicação Archive externa (ver [`docs/IMPLEMENTATION_NEXT_STEPS.md`](docs/IMPLEMENTATION_NEXT_STEPS.md)). |

> ⚠️ **Aviso de Engenharia:** Embora todos os núcleos P0/P1 estejam validados em laboratório local com suítes reproduzíveis, o Nix permanece em **fase pre-alpha** até a conclusão da validação em VPS externa, dispositivos móveis físicos e auditoria criptográfica independente.

---

## 📚 Documentação Técnica & Relatórios da Auditoria

* [`docs/REPOSITORY_DIAGNOSTIC.md`](docs/REPOSITORY_DIAGNOSTIC.md) — Diagnóstico real por módulo e divergências corrigidas.
* [`docs/IMPLEMENTATION_GAPS.md`](docs/IMPLEMENTATION_GAPS.md) — Lacunas P0/P1/P2 auditadas com arquivo, símbolo e teste.
* [`docs/PR_ISSUE_VERIFICATION.md`](docs/PR_ISSUE_VERIFICATION.md) — Verificação individual das Issues `#11`–`#12` e PRs `#1`–`#18`.
* [`docs/LOCAL_INTEGRATION_TEST_REPORT.md`](docs/LOCAL_INTEGRATION_TEST_REPORT.md) — Relatório completo das execuções locais.
* [`docs/IMPLEMENTATION_NEXT_STEPS.md`](docs/IMPLEMENTATION_NEXT_STEPS.md) — Plano para etapas de VPS, Android físico, BLE/LoRa e RPC externo.
* [`docs/PRIVACY.md`](docs/PRIVACY.md) · [`docs/PRIVACY_MATRIX.md`](docs/PRIVACY_MATRIX.md) · [`SECURITY.md`](SECURITY.md) · [`ROADMAP.md`](ROADMAP.md) · [`docs/adr/`](docs/adr/) · [`database/`](database/)

---

## 🛠️ Compilação e Execução de Protótipos Locais

### Pré-requisitos
* **Flutter SDK:** 3.27.4 ou superior, com o Dart incluído no SDK
* **Go:** 1.22 ou 1.23 (para desenvolvimento do relay)
* **SQLite no Linux:** instale `libsqlite3-dev` (Debian/Ubuntu) para os testes do cliente.
* **Docker & Docker Compose:** para execução do banco PostgreSQL em testes locais

### 1. Execução do Cliente Desktop (Linux)
```bash
cd apps/nix_client
flutter pub get
flutter run -d linux
```

### 2. Compilação do APK Android Release

Instale o Android SDK e o JDK 17, inclua o `apksigner` do Android SDK
Build Tools no `PATH` e confirme o ambiente com `flutter doctor -v`.
Configure a keystore de distribuição em
`apps/nix_client/android/key.properties` com as propriedades `storeFile`,
`storePassword`, `keyAlias` e `keyPassword`, ou use as variáveis
`NIX_KEYSTORE_PATH`, `NIX_KEYSTORE_PASSWORD`, `NIX_KEY_ALIAS` e `NIX_KEY_PASSWORD`.

```bash
cd apps/nix_client
flutter pub get
flutter build apk --release
sha256sum build/app/outputs/flutter-apk/app-release.apk
apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
```

O APK homologado na Etapa 7 tem 54.719.573 bytes e um assinante no esquema
APK Signature Scheme v2. O relatório registra Flutter 3.27.4, Dart 3.6.2,
Android SDK 35.0.0 e OpenJDK 17.0.21.1. O SHA-256 abaixo identifica o
artefato histórico. [Relatório de validação Android](docs/ANDROID_VALIDATION_REPORT.md)

```text
d99cd9c4b1d4ba748fd76831287696d3e83095b235c656c9942588a5a57a2756
```

### Builds do piloto

O workflow manual [Nix pilot builds](.github/workflows/pilot-builds.yml)
empacota o desktop **Linux x86-64** e APKs Android de teste separados por
arquitetura. Use `arm64-v8a` em Android 64 bits e `armeabi-v7a` em ARM 32 bits.
O APK **Nix Piloto** é compilado em modo release e assinado com a chave de
depuração do runner. Cada execução do GitHub Actions recebe um identificador
de pacote próprio, então pode ser instalada ao lado dos pilotos anteriores
com dados separados. No Linux, extraia o tarball e execute `./bundle/nix_client`.

Para distribuição, passe as chaves públicas oficiais pelo Dart com
`--dart-define=NIX_RELEASE_PUBLISHER_KEY_HEX=<chave-publica>` e
`--dart-define=NIX_CATALOG_PUBLISHER_KEY_HEX=<chave-publica>`.
Para atualizar o catálogo remoto, configure também
`--dart-define=NIX_CATALOG_MANIFEST_URL=http://<publicador>.onion/manifest.json`.
O catálogo inicial é fornecido no APK. A partir da
raiz do repositório, após `flutter pub get` no cliente:

```bash
dart --packages=apps/nix_client/.dart_tool/package_config.json \
  scripts/sign_release.dart apps/nix_client/build/app/outputs/flutter-apk/app-release.apk \
  <versão> <arquivo-privado-com-seed-ed25519-hex>
```

O cliente usa o manifesto `app-release.apk.sig.json` junto ao APK. Mantenha
a seed Ed25519 e a keystore de distribuição fora do repositório.

Para ensaiar BLE sem VPS, use dois Android em modo avião com Bluetooth
reativado. Em ambos, habilite o modo off-grid e a malha BLE, troque os
Card IDs assinados e envie mensagens de texto entre os contatos.
A interface oferece retentativa e preserva a confirmação como pendente.

O relay exige provisionamento explícito de `read_ack` pelo administrador
local. Antes de atualizar instalações antigas, provisione credenciais
aleatórias e configure-as no cliente. O relay rejeita o formato legado dos
tokens de leitura derivados do identificador público.

### Escopo da versão de teste

- **Mensagens sem VPS:** texto BLE entre contatos com Card ID importado.
  Recibo autenticado, Wi-Fi direto e Tor direto são entregas seguintes.
- **Mercado:** use **Criar sala** e **Usar convite** para uma negociação com
  pseudônimos efêmeros. O teste entre dois clientes usou um ambiente Tor
  controlado. Use **Simular negociação** para ensaiar pagamento e disputa com
  dados fictícios no próprio aparelho. [Salas privadas](docs/WALLET.md#4-salas-privadas-de-negociação)
- **Mídia:** o catálogo pode abrir áudio ou vídeo escolhido no player do
  sistema em Android e Linux. O Nix não opera servidor de streaming.
- **Relay opcional:** o benchmark pode usar um Onion v3 de laboratório pelo
  SOCKS5 local. Em `services/nix_relay`, rode
  `go run ./cmd/bench -onion http://<hostname>.onion -clients 50 -duration 60m -credentials /caminho/privado/caixas.json`.
  Forneça um array JSON privado, com modo `0600`, contendo `id`, `read_token`
  e, quando a escrita exigir autorização, `write_token` de cada caixa de
  teste provisionada. Observe as métricas do servidor no host da VPS.

### 3. Testes e verificações

A partir da raiz do repositório:

```bash
(cd modules/core_crypto && dart pub get && dart analyze && dart test)
(cd modules/transport && dart pub get && dart analyze && dart test)
(cd services/nix_relay && go vet ./... && go test -race ./...)
./scripts/verify_privacy_matrix.sh
./scripts/verify_automation_policy.sh
(cd apps/nix_client && flutter pub get && flutter analyze --no-fatal-infos && HOME="$(mktemp -d)" flutter test)
```

Os testes de transporte devem rodar em namespace de rede isolado, sem um
serviço escutando em `127.0.0.1:9050`. Consulte as condições para rodar
os testes do catálogo completo no [registro de implementação](docs/IMPLEMENTATION_PROGRESS.md).

---

## 📚 Documentação Técnica de Referência

* [`docs/AUDIT_REPORT_V4.md`](docs/AUDIT_REPORT_V4.md) — Relatório detalhado da Auditoria Técnica V4.
* [`docs/PRIVACY.md`](docs/PRIVACY.md) — Declaração pública de privacidade e limites operacionais.
* [`docs/PRIVACY_MATRIX.md`](docs/PRIVACY_MATRIX.md) — Matriz dos 21 critérios de privacidade (*The Hated One*).
* [`SECURITY.md`](SECURITY.md) — Política de divulgação responsável de vulnerabilidades e modelo de ameaças.
* [`ROADMAP.md`](ROADMAP.md) — Cronograma técnico detalhado de dependências e marcos de engenharia.
* [`docs/adr/`](docs/adr/) — Registros formais de decisões de arquitetura (ADRs).
* [`database/`](database/) — Schemas SQL, migrações e scripts de backup do banco local e do relay.

---

## ⚖️ Licença

O Projeto Nix é distribuído sob os termos da licença **GNU General Public License v3.0 (GPL-3.0)**. Consulte o arquivo [`LICENSE`](LICENSE) para obter o texto completo da licença.

## Piloto desktop e mensageria

O cliente oferece convite assinado por texto ou QR, leitura por câmera no Android e configuração de relay Onion pelo cofre. O relógio do compositor permite agendar texto em conversas diretas cifradas. O piloto distribui APKs e bundles nativos. Consulte os passos de [mensageria](docs/MESSAGING_AND_MEDIA_INTEGRATION.md), [Windows](docs/WINDOWS_DESKTOP_IMPLEMENTATION.md) e o [aceite incremental](docs/FINAL_ACCEPTANCE_REPORT.md).
