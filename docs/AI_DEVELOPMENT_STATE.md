# Estado de desenvolvimento

Branch autorizada `main` local. Base inicial `36768cf`. Para obter o HEAD e o último commit funcional, use `git log -4 --oneline`. Distribuição privada e sem releases.

| Etapa | Estado |
|---|---|
| Presença e membros em Explorar | Removidos os valores de produção presumidos. Espaços próprios exibem o proprietário local conhecido. Presença remota depende de fonte verificável. |
| Grupo convencional e fórum | Próxima etapa. |
| Demais tarefas | Aguardam as etapas anteriores. Chamadas e enquetes já têm ensaios em laboratório, com homologação física pendente. |

Para retomar, leia `AGENTS.md`, este arquivo e `git status --short --branch`. No cliente, use HOME isolado e rode `flutter analyze --no-fatal-infos` e `flutter test`. Na raiz, rode os portões de privacidade e automação.

Explorar passou os 4 testes de `passport_display_regression_test.dart`. O formato de grupo passou 12 testes de fórum SQLCipher e layout móvel, incluindo conversão, desbloqueio e restauração dos tópicos. Próxima etapa: imagens no formulário de tópico.

Imagem de tópico incorporada ao cofre com a sanitização do Archive. O teste SQLCipher confirmou os bytes após alternar o formato e reabrir o cofre. Recorte manual do anexo segue pendente.
