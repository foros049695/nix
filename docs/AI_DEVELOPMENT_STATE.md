# Continuidade do desenvolvimento — Projeto Nix

**Branch:** `main`  
**HEAD atual:** `d809a73`  
**Sincronizado com:** `origin/main` (GitHub: `foros049695/nix`)  
**Data da última rodada:** 22/11/2026  

---

## Tabela de Estado das Áreas

| Área | Estado | Detalhes da alteração e testes |
|---|---|---|
| Música (Metadados Online) | VERIFIED_LOCAL | Implementado `MusicOnlineMetadataService` via Tor SOCKS5 fail-closed. Conectado a `CulturalCatalogPicker` e `PagerPlaylistDialog`. Testes aprovados em `attachments_call_and_music_test.dart` e `pager_playlist_test.dart`. |
| Mercado Cripto | VERIFIED_LOCAL | Renomeação completa de "Mercado" para "Mercado Cripto". Adicionado modelo unificado `CryptoMarketItem` com métodos reativos no `NixState`. Suporte a ordens de XMR e BTC no mesmo ambiente. |
| Bitcoin e Lightning | VERIFIED_LOCAL | Pagamentos iniciados pelo próprio Nix validados em nó próprio (Bitcoin Core RPC e LND REST via Tor). Diálogo de confirmação com aviso de fundos sintéticos regtest, tratamento de falhas e histórico de liquidações. Testes aprovados em `bitcoin_payment_test.dart`. |
| Grupos e Fóruns | VERIFIED_LOCAL | Chat único e fórum com tópicos, com alternância e persistência em cofre SQLCipher (`327b9d1`). |
| Imagem em tópicos | VERIFIED_LOCAL | Imagem sanitizada com prévia e remoção no formulário de tópicos (`559d540`). |
| Banners | VERIFIED_LOCAL | Banners locais independentes do avatar, com ajuste de posição e exibição em grupo, canal e Explorar (`d39ec5d`). |
| Pastas expansíveis | VERIFIED_LOCAL | Expansão de pastas estilo Discord com estado persistido (`867e9ef`). |
| Acervo e capas | VERIFIED_LOCAL | Fichas unificadas no Media Index e Passaporte do Pager (`e31a188`). Capas de livros e mangás com desenho 3D refinado (`bd233e3`). |
| Fundo da interface | VERIFIED_LOCAL | Seleção local de wallpaper, opacidade, escurecimento, desfoque e animação opcional respeitando redução de movimento (`3e56f23`). |
| Explorar | VERIFIED_LOCAL | Removidos contadores presumidos; contagem reflete somente dados conhecidos e verificáveis (`cb57862`). |
| Chamadas e Enquetes | PARTIAL | Implementação de sincronização, convite Onion e correções de áudio (`0d9b689`, `4a00302`, `d61b9c0`, `36768cf`). Pendente apenas homologação em 2 dispositivos físicos reais com Tor fim a fim. |

---

## Commits desta rodada (na `main` remota e local)

1. `ef3ec1b` — `feat(music): add consented Tor‑only online metadata search and UI integration`
2. `7138f76` — `refactor: rename Mercado to Mercado Cripto in UI and tests`
3. `67bdee7` — `feat(crypto-market): add CryptoMarketItem model and state integration`
4. `4bf4ad2` — `fix: restore monero_order import and remove equatable dependency from CryptoMarketItem`
5. `d809a73` — `fix(ci): use SecureSocket for music metadata and disambiguate Mercado Cripto tab in tests`

---

## Validação Executada e Aprovada

- `flutter analyze --no-fatal-infos` em `apps/nix_client`: **0 erros/warnings fatais** (apenas informativos estilísticos mantidos do código legado).
- `flutter test` em `apps/nix_client`:
  - `test/attachments_call_and_music_test.dart` (passou)
  - `test/pager_playlist_test.dart` (passou)
  - `test/mobile_layout_regression_test.dart` (passou)
  - `test/widget_test.dart` (passou)
  - `test/bitcoin_payment_test.dart` (passou)
  - `test/forum_persistence_test.dart` (passou)
  - `test/voice_note_test.dart` (passou)
  - `test/trade_simulation_test.dart` (passou)
- `dart analyze` & `dart test` em `modules/core_crypto`: **Todos passaram (13/13)**.
- `dart analyze` & `dart test` em `modules/transport`: **Todos passaram (25/25)**.
- `./scripts/verify_privacy_matrix.sh`: **Aprovado**.
- `./scripts/verify_automation_policy.sh`: **Aprovado**.

---

## Pendências Externas (Fora do Ambiente Local)

1. **Homologação em Hardware Físico:**
   - Teste de chamada de voz P2P e votação em enquetes entre 2 smartphones Android físicos através de circuito Tor real.
2. **Geração de Instaladores:**
   - Compilação dos APKs Android e binários Desktop (fora do repositório público, conforme política de distribuição privada do projeto).
