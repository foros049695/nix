# Continuidade do desenvolvimento

Use a branch `main` local. Leia primeiro `AGENTS.md` e a solicitação original incluída no pacote de transferência. A base do pacote é `76b840d`, a última revisão conhecida de `origin/main`; a rodada atual começou em `36768cf`. Os commits permanecem locais e a distribuição do código deve permanecer privada. O pacote não contém instaladores.

| Área | Estado | Alteração verificada ou pendência |
|---|---|---|
| Explorar | PARTIAL | `cb57862` remove números presumidos e usa o proprietário local conhecido. Falta fonte verificável de presença remota e de membros de espaços remotos. |
| Grupos | VERIFIED_LOCAL | `327b9d1` adiciona chat único e fórum. Teste com SQLCipher real confirmou alternância de formato e restauração dos tópicos após reabrir o cofre. Grupos existentes mantêm o modo legado. |
| Imagem em tópicos | PARTIAL | `559d540` salva imagem sanitizada com prévia e remoção. O teste SQLCipher confirma os bytes após reinstanciar o cofre. Falta editor de recorte manual e sincronização do anexo com pares. |
| Banners | PARTIAL | `d39ec5d` adiciona banners locais independentes do avatar, ajuste de posição e exibição em grupo, canal e Explorar local. Falta validação entre pares e acesso direto para editar banner do grupo convencional no desktop. |
| Pastas | PARTIAL | `867e9ef` adiciona expansão com estado persistido. Validado o gesto existente de mover pela lista de canais. Falta testar arrastar diretamente da lista compacta e validar organização no toque. |
| Acervo e capas | VERIFIED_LOCAL | `e31a188` unifica fichas manuais e de catálogo no Media Index e no Passaporte do Pager, com leitura de registros legados. `bd233e3` refina as capas de livros e mangás. Falta teste dedicado da migração após reabrir o cofre e comparação visual em dispositivos. |
| Música | PARTIAL | `f32483a` adiciona carrossel de faixas, busca local e seleção de metadados, com vinculação explícita a um arquivo de áudio. A playlist existente é preservada. Busca online consentida aguarda uma fonte de metadados compatível com a política de transporte. |
| Fundo da interface | PARTIAL | `3e56f23` adiciona seleção local, posição de recorte, opacidade, escurecimento, desfoque, animação opcional e restauração. A animação respeita o ciclo de vida e a redução de movimento. Falta testar GIF e legibilidade em dispositivo, modo economia de energia e cobertura visual das áreas com superfícies próprias. |
| Mercado Cripto | PARTIAL | `c0c2839` renomeia a área existente. Compra e venda XMR permanecem no fluxo atual, com BTC ainda sem mercado integrado. Leia `docs/ROBOSATS_INTEGRATION.md` antes de ligar um coordenador Onion real. |
| Bitcoin e Lightning | PARTIAL | Cliente revisa endereços e valida faturas em nó próprio. A rodada anterior validou Bitcoin Core e LND reais em regtest e usou carteira externa para liquidar fundos sintéticos. Falta pagamento iniciado pelo Nix, confirmação e tratamento de tentativas com resultado desconhecido. Use apenas fundos sintéticos em regtest. |
| Chamadas e enquetes | PARTIAL | `0d9b689`, `4a00302`, `d61b9c0` e `36768cf` incluem sincronização, convite Onion e correções de áudio. Falta validação com dois dispositivos físicos e Tor de ponta a ponta. |

## Validação e retomada

A última rodada direcionada passou 26 testes de layout móvel, playlist local, Passaporte, voz Onion, enquetes e Bitcoin. Também passaram 4 testes direcionados de Explorar, 12 testes de fórum e layout móvel, 5 de anexos, chamadas e pastas, 10 do Passaporte e Media Index e 15 de banners e layout. Os grupos de testes se sobrepõem. A análise estática com `--no-fatal-infos` apresentou somente diagnósticos informativos. A compilação dos instaladores e a suíte integral do HEAD permanecem pendentes.

No cliente `apps/nix_client`, execute `flutter analyze --no-fatal-infos` e `flutter test` com SQLCipher nativo disponível. Execute também os testes dos módulos Dart `modules/core_crypto` e `modules/transport`, `go test ./...` em `services/nix_relay` e as verificações em `scripts/verify_privacy_matrix.sh` e `scripts/verify_automation_policy.sh`. Priorize primeiro a homologação das mudanças parciais. Faça commits pequenos na `main` local e mantenha os binários fora do GitHub Releases.
