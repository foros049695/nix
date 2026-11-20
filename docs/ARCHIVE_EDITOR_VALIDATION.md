# Archive, rascunhos e moderação

| Requisito | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| Remover silenciamento | `article_detail_view.dart`, `archive_moderation_dialog.dart` | Lista autores silenciados e bloqueados no cofre e permite restaurá-los, inclusive quando todos os comentários estão ocultos | `archive_ui_full_flow_test.dart` | IMPLEMENTED | A ação se aplica ao Archive local. |
| Objeto original | `nix_archive_service.dart`, `archive_discussions_test.dart` | Moderação local e comentários continuam separados do artigo assinado | `archive_discussions_test.dart` | VERIFIED_LOCAL | Sincronização entre clientes exige publicação e infraestrutura autorizadas. |
| Rich text | `archive_environment_view.dart` | Rascunhos e prévia limitada encontrados no checkout inicial | `archive_ui_full_flow_test.dart` | PARTIAL | A jornada de editor avançado com tabelas, mídias, notas e desfazer/refazer ainda está pendente. |
