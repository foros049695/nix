# Catálogo, música e progresso cultural

| Requisito | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| Abrir catálogo offline | `catalog_database.dart`, `nix_state.dart` | Inicializa SQLite/SQLCipher no isolate real da consulta, valida o SHA-256 do catálogo embarcado e fecha a conexão se o schema falhar | `offline_media_index_test.dart` | VERIFIED_LOCAL | A reprodução do erro em Android e o aceite em aparelho ficam pendentes. |
| Acentos, nomes originais | `catalog_database.dart` | Preserva letras, marcas e números Unicode ao construir consultas FTS5 parametrizadas | `offline_media_index_test.dart` | VERIFIED_LOCAL | Busca por prefixo segue a segmentação do FTS5. |
| Música | `catalog_database.dart`, `cultural_catalog_picker.dart` | Integra as faixas e álbuns do pacote MusicBrainz já versionado ao índice local | `attachments_call_and_music_test.dart` | VERIFIED_LOCAL | A busca usa metadados. Reprodução, playlists e perfil com áudio permanecem pendentes. |
| Acervo | `cultural_cover_art.dart`, `cultural_showcase.dart`, `cultural_tracking.dart` | Vinil, livro e pôster. Progresso por episódio, capítulo, página ou faixa, status, favoritos, coleções, tags, resenhas e notas | `passport_display_regression_test.dart`, `offline_media_index_test.dart` | PARTIAL | Datas, resenha formatada, horas de jogo e playlists ainda em aberto. |
| Privacidade | `nix_preference_store.dart`, `nix_state.dart` | Migração do acervo, favoritos antigos e faixa do Pager para o cofre. Os dados de acompanhamento saem da projeção pública | `acervo_privacy_migration_test.dart` | VERIFIED_LOCAL | Instalações antigas concluem a migração ao desbloquear o cofre. |
