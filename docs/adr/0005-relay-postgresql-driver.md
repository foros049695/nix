# ADR 0005: Adoção do Driver PostgreSQL (`github.com/lib/pq`) no Nix Relay

## Status
Proposto (registro retroativo)

## Contexto
Conforme o [ADR 0001](0001-record-architecture-decisions.md) e o [`CONTRIBUTING.md`](../../CONTRIBUTING.md), toda nova dependência externa exige registro formal em ADR. Inicialmente, o serviço `services/nix_relay` utilizava exclusivamente a biblioteca padrão do Go (`go 1.22`) com armazenamento atômico em arquivos JSON (`BlindMailboxStore`).

Na consolidação da Fase 2 (commit `1dea5f3`), o mantenedor introduziu o backend opcional `PostgresMailboxStore` (`services/nix_relay/internal/buffer/postgres_store.go`), apoiado no schema transacional PostgreSQL 17 (`database/schema/relay.sql`), adicionando `github.com/lib/pq v1.12.3` em `services/nix_relay/go.mod` para registrar o driver `postgres` em `database/sql`.

> **Nota sobre este registro retroativo:** as justificativas e comparações de alternativas abaixo foram reconstruídas a partir do histórico Git e da implementação atual para regularizar a rastreabilidade documental, cabendo ao mantenedor revisar, ajustar o que julgar pertinente e promover o status para `Aceito`.

## Decisão Registrada
1. Utilizar `github.com/lib/pq v1.12.3` como única dependência externa de `services/nix_relay/go.mod` para o driver `postgres` sobre `database/sql` em `PostgresMailboxStore`.
2. Preservar `BlindMailboxStore` (baseado em sistema de arquivos, sem banco externo) como implementação padrão leve para execução local e testes unitários sem infraestrutura adicional.
3. Manter o uso do driver confinado a `services/nix_relay/internal/buffer/postgres_store.go` atrás da interface `RelayStore`, com testes de integração PostgreSQL condicionados à variável `NIX_TEST_PG_DSN`.

## Alternativas e Trade-offs (Reconstrução)
1. **Permanecer restrito à stdlib Go apenas com `BlindMailboxStore` em disco:** mantém zero dependências externas, mas exige coordenação manual de arquivos por caixa postal sob maior concorrência e não oferece as rotinas nativas de backup/restauração transacional (`pg_dump` / `pg_restore` de estrutura) previstas na Fase 2.
2. **`github.com/jackc/pgx/v5` (`stdlib` ou pool nativo):** alternativa moderna e ativamente evoluída no ecossistema Go, porém traz árvore transitiva maior (`pgpassfile`, `pgservicefile`, `puddle/v2`, `golang.org/x/crypto`, `golang.org/x/sync`, `golang.org/x/text`). Para o escopo atual de `RelayStore` sobre `database/sql`, `github.com/lib/pq` adiciona apenas um módulo em `go.sum` sem dependências transitivas extras e sem telemetria. Caso o projeto passe a exigir recursos específicos do `pgx`, a mudança deverá ser precedida de novo ADR.
3. **Bindings CGo sobre `libpq` em C:** exigiria compilador C e bibliotecas dinâmicas no build e no deploy do binário `nix-relay`, ao passo que `github.com/lib/pq` preserva compilação Go pura (`CGO_ENABLED=0`).

## Compatibilidade de Licenças com GPL-3.0
O Projeto Nix é distribuído sob **GNU General Public License v3.0 (`GPL-3.0`)** ([`LICENSE`](../../LICENSE)).

| Dependência | Manifesto | Licença | Fontes Verificadas |
|---|---|---|---|
| `github.com/lib/pq v1.12.3` | `services/nix_relay/go.mod` | MIT (Expat) | [pkg.go.dev/github.com/lib/pq@v1.12.3?tab=licenses](https://pkg.go.dev/github.com/lib/pq@v1.12.3?tab=licenses); [`docs/THIRD_PARTY_LICENSES.md`](../THIRD_PARTY_LICENSES.md) |

- **Avaliação de compatibilidade:** a licença MIT (classificada pela Free Software Foundation como *Expat License*) é uma licença de software livre permissiva não-copyleft expressamente compatível com a GNU GPLv3 ([FSF — Various Licenses and Comments about Them: `#Expat`](https://www.gnu.org/licenses/license-list.html#Expat)). Não há cláusulas de restrição de uso, publicidade ou retaliação incompatíveis com a redistribuição sob GPL-3.0.

## Consequências
- `services/nix_relay` deixa de ser estritamente *stdlib-only*, passando a exigir `go.sum` íntegro no controle de versão, no cache de CI e na geração de SBOM (`scripts/generate_sbom.sh`).
- Zero dependências transitivas adicionais em `services/nix_relay/go.sum` e compilação 100% Go puro (`CGO_ENABLED=0` permanece suportado).
- Como `github.com/lib/pq` encontra-se em regime de manutenção conservadora upstream, eventuais necessidades futuras de recursos avançados do PostgreSQL deverão avaliar migração isolada atrás de `RelayStore`.
