# Módulo `transport` (`nix_transport`)

Camada de transporte privado fail-closed para comunicação via rede Tor Onion v3 no Project Nix.

## Garantias de Arquitetura

- **Fail-Closed por padrão (`TransportMode.torFailClosed`)**: nenhuma URL fora de `[a-z2-7]{56}.onion` é aceita em produção; clearnet IPs e domínios externos lançam `TransportBlockedException` sem fallback silencioso.
- **Zero vazamento de DNS local**: `Socks5Connector` envia exclusivamente endereços do tipo `ATYP = 0x03` (`DOMAINNAME`) para o daemon Tor remoto resolver.
- **Isolamento por stream**: suporte opcional a usuário/senha SOCKS5 (`IsolateSOCKSAuth`).
- **Tor ControlPort**: `TorControlClient` para autenticação hex/cookie/senha, consulta `status/bootstrap-phase` e provisionamento de Hidden Services Onion v3 (`ADD_ONION` / `DEL_ONION`).
- **Store-and-forward cego**: `RelayClient` integra caixas postais cegas (`POST/GET /v1/mailboxes/{id}/envelopes` e `ack`) com derivação de identificador por hash SHA-256.

## Verificação

```bash
dart pub get
dart analyze
dart test
```
