# Archive, rascunhos e moderação

| Requisito | Arquivos | Implementação | Teste | Resultado | Limitação |
|---|---|---|---|---|---|
| Remover silenciamento | `article_detail_view.dart`, `archive_moderation_dialog.dart` | Lista autores silenciados e bloqueados no cofre e permite restaurá-los, inclusive quando todos os comentários estão ocultos | `archive_ui_full_flow_test.dart` | VERIFIED_LOCAL | A ação se aplica ao Archive local. |
| Objeto original | `nix_archive_service.dart`, `archive_discussions_test.dart` | Moderação local e comentários continuam separados do artigo assinado | `archive_discussions_test.dart` | VERIFIED_LOCAL | Sincronização entre clientes exige publicação e infraestrutura autorizadas. |
| Editor e leitura | `archive_environment_view.dart`, `archive_document.dart`, `archive_markdown.dart` | Toolbar, desfazer/refazer, títulos, marcas de texto, checklist, citações, links copiáveis, código e tabelas no corpo assinado | `archive_ui_full_flow_test.dart` | VERIFIED_LOCAL | Notas de rodapé e imagens locais estão disponíveis. Vídeo autorizado e referências estruturadas continuam pendentes. |
| Rascunhos | `archive_environment_view.dart` | Rascunho salvo em fila ao editar, mudar de rascunho ou sair | `archive_discussions_test.dart` | IMPLEMENTED | A recuperação após interrupção abrupta respeita a janela do autosave. |


## Imagens em publicações

Na aba **Novo Artigo**, escolha **Adicionar imagem**. O editor aceita PNG, JPEG e WebP locais, prepara uma versão estática em PNG, dimensiona o conteúdo e remove metadados. Caminhos, nomes de arquivos e URLs não são incluídos. O editor exibe uma prévia e permite informar legenda ou descrição acessível.

O rascunho guarda as imagens junto do texto no cofre. Ao publicar um artigo com imagens, o Nix pede confirmação específica da divulgação. Os bytes e as legendas integram o conteúdo assinado com Ed25519. O leitor só apresenta as imagens de um objeto verificado e não busca recursos externos. Artigos restritos seguem as regras de replicação do Archive.

Cada artigo aceita até três imagens, com até 384 KiB por imagem e 1 MiB no conjunto após preparação. Os testes cobrem rascunho, exclusão, assinatura, adulteração, leitura e sincronização entre dois clientes no ambiente de laboratório. Clientes antigos continuam a ler o texto e precisam da versão atual para exibir as imagens.
