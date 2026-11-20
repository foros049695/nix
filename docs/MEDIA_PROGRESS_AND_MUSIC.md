# Catálogo, música e progresso cultural

| Requisito | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| Abrir catálogo offline | `catalog_database.dart`, `nix_state.dart` | Inicializa SQLite/SQLCipher no isolate real da consulta, valida o SHA-256 do catálogo embarcado e fecha a conexão se o schema falhar | `offline_media_index_test.dart` | VERIFIED_LOCAL | A reprodução do erro em Android e o aceite em aparelho ficam pendentes. |
| Acentos, nomes originais | `catalog_database.dart` | Preserva letras, marcas e números Unicode ao construir consultas FTS5 parametrizadas | `offline_media_index_test.dart` | VERIFIED_LOCAL | Busca por prefixo segue a segmentação do FTS5. |
| Música | `catalog_database.dart`, `cultural_catalog_picker.dart` | Integra as faixas e álbuns do pacote MusicBrainz já versionado ao índice local | `attachments_call_and_music_test.dart` | VERIFIED_LOCAL | A busca usa metadados. A playlist do Pager usa arquivos de áudio autorizados pelo usuário. |
| Acervo | `cultural_cover_art.dart`, `cultural_showcase.dart`, `cultural_tracking.dart` | Vinil, livro e pôster. Progresso por episódio, capítulo, página ou faixa, status, favoritos, coleções, tags, resenhas e notas | `passport_display_regression_test.dart`, `offline_media_index_test.dart` | PARTIAL | Datas, resenha formatada, horas de jogo e playlists ainda em aberto. |
| Privacidade | `nix_preference_store.dart`, `nix_state.dart` | Migração do acervo, favoritos antigos e faixa do Pager para o cofre. Os dados de acompanhamento saem da projeção pública | `acervo_privacy_migration_test.dart` | VERIFIED_LOCAL | Instalações antigas concluem a migração ao desbloquear o cofre. |

## Playlist local do Pager no Android

Abra **Menu do Pager → Playlist do Pager → Adicionar faixa** e escolha áudio no armazenamento local. O menu de cada faixa permite mudar a ordem ou removê-la. O player do Android começa apenas após o comando **Reproduzir** e para ao fechar o diálogo ou enviar o Nix para segundo plano.

O cofre guarda a ordem, o nome e a referência escolhida pelo usuário. O Nix abre o arquivo local original por um descritor do Android. A playlist fica privada, inclusive no convite e no Card ID. Se o arquivo for movido ou retirado, selecione-o novamente. A publicação opcional de faixas e a reprodução a partir do catálogo permanecem pendentes. Os testes cobrem o fluxo da interface, o bloqueio de referências externas e a restauração do cofre. A reprodução audível depende de homologação em aparelho.


## Playlist local do Pager no desktop

O mesmo menu aceita WAV no Windows e no Linux. O Windows usa o player WAV do sistema via PowerShell. No Linux, a reprodução requer `paplay` e um servidor PulseAudio ou PipeWire Pulse. O cliente encerra a reprodução ao fechar a playlist. A confirmação da saída audível permanece no ensaio em hardware.
