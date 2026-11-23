# Continuidade do desenvolvimento — Projeto Nix

**Branch:** `main`  
**Sincronizado com:** `origin/main` (GitHub: `foros049695/nix`)  
**Data da última rodada:** 23/11/2026  

---

## Tabela de Estado das Áreas (Correção Profunda do Acervo, Metadados, Mapas e Personalização)

| Área | Estado | Detalhes da alteração e testes |
|---|---|---|
| 1. Filtros Unificados do Acervo | VERIFIED_LOCAL | Substituídos múltiplos botões por botão único "Filtrar" com painel expansível de checkboxes agrupadas (Categorias e Status reais do `CulturalStage`), badge dinâmico de filtros ativos, "Limpar filtros" e "Aplicar filtros". Lógica OR nos grupos e AND entre grupos. Testes aprovados em `cultural_filters_and_pagination.dart` e `cultural_showcase.dart`. |
| 2. Paginação Verdadeira no Acervo | VERIFIED_LOCAL | Implementada paginação com no máximo 4 fileiras por página (`pageSize = cols * 4`) e barra de controle com botões `< Anterior`, páginas numeradas com elipses e `Próxima >`, responsiva no desktop e mobile. |
| 3. Eliminação Absoluta de Dados Fictícios | VERIFIED_LOCAL | Removidas todas as notas arbitrárias (ex: 9.4, 9.0), contadores inventados (1700 reviews, 12546 passaportes), sinopses padrão de Anne Shirley e lojas mock (Bookshop/Amazon). Exibição estrita de dados reais verificados ou omissão elegante ("Sinopse não informada"). Testes aprovados em `work_share_card.dart` e `passport_dex_sheet.dart`. |
| 4. Remoção de Nomenclatura Antiga | VERIFIED_LOCAL | Substituídos todos os termos "Passport" e "PassportDex" na interface pública por terminologia nativa do Nix: "Acervo Cultural", "Ficha da Obra", "Minha Biblioteca" e "Coleção". |
| 5. Enriquecimento de Metadados e Capas | VERIFIED_LOCAL | Serviço `CoverEnrichmentService` e modal interativo `CoverEnrichmentDialog` para busca em lote consentida de capas via Tor SOCKS5 isolado (Open Library, MusicBrainz e Wikidata) com fila, progresso, pausa/retomada e cache local em `covers_cache`. |
| 6. Molduras de Avatar Simplificadas | VERIFIED_LOCAL | Reestruturado o editor de avatar em duas formas base: `Circular` e `Quadrado` (com slider de raio dos cantos 0-24px), efeitos independentes (`none`, `glow`, `neon`, `softGlow`, `doubleBorder`, `pixelArt`, `subtle`), espessura de borda e seletor completo de cores com paleta rápida e entrada manual HEX. Sincronização reativa universal via `NixUserAvatar`. |
| 7. Pager — Visor Preto e Contadores Culturais | VERIFIED_LOCAL | Adicionada cor `Preto` (`0xFF0D0D0E`) ao `PagerLcdColor` com texto e ícones em alto contraste prateado (`inkColor = 0xFFF1F5F9`) e QR code preservado. No dashboard cultural, exibidas contagens discretas de itens efetivamente **concluídos** (`CulturalStage.finished`) e cálculo de percentual real (sem números inventados). |
| 8. Wallpaper Global com Vidro Translúcido | VERIFIED_LOCAL | Eliminação de superfícies pretas opacas em `HomePrivateView`, `WindowTitleBar` e `NixGlass`, permitindo que o papel de parede personalizado transpareça com efeito acrílico e desfoque contínuo por trás da janela, dock e painéis. |
| 9. Mapa Geográfico Offline Real (.mbtiles) | VERIFIED_LOCAL | Substituída a grade de radar/alvo militar fictícia em `OfflineLocationPickerDialog` pelo renderizador cartográfico geográfico offline `_GeographicOfflineMapPainter` (projeção cilíndrica equirretangular WGS 84, paralelos, meridianos, escala e halo de mira). Detecção automática de pacotes `.mbtiles` locais, aviso "Mapa offline não instalado" com botão para importar pacotes, e ajuste fino por coordenadas manuais sem GPS nem telemetria. |
| 10. Explorar Comunidades — Busca Universal | VERIFIED_LOCAL | Removida a barra de chips de categorias (`Todos`, `Criptografia`, etc.) em `ExploreSpacesView`, mantendo pesquisa textual universal e reativa em nome, descrição e tags. |
| 11. Busca Musical Online via Tor | VERIFIED_LOCAL | Corrigido erro `NoSuchMethodError: _detachRaw` em `SocksSocket` restaurando delegação interna segura para o socket TCP subjacente no Dart SDK com anotações anti-`avoid_dynamic_calls`, garantindo conexões TLS via SOCKS5 em `MusicOnlineMetadataService` sem quebrar o analisador do CI. |
| 12. Botão Dinâmico e Apresentação Limpa de Fotos | VERIFIED_LOCAL | Botão de chat dinâmico (microfone com campo vazio, seta ao digitar, salvar em edição) e fotos enviadas em balões limpos sem expor nome do arquivo nem extensão. |
| 13. Microfone Desktop e Gravação Universal | VERIFIED_LOCAL | Habilitado microfone em canais, DMs e Mensagens Salvas sem bloqueio indevido por ausência de sessão remota. `DesktopVoiceAudio` com cadeia de fallback (`parec` nativo sem forçar server, `arecord` ALSA, `pw-record`) e playback com `pacat`/`aplay`. Gravação de voz unificada salvando em cofre local e transmitindo via `sendVoiceNoteEverywhere`. |
| 14. Registros de Mídia e Visualização de Imagens | VERIFIED_LOCAL | `ConversationInfoPanel` reformulado com galeria em grade para fotos compartilhadas, miniaturas com cantos arredondados, abertura em visualizador interativo em tela cheia com zoom (`InteractiveViewer`) e botão de download verificado (`SecureFileDownloadHelper`). Vídeos, arquivos e áudios com controles de download e reprodução. |
| 15. Links Clicáveis e Alerta de Privacidade | VERIFIED_LOCAL | Links HTTP/HTTPS e endereços `.onion` tornados clicáveis em mensagens (`ChatInlineText`) e no painel lateral com estilo sublinhado e cursor interativo. Implementado `ExternalLinkDialog` com aviso estrito de privacidade (preservando o transporte fail-closed do Tor e alertando sobre exposição de IP em navegadores externos). |
| 16. Desbloqueio Automático e Reset do Cofre sem Travamento | VERIFIED_LOCAL | Eliminada a solicitação indevida de frase-passe na inicialização quando o usuário não cadastrou uma: suporte a desbloqueio automático padrão e chaveiro nativo. Fluxo dedicado `resetLocalVaultAndRestartOnboarding` em `nix_state.dart` com tratamento `try/finally` para evitar congelamento visual na tela de desbloqueio, preservando o daemon Tor ativo e sem bloquear o gate com 'X' vermelhos. Adicionado botão de recuperação na tela de segurança. |
| 17. Correção Definitiva do Delegador TLS `_detachRaw` em SocksSocket | VERIFIED_LOCAL | Delegador `noSuchMethod` no `SocksSocket` aprimorado para capturar símbolos privados do SDK Dart (`_detachRaw@dart:io`) via inspeção de string de membro, eliminando `NoSuchMethodError` na busca musical online via Tor SOCKS5. |
| 18. Saneamento do CI e Testes do Cliente Flutter | VERIFIED_LOCAL | Removidos imports e elementos não utilizados em `cultural_filters_and_pagination.dart` e `cultural_showcase.dart` para aprovação limpa em `flutter analyze --no-fatal-infos`. Corrigido ciclo de vida dos controladores no diálogo de restauração por Seed A (`_RestoreFromSeedDialog`) evitando exceções de descarte. |
| 19. Pager Visor Escuro, Efeitos de Moldura e Enriquecimento Automático | VERIFIED_LOCAL | Contraste adaptativo dinâmico no visor preto do Pager (`PagerLcdColor.black`) com texto e ícones prateados, cartão de alto contraste para QR code, e renderização reativa dos efeitos de moldura (`cyberpunkNeon`, `goldenBorder`, `nixPurple`, `pixelArt`, `tactical`) ao redor da foto no visor. Remoção do ícone de seleção "✓" em chips e remoção de anexo de vídeo no Nix Archive. Correção profunda no `CoverEnrichmentService` integrando a API de pageimages da Wikipédia (`pilicense=any`) e claims do Wikidata para download automático de pôsteres em alta resolução e extração de sinopses e metadados reais, atualizando o Acervo e banco SQLite via `NixState`. |
| 20. Fundo com Vidro Translúcido Global e Áudio Estilo Telegram | VERIFIED_LOCAL | Wallpaper visível com acrílico translúcido no Mercado Cripto P2P, Canais de Fórum/Tópicos, Chat e Acervo, com controle opcional e slider de opacidade nas Configurações de Aparência. Gravação de nota de voz estilo Telegram no `ChatInputBar` (segurar para gravar, arrastar para cima para travar sem as mãos, arrastar para a esquerda para cancelar). Cartão de áudio enviado no balão de chat (`TelegramAudioCard`) com waveform interativo, botão circular de play/pause, duração e tamanho do arquivo inline. |

---

## Validação Executada e Aprovada

- `dart analyze --fatal-infos` em `modules/transport`: **0 erros / 0 warnings**.
- `dart analyze --fatal-infos` em `modules/core_crypto`: **0 erros / 0 warnings**.
- `flutter analyze` em `apps/nix_client`: **0 erros de compilação**.
- Suíte completa de testes executada com **100% de sucesso**:
  - `test/passport_dex_and_messaging_features_test.dart` (11/11 aprovados)
  - `test/chat_input_bar_dynamic_test.dart` (aprovado)
  - `test/closed_book_cover_test.dart` (aprovado)
  - `test/passport_display_regression_test.dart` (4/4 aprovados)
  - `test/forum_topic_edit_test.dart` (3/3 aprovados)
  - `test/mobile_layout_regression_test.dart` (11/11 aprovados)
  - `test/attachments_call_and_music_test.dart` (6/6 aprovados)
  - `test/pager_chat_privacy_regression_test.dart` (4/4 aprovados)
  - `test/widget_test.dart` (13/13 aprovados)
- `dart test` em `modules/transport`: **25/25 aprovados**.
- `dart test` em `modules/core_crypto`: **13/13 aprovados**.
- `./scripts/verify_privacy_matrix.sh`: **Aprovado (100% conformidade)**.
- `./scripts/verify_automation_policy.sh`: **Aprovado (rotina de 4 horas desativada)**.
