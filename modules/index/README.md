# Módulo `index` (Placeholder)

> **Estado atual:** este diretório é apenas um *placeholder* estrutural — **não é um pacote Dart/Flutter ou Go compilável** (não possui `pubspec.yaml` nem código-fonte próprio).

## Marco no Roadmap

- **Fase 8 — Nix Media, Index e GitHub Discovery** ([`ROADMAP.md`](../../ROADMAP.md) e [`docs/INDEX.md`](../../docs/INDEX.md)).

## Onde vive a implementação atual

- [`apps/nix_client/lib/core/media/media_catalog_service.dart`](../../apps/nix_client/lib/core/media/media_catalog_service.dart) — `MediaCatalogService` (separação entre busca local offline, consulta remota opt-in e resolução controlada de magnet links com bloqueio *fail-closed* `TorrentClearnetLeakBlockedException`).
- [`apps/nix_client/lib/core/database/repositories.dart`](../../apps/nix_client/lib/core/database/repositories.dart) — `MediaRepository` (indexação e busca textual local via SQLite FTS5 sobre SQLCipher).
- [`apps/nix_client/lib/features/discovery/github_discovery_view.dart`](../../apps/nix_client/lib/features/discovery/github_discovery_view.dart) e [`apps/nix_client/lib/core/models/github_repo.dart`](../../apps/nix_client/lib/core/models/github_repo.dart) — catálogo offline Starwire e política *fail-closed* de transporte para downloads.
