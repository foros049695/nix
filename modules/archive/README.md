# Módulo `archive` (Placeholder)

> **Estado atual:** este diretório é apenas um *placeholder* estrutural — **não é um pacote Dart/Flutter ou Go compilável** (não possui `pubspec.yaml` nem código-fonte próprio).

## Marco no Roadmap

- **Fase 7 — Nix Archive** ([`ROADMAP.md`](../../ROADMAP.md), [`docs/ARCHIVE.md`](../../docs/ARCHIVE.md) e [`docs/REPLICATION.md`](../../docs/REPLICATION.md)).

## Onde vive a implementação atual

- [`apps/nix_client/lib/core/archive/nix_archive_service.dart`](../../apps/nix_client/lib/core/archive/nix_archive_service.dart) — `NixArchiveService` (canonicalização determinística `nix.archive.article.v1` / `nix.archive.refutation.v1`, hash SHA-256, assinatura Ed25519, sanitização HTML e histórico `supersedes`).
- [`apps/nix_client/lib/core/database/repositories.dart`](../../apps/nix_client/lib/core/database/repositories.dart) — `ArchiveRepository` (persistência local no SQLCipher).
- [`apps/nix_client/lib/core/models/publication.dart`](../../apps/nix_client/lib/core/models/publication.dart) e [`apps/nix_client/lib/features/publications/publication_room_view.dart`](../../apps/nix_client/lib/features/publications/publication_room_view.dart) — modelos e interface de publicação e refutação no cliente.
