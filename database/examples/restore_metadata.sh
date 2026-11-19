#!/usr/bin/env bash
# PROPOSTO, NAO EXECUTADO. SOMENTE instancia nova ISOLADA, sem onion/relay.
# Banco nix vazio ja criado; confirmar snapshot antes de executar.
set -euo pipefail
: "${RESTIC_REPOSITORY:?}"
: "${RESTIC_PASSWORD_FILE:?}"
: "${NIX_RESTORE_SNAPSHOT:?ID explicito do snapshot a restaurar}"
restic dump "$NIX_RESTORE_SNAPSHOT" nix-metadata.dump \
 | docker compose exec -T -u postgres postgres pg_restore -U postgres -d nix --no-owner --no-privileges --exit-on-error
# Excluir dados envelope exige reconciliar contadores do snapshot anterior.
docker compose exec -T -u postgres postgres psql -v ON_ERROR_STOP=1 -d nix <<'SQL'
BEGIN;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM nix.envelopes) THEN RAISE EXCEPTION 'restore target unexpectedly contains envelopes'; END IF; END $$;
UPDATE nix.mailboxes SET used_bytes=0,pending_count=0;
UPDATE nix.storage_budget SET used_bytes=0;
DELETE FROM nix.capabilities WHERE expires_at<=clock_timestamp() OR revoked_at IS NOT NULL;
COMMIT;
SQL
# Nao libera rede: revisar revogacoes, rotacao, roles e migracoes antes.
