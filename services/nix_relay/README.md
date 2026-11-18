# Nix Relay (`services/nix_relay`)

Nó transitório **store-and-forward cego** em Go para o Project Nix, projetado para operar atrás de um Tor Hidden Service Onion v3 em `127.0.0.1:8080`.

## Características Implementadas

- **Zero custódia e zero leitura de conteúdo**: armazena exclusivamente envelopes `payload_b64` cifrados pelo cliente.
- **TTL padrão de 7 dias** (`base_ttl_seconds: 604800`) com remoção automática após `POST /ack` ou expiração.
- **AutoPruner com histerese (`internal/buffer/autopruner.go`)**:
  - `< 70%` (retorno por histerese): `NORMAL` — TTL 7 dias, até 50 MB por anexo.
  - `>= 75%`: `LIGHT_RELIEF` — reduz retenção máxima para 4 dias.
  - `>= 85%`: `SEVERE_RELIEF` — reduz retenção para 48 horas e limita anexos a 10 MB.
  - `>= 92%`: `CRITICAL_BLOCK` — teto de 24 horas e bloqueio de anexos > 1 MB (prioridade para texto).
- **Endpoints HTTP**:
  - `GET /healthz`
  - `GET /metrics` (formato Prometheus sem identificadores de usuário ou IP)
  - `POST /v1/mailboxes/{id}/envelopes`
  - `GET /v1/mailboxes/{id}/envelopes`
  - `POST /v1/mailboxes/{id}/ack`

## Verificação e Execução

```bash
go test -v ./...
go vet ./...
go run ./cmd/relay -config configs/relay.local.yaml
```
