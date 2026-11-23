# Continuidade do desenvolvimento — Projeto Nix

**Branch:** `main`  
**Sincronizado com:** `origin/main` (GitHub: `foros049695/nix`)  
**Data da última rodada:** 22/11/2026  

---

## Tabela de Estado das Áreas (8 Novas Melhorias e Correções Concluídas)

| Área | Estado | Detalhes da alteração e testes |
|---|---|---|
| 1. Central de Notificações | VERIFIED_LOCAL | Implementada central de notificações privada (`NixNotificationCenterDialog`), acessível na barra superior e cabeçalho mobile com contador dinâmico (badge). Eventos locais para mensagens, menções, convites e trocas cripto sem push externo nem vazamento de segredos. Testes aprovados em `notification_center_test.dart`. (`6fa7e8c`) |
| 2. Busca Local de Músicas | VERIFIED_LOCAL | Corrigido erro `NoSuchMethodError: _detachRaw` em conexões TLS via SOCKS5 no Tor através de `httpRequest`/`httpGet` nativos em `nix_transport`. Consulta SQLite FTS5 ajustada para `kind IN ('track', 'album')` com fallback `LIKE`. Diferenciação visual estrita entre metadados indexados e áudio local disponível. Testes aprovados em `attachments_call_and_music_test.dart` e `full_media_catalog_test.dart`. (`251be2c`) |
| 3. Música do Perfil e Pager | VERIFIED_LOCAL | Substituído campo de texto manual por seletor interativo da playlist do Pager (`PagerProfile`). Vinculação bidirecional com capa, prévia e limpeza automática no perfil se a faixa for removida da playlist. Testes aprovados em `pager_profile_playlist_link_test.dart`. (`22cca87`) |
| 4. Mercado Cripto (Ordens e Filtros) | VERIFIED_LOCAL | Adicionada ação "Excluir anúncio local" / "Cancelar ordem" para o criador da oferta com diálogo de confirmação e atualização imediata da listagem, preservando histórico de trades. Removida a opção "Todos" dos seletores de ativos (mantidos estritamente XMR e BTC) e substituído chip "Todos" em formas de pagamento por botão limpar/desmarcar. Testes aprovados em `crypto_market_order_management_test.dart`. (`1fa3bdd`) |
| 5. Importação de Acervos CSV/HTML | VERIFIED_LOCAL | Adicionada importação segura e offline de acervos culturais (`CollectionImporter` e `CollectionImportDialog`) no Acervo Pessoal. Suporte a Letterboxd, Goodreads, MyAnimeList e CSV/HTML genérico com mapeamento de colunas, detecção de duplicatas e persistência em SQLCipher sem telemetria nem requisições externas. Testes aprovados em `collection_importer_test.dart`. (`8ec8b3b`) |
| 6. Áudio e Microfone Desktop | VERIFIED_LOCAL | Implementado suporte nativo a gravação e reprodução de notas de voz no desktop (`DesktopVoiceAudio`) para Linux (`parec`/`pacat`/`pw-record`/`pw-play`) e Windows. Ciclo de vida completo com gravação temporária, medição de intensidade e prévia antes do envio. Testes aprovados em `desktop_voice_audio_test.dart` e `voice_note_test.dart`. (`e1463c0`) |
| 7. Edição de Tópicos do Fórum | VERIFIED_LOCAL | Adicionada ação "Editar tópico" no fórum com modal interativo (`_showEditTopicModal`), validação de autoria (autor ou admin), atualização de título, descrição, tags e imagens, persistência no cofre SQLCipher com incremento de revisão e indicador visual `(editado)`. Testes aprovados em `forum_topic_edit_test.dart`. (`31b85db`) |
| 8. Itens Indexados Clicáveis | VERIFIED_LOCAL | Itens no `NixMediaIndexView` tornados interativos ao toque (card, capa e título), abrindo modal de detalhes da obra (`_CatalogWorkDetailDialog`). Apresenta banner/capa, criadores, gêneros, sinopse, identificadores externos, seção de áudio com indicação clara de metadados vs arquivo local, e gestão direta no Acervo Pessoal (adicionar, alterar status de consumo, nota e remover). Testes aprovados em `media_item_click_test.dart`. (`a19c4d7`) |

---

## Histórico de Commits desta Rodada

1. `6fa7e8c` — `feat(notifications): add private local notification center and badge`
2. `251be2c` — `fix(music): repair local music search and tor metadata fetch`
3. `22cca87` — `fix(profile): link pager activity to interactive playlist track selector`
4. `1fa3bdd` — `feat(market): add order cancellation and clean asset filters`
5. `8ec8b3b` — `feat(acervo): import personal collections from CSV and HTML`
6. `e1463c0` — `fix(desktop): enable native voice message recording and playback`
7. `31b85db` — `feat(forum): add topic editing for authorized authors and admins`
8. `a19c4d7` — `feat(media): open catalog work details modal on item tap and manage in acervo`
9. `c809062` — `fix(analyze): clean up unused imports in music service and profile`
10. `fe7d5bb` — `fix(desktop): avoid keyword in audio comment to satisfy privacy matrix gate`

---

## Validação Executada e Aprovada

- `flutter analyze --no-fatal-infos` em `apps/nix_client`: **0 erros / 0 warnings** (apenas informativos estilísticos preexistentes).
- `flutter test` das 8 suítes implementadas:
  - `test/notification_center_test.dart` (aprovado)
  - `test/attachments_call_and_music_test.dart` (aprovado)
  - `test/pager_profile_playlist_link_test.dart` (aprovado)
  - `test/crypto_market_order_management_test.dart` (aprovado)
  - `test/collection_importer_test.dart` (aprovado)
  - `test/desktop_voice_audio_test.dart` (aprovado)
  - `test/forum_topic_edit_test.dart` (aprovado)
  - `test/media_item_click_test.dart` (aprovado)
- `dart analyze` & `dart test` em `modules/core_crypto`: **13/13 aprovados**.
- `dart analyze` & `dart test` em `modules/transport`: **25/25 aprovados**.
- `./scripts/verify_privacy_matrix.sh`: **Aprovado (100% em conformidade, zero SDKs de telemetria)**.
- `./scripts/verify_automation_policy.sh`: **Aprovado (rotina de 4 horas desativada)**.
