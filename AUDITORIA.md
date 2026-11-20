# Auditoria do Projeto Nix

## Resumo

Base `552f0b3d3514727944bef6f4740336cb4926f5dc`, branch original `main`. O Nix é um monorepo pré-alfa de mensageria local-first, com cliente Flutter, módulos Dart de criptografia e transporte, relay Go com armazenamento em disco ou PostgreSQL, migrações SQL e ferramentas Python/Bash. A varredura automatizada processou os 449 arquivos rastreados, incluindo 405 arquivos de texto, com inventário, buscas de padrões e verificação de sintaxe aplicável. A revisão manual seguiu os fluxos de maior impacto e os candidatos encontrados. Fontes e imagens receberam inventário de tipo, tamanho e hash. A fixture SQLite passou em `integrity_check`.

## Linha de base

| Verificação | Resultado antes das alterações |
|---|---|
| Relay | Go 1.23.12, `go build ./...`, `go vet ./...` e `go test -race ./...` aprovados. PostgreSQL vivo depende de `NIX_TEST_PG_DSN`. |
| Dart | Criptografia com 13 testes e transporte com 22 testes aprovados. Análise sem diagnósticos e compilação kernel das entradas de verificação aprovada. Transporte executado em namespace isolado com loopback. |
| Flutter | Análise sem erros ou avisos e 210 informações. 215 testes aprovados e 3 saltados. |
| Empacotamento | Linux local bloqueado por CMake e GTK de desenvolvimento ausentes. Android local bloqueado por ausência do SDK. Ambos os builds da base passaram nas [Actions](https://github.com/foros049695/nix/actions/runs/44734927545). |
| Regras estáticas | Matriz de privacidade, política de automação, sintaxe Python/Bash e `git diff --check` aprovados. Os dois arquivos JSON de configuração do VS Code usam JSONC. |
| Inventário de dependências | SBOM da base com 90 componentes e zero módulos Go. Busca por formatos usuais de segredos no snapshot sem ocorrências confirmadas. A chave Ed25519 versionada do catálogo é uma fixture identificada e rejeitada no modo de produção. |

## Achados

As linhas abaixo se referem ao commit de base.

| ID | Categoria | Severidade | Arquivo e linhas | Problema | Correção proposta |
|---|---|---|---|---|---|
| A-001 | Segurança | Alta | `services/nix_relay/internal/buffer/store.go:408,441–461,529–539`, `postgres_store.go:387–398` | A política de escrita deixa de exigir autorização quando o último token perde validade. O backend de arquivos também ignora erro ao ler o registro de permissões. | Preservar a política após revogação/expiração e tratar falha de consulta ou leitura de forma fechada. |
| A-002 | Privacidade | Alta | `services/nix_relay/cmd/relay/main.go:127–132`, `internal/buffer/store.go:30–36` | A leitura devolve o token auxiliar de cota do emissor junto com o envelope. | Separar campos públicos de metadados de armazenamento. |
| A-003 | Segurança operacional | Alta | `scripts/run_maintenance_audit.py:145–163`, `AGENTS.md:15` | A ferramenta manual executa testes de apagamento no ambiente herdado pelo operador e executa os testes de transporte sem isolamento de rede. | Isolar o diretório pessoal e exigir namespace isolado para os testes de transporte. |
| A-004 | Consistência | Média | `services/nix_relay/internal/buffer/store.go:483–524` | Falhas de persistência deixam uma alteração de capability em memória e o estado antigo no disco. | Restaurar a versão anterior se a gravação falhar. |
| A-005 | Lógica | Média | `services/nix_relay/internal/buffer/postgres_store.go:208–215,305–336` | A cota em trânsito cresce com cada gravação. ACK e expiração não liberam o consumo, e o contador só vive em memória. | Contabilizar cota no banco junto com as transações de inserção, ACK e expiração. |
| A-006 | Segurança | Média | `modules/transport/lib/nix_transport.dart:574–618` | O diagnóstico de timeout pode incluir o comando inteiro de autenticação. O canal de controle também permite chamadas sobrepostas sobre a mesma fila de respostas. | Redigir mensagens de erro, rejeitar quebras de linha e serializar os comandos. |
| A-007 | Lógica | Média | `services/nix_relay/internal/buffer/store.go:147–152` | O TTL solicitado é convertido para nanossegundos antes da comparação com o limite, o que permite estouro aritmético. | Comparar em segundos antes da conversão. |
| A-008 | Confiabilidade | Média | `tools/metadata_builder/build_catalog.py:357–362,818–831` | O gerador apaga a base anterior antes de validar dados e assinatura da substituta. | Gerar e assinar em temporários irmãos antes de substituir as saídas. |
| A-009 | Qualidade | Média | `scripts/generate_sbom.sh:16–30,65–76` | O parser omite a dependência Go declarada em `require` de uma linha. O identificador do SBOM tem formato de UUID inválido. | Incluir as duas sintaxes e emitir UUID determinístico válido. |
| A-010 | CI | Baixa | `.github/workflows/ci.yml:3–7` | Branches `chore/**` não recebem a validação de push antes de uma PR. | Incluir esse prefixo no filtro. |
| A-011 | Documentação | Baixa | `README.md:322–327`, `docs/WALLET.md:27–38` | O guia do piloto só descreve a simulação de negociação. | Documentar o modo por convite e o limite da validação fora do laboratório. |
| A-012 | Arquitetura | Baixa | `apps/nix_client/lib/state/nix_state.dart:1014–1077,1455–1572,2237–2389,3570–3690` | A fachada de 5.466 linhas controla persistência, ciclo de vida, perfil e negociação, além de roteamento da interface. | Planejar extrações por fronteira de responsabilidade com testes de contratos e compatibilidade. |
| A-013 | Privacidade | Média | `services/nix_relay/internal/buffer/store.go:30–36,155–167,345–409` | O backend de arquivos grava o identificador de cota em claro. | Planejar migração dos registros duráveis para hash e retenção compatível com instalações existentes. |

## Plano de ação

1. Crítica. Nenhum achado confirmado nessa severidade.
2. Alta. Corrigir A-001, A-002 e A-003.
3. Média. Corrigir A-004, A-006, A-007, A-008 e A-009. Registrar decisões operacionais de A-005 e A-013.
4. Baixa. Corrigir A-010 e A-011. Registrar a fronteira proposta para A-012.

## Itens pendentes de decisão ou infraestrutura

- **A-005 e A-013.** A contabilização em PostgreSQL e a conversão de registros existentes pedem migração de dados, teste com PostgreSQL 17 e decisão de operação para cópias de backup.
- **A-012.** A extração de uma fachada central envolve alterações de ciclo de vida e pressupostos de compatibilidade. Convém separar esse esforço da correção pontual.
- **Validação externa.** As buscas de padrões se limitam ao snapshot. Uma revisão de histórico com scanner dedicado e consulta de avisos por versão, um teste completo em Tor público com dois aparelhos e a homologação de implantação continuam sendo etapas independentes.
