# Módulo `offgrid` (Placeholder)

> **Estado atual:** este diretório é apenas um *placeholder* estrutural — **não é um pacote Dart/Flutter ou Go compilável** (não possui `pubspec.yaml` nem código-fonte próprio).

## Marco no Roadmap

- **Fase 5 — Comunicação Off-Grid** ([`ROADMAP.md`](../../ROADMAP.md) e [`docs/OFFGRID.md`](../../docs/OFFGRID.md)).

## Onde vive a implementação atual

- [`modules/transport/lib/nix_offgrid_radio.dart`](../transport/lib/nix_offgrid_radio.dart) — `RadioPacketCodec` (pacotes compactos `<= 240` bytes sem mídia), `DutyCycleGovernor` e `AtakCotBridge`.
- [`modules/transport/lib/nix_bluetooth_mesh.dart`](../transport/lib/nix_bluetooth_mesh.dart) — módulo experimental de transporte Bluetooth Mesh no pacote `nix_transport`.
- [`apps/nix_client/lib/core/offgrid/mbtiles_reader.dart`](../../apps/nix_client/lib/core/offgrid/mbtiles_reader.dart) — `MbtilesMapReader` (leitura offline de mapas `.mbtiles` em SQLite somente-leitura).
- [`apps/nix_client/lib/features/offline/share_app_offline_dialog.dart`](../../apps/nix_client/lib/features/offline/share_app_offline_dialog.dart) — diálogo de compartilhamento local de instalador verificado por manifesto assinado (`SignedReleaseManifest`).
