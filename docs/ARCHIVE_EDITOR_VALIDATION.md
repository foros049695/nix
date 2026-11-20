# Archive, rascunhos e moderação

| Requisito | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| Remover silenciamento | `article_detail_view.dart`, `archive_moderation_dialog.dart` | Lista autores silenciados e bloqueados no cofre e permite restaurá-los, inclusive quando todos os comentários estão ocultos | `archive_ui_full_flow_test.dart` | VERIFIED_LOCAL | A ação se aplica ao Archive local. |
| Objeto original | `nix_archive_service.dart`, `archive_discussions_test.dart` | Moderação local e comentários continuam separados do artigo assinado | `archive_discussions_test.dart` | VERIFIED_LOCAL | Sincronização entre clientes exige publicação e infraestrutura autorizadas. |
| Editor e leitura | `archive_environment_view.dart`, `archive_document.dart`, `archive_markdown.dart` | Toolbar, desfazer/refazer, títulos, marcas de texto, checklist, citações, links copiáveis, código e tabelas no corpo assinado | `archive_ui_full_flow_test.dart` | VERIFIED_LOCAL | Mídias autorizadas, notas de rodapé e referências estruturadas continuam pendentes. |
| Rascunhos | `archive_environment_view.dart` | Rascunho salvo em fila ao editar, mudar de rascunho ou sair | `archive_discussions_test.dart` | IMPLEMENTED | A recuperação após interrupção abrupta respeita a janela do autosave. |
