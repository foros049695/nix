# Módulo `wallet` (Placeholder)

> **Estado atual:** este diretório é apenas um *placeholder* estrutural — **não é um pacote Dart/Flutter ou Go compilável** (não possui `pubspec.yaml` nem código-fonte próprio).

## Marco no Roadmap

- **Fase 6 — Monero P2P** ([`ROADMAP.md`](../../ROADMAP.md), [`docs/WALLET.md`](../../docs/WALLET.md) e [`docs/adr/0003-seed-isolation-architecture.md`](../../docs/adr/0003-seed-isolation-architecture.md)).

## Onde vive a implementação atual

- [`apps/nix_client/lib/core/p2p/monero_ad_verifier.dart`](../../apps/nix_client/lib/core/p2p/monero_ad_verifier.dart) — `MoneroIsolationPolicy` (fronteira estrita entre Seed A de mensageria e Seed B financeira, além de restrição de endpoints RPC a loopback/`.onion`) e `SignedMoneroAd` (anúncios P2P assinados com Ed25519 e proteção anti-replay).
- [`apps/nix_client/lib/core/models/monero_order.dart`](../../apps/nix_client/lib/core/models/monero_order.dart) e [`apps/nix_client/lib/features/monero_p2p/monero_p2p_view.dart`](../../apps/nix_client/lib/features/monero_p2p/monero_p2p_view.dart) — modelos e interface do mural Monero P2P no cliente.
- A integração ao vivo com um processo `monero-wallet-rpc` isolado permanece como entrega pendente da Fase 6 em [`ROADMAP.md`](../../ROADMAP.md).
