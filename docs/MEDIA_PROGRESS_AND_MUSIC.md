# Catálogo, música e progresso cultural

| Requisito | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| Abrir catálogo offline | `catalog_database.dart`, `nix_state.dart` | Inicializa SQLite/SQLCipher no isolate real da consulta, valida o SHA-256 do catálogo embarcado e fecha a conexão se o schema falhar | `offline_media_index_test.dart` | VERIFIED_LOCAL | A reprodução do erro em Android e o aceite em aparelho ficam pendentes. |
| Acentos, nomes originais | `catalog_database.dart` | Preserva letras, marcas e números Unicode ao construir consultas FTS5 parametrizadas | `offline_media_index_test.dart` | VERIFIED_LOCAL | Busca por prefixo segue a segmentação do FTS5. |
| Música | `catalog_database.dart`, `cultural_catalog_picker.dart` | Integra as faixas e álbuns do pacote MusicBrainz já versionado ao índice local | `attachments_call_and_music_test.dart` | VERIFIED_LOCAL | A busca usa metadados. Reprodução, playlists e perfil com áudio permanecem pendentes. |
| Acervo | `cultural_cover_art.dart`, `cultural_showcase.dart` | Formatos já presentes de vinil, livro e pôster reutilizados | `passport_display_regression_test.dart` | VERIFIED_LOCAL | Estados detalhados, reviews formatadas e progresso por episódio, capítulo e página aguardam implementação. |
