# Continuidade do desenvolvimento — Projeto Nix

**Branch:** `main`  
**Sincronizado com:** `origin/main` (GitHub: `foros049695/nix`)  
**Data da última rodada:** 23/11/2026  

---

## Tabela de Estado das Áreas (Etapa de Mensageria Moderna, Personalização, Pager e Passaporte Dex)

| Área | Estado | Detalhes da alteração e testes |
|---|---|---|
| 1. Botão Dinâmico do Chat (Microfone / Envio / Salvar) | VERIFIED_LOCAL | Implementada alternância unificada e fluida sem concorrência de botões (`ChatInputBar`): microfone com campo vazio, seta de envio ao digitar ou com anexos selecionados, e ícone de salvar em modo de edição. Otimizado sem loops de `setState` em cursor blink. Testes aprovados em `chat_input_bar_dynamic_test.dart` e `widget_test.dart`. |
| 2. Apresentação de Imagens, Vídeos e Documentos | VERIFIED_LOCAL | Fotos exibidas limpas no balão sem nome de arquivo nem extensão por padrão, com zoom gestual via `InteractiveViewer`. Vídeos com miniatura, overlay play e duração. Documentos com cartão distinto, ícone por formato e tamanho. Testes aprovados em `message_attachment_tile.dart` e `widget_test.dart`. |
| 3. Qualidade de Envio de Imagens (3 Modos) | VERIFIED_LOCAL | Implementado seletor interativo (`ImageQualityDialog`) com 3 modos: Foto Comprimida (otimizada, EXIF stripped), Foto em Qualidade Original e Enviar como Arquivo (bytes intocados como documento). Prévia e tamanho exibidos. |
| 4. Avisos de Segurança para Downloads | VERIFIED_LOCAL | Utilitário soberano `SecureFileDownloadHelper`: diálogo obrigatório com aviso explícito de segurança para arquivos de terceiros, sanitização contra path traversal, validação SHA-256 pré e pós gravação em disco em pasta segura de downloads sem autoexecução. Testes aprovados em `passport_dex_and_messaging_features_test.dart`. |
| 5. Menu Ampliado de Anexos (6 Opções) | VERIFIED_LOCAL | Menu expansível do chat com 6 opções dedicadas com ícones estilizados: Fotos e vídeos, Documentos, Artigos (Archive), Localização (Mapa Tático), Música (Playlist Pager) e Acervo (PassportDex). Envolvido em `SingleChildScrollView` responsivo. |
| 6. Localização por Mapa Offline com Marcador Manual | VERIFIED_LOCAL | Diálogo `OfflineLocationPickerDialog` com grade tática vetorial offline, arrasto manual de pin, cálculo de lat/lng sem chamadas GPS/clearnet, serialização criptografada `[NIX_LOC]:{...}` e cartão estruturado `OfflineLocationCard` com mini-mapa estático e ação "Ver no Mapa Tático". Testes aprovados em `passport_dex_and_messaging_features_test.dart`. |
| 7. Wallpaper Global no Workspace | VERIFIED_LOCAL | Camada contínua `InterfaceWallpaperLayer` estendida por trás de todo o workspace (painel de navegação, canais, chat e gaveta lateral) com suporte a opacidade, desfoque e vidro translúcido em `workspace_frame.dart` e `app_shell.dart`. |
| 8. Molduras Personalizáveis para Avatares | VERIFIED_LOCAL | Adicionados estilos `avatarFrameStyle` (`circle`, `roundedSquare`, `pixelArt`, `cyberpunkNeon`, `goldenBorder`, `nixPurple`, `tactical`), controle de largura de borda `avatarBorderWidth` e cor personalizada `avatarFrameColorHex`. Sincronização reativa universal via `NixUserAvatar`. Testes aprovados em `passport_dex_and_messaging_features_test.dart`. |
| 9. Pager — Cinco Estrelas Privadas de Segurança | VERIFIED_LOCAL | Indicador visual de 5 estrelas soberanas e barra de progresso retrô no `PagerProfile`, auditando condições locais reais: SQLCipher ativo, Tor Onion v3 ativo, chaves ativas em memória, ausência de telemetria e transporte fail-closed. Diálogo de auditoria detalhada ao toque. |
| 10. Pager — Estatísticas Culturais e Gráficos | VERIFIED_LOCAL | Dashboard cultural no Pager com contagem de Livros, Mangás, Filmes e Séries, gráfico de barras com distribuição de consumo, percentual de conclusão e selo soberano com cadeado. Testes aprovados em `passport_dex_and_messaging_features_test.dart`. |
| 11. Molduras Culturais e Correção dos Livros 2.5D Fechados | VERIFIED_LOCAL | Substituído o modelo de livro aberto por livro físico fechado (`_closedBook`) com lombada realista, profundidade em perspectiva isométrica, blocos de páginas com ranhuras de corte e proporções ideais para livros e mangás. Testes aprovados em `closed_book_cover_test.dart` e `passport_display_regression_test.dart`. |
| 12. Fichas Técnicas Completas Padrão PassportDex | VERIFIED_LOCAL | Implementado componente `PassportDexSheet` com arte de capa 2.5D em destaque, metadados completos, avaliação por estrelas, chips interativos de status (`CulturalStage`), estatísticas da comunidade, sinopse e links de referência. |
| 13. Compartilhamento de Obras e Artigos nos Chats (Mini Cards) | VERIFIED_LOCAL | Mini cards em balões de chat: `WorkShareCard` (formato PassportDex com banner, nota, badges, botão "Ver obra ↗" e "+ Ao Acervo") e `ArticleShareCard` (artigos assinados do Nix Archive com selo de verificação Ed25519). Testes aprovados em `passport_dex_and_messaging_features_test.dart`. |
| 14. Botão "Ver obra" e Painel Lateral Desktop / Sheet Android | VERIFIED_LOCAL | Ao clicar em "Ver obra ↗", abre a ficha técnica no painel lateral direito no desktop mantendo o chat ativo e visível, ou via bottom sheet no Android. Gerenciado no estado soberano via `activeWorkDetail`. |

---

## Validação Executada e Aprovada

- `dart analyze` em `modules/transport`: **0 erros / 0 warnings**.
- `dart analyze` em `modules/core_crypto`: **0 erros / 0 warnings**.
- `flutter analyze --no-fatal-infos` em `apps/nix_client`: **0 erros / 0 warnings**.
- Suíte completa de testes executada com **100% de sucesso**:
  - `test/passport_dex_and_messaging_features_test.dart` (11/11 aprovados)
  - `test/chat_input_bar_dynamic_test.dart` (aprovado)
  - `test/closed_book_cover_test.dart` (aprovado)
  - `test/passport_display_regression_test.dart` (aprovado)
  - `test/forum_topic_edit_test.dart` (3/3 aprovados)
  - `test/mobile_layout_regression_test.dart` (11/11 aprovados)
  - `test/attachments_call_and_music_test.dart` (6/6 aprovados)
  - `test/pager_chat_privacy_regression_test.dart` (4/4 aprovados)
  - `test/widget_test.dart` (13/13 aprovados)
- `dart test` em `modules/transport`: **25/25 aprovados**.
- `dart test` em `modules/core_crypto`: **13/13 aprovados**.
- `./scripts/verify_privacy_matrix.sh`: **Aprovado (100% conformidade)**.
- `./scripts/verify_automation_policy.sh`: **Aprovado (rotina de 4 horas desativada)**.
