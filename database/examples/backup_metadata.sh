#!/usr/bin/env bash
# PROPOSTO, NAO EXECUTADO. Rodar no diretorio do compose; env restic fora do repo.
set -euo pipefail
: "${RESTIC_REPOSITORY:?Defina repositorio restic externo}"
: "${RESTIC_PASSWORD_FILE:?Defina arquivo de senha fora do repositorio}"
# Compose exec usa socket local; operador de backup e privilegiado.
# Exclui payloads e tombstones; contadores sao zerados no restore.
docker compose exec -T -u postgres postgres pg_dump -U postgres -d nix -Fc \
  --exclude-table-data=nix.envelopes \
  | restic backup --stdin --stdin-filename nix-metadata.dump --tag nix-metadata
# Retencao proposta de metadados; nunca usar este script para payload sem revisao.
restic forget --tag nix-metadata --keep-daily 7 --prune
restic check
