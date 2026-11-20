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


## Vídeo e reações

Em **Novo artigo**, **Adicionar vídeo** aceita um MP4 local de até 2 MiB.
A prévia usa os bytes do MP4. A publicação exige confirmação e preserva o
arquivo original, inclusive possíveis metadados e faixas de áudio. O Archive
recusa contêiner fragmentado e referências externas de mídia e incorpora os
bytes ao conteúdo assinado. No Android, o reprodutor nativo usa uma cópia no
cache do aplicativo. No desktop, o botão abre o reprodutor associado pelo
sistema após confirmação.

Em artigos verificados, **Reações assinadas** permite escolher, trocar ou
retirar uma reação por identidade. O contador usa a revisão assinada mais
recente. Para artigos públicos, a reação usa a mesma malha de réplicas do
Archive. Reações em artigos restritos ficam locais. A retirada corrige o
contador ao receber a revisão nova. Réplicas podem manter a revisão anterior.

O teste distribuído usa duas bases independentes e réplicas em laboratório.
Foram verificados um MP4 H.264 gerado para o ensaio, rejeição de referências a
mídia externa, recuperação de rascunho, isolamento de conteúdo restrito e
aplicação de reações entregues fora de ordem.
