# Módulo `media` (Placeholder)

> **Estado atual:** este diretório é apenas um *placeholder* estrutural — **não é um pacote Dart/Flutter ou Go compilável** (não possui `pubspec.yaml` nem código-fonte próprio).

## Marco no Roadmap

- **Fase 8 — Nix Media, Index e GitHub Discovery** ([`ROADMAP.md`](../../ROADMAP.md) e [`docs/MEDIA.md`](../../docs/MEDIA.md)).

## Onde vive a implementação atual

- [`apps/nix_client/lib/core/media/media_catalog_service.dart`](../../apps/nix_client/lib/core/media/media_catalog_service.dart) — `MediaCatalogService` e conectores externos estritamente opt-in (`OptInMediaConnectorKind`: TMDB, AniList e Jellyfin).
- [`apps/nix_client/lib/core/database/repositories.dart`](../../apps/nix_client/lib/core/database/repositories.dart) — `MediaRepository` (catálogo local cifrado e índice FTS5).
- [`apps/nix_client/lib/core/models/cultural_item.dart`](../../apps/nix_client/lib/core/models/cultural_item.dart) e [`apps/nix_client/lib/features/profile/cultural_showcase.dart`](../../apps/nix_client/lib/features/profile/cultural_showcase.dart) — modelo e visualização do Acervo Cultural no cliente.
