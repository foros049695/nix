-- PROPOSTO: aplicar uma vez, depois de 001, com runner de migracoes.
BEGIN;
CREATE INDEX capabilities_expiry ON nix.capabilities(expires_at);
CREATE INDEX mailboxes_expiry ON nix.mailboxes(expires_at);
INSERT INTO nix.schema_migrations(version,checksum) VALUES(2,'runner-must-record-actual-file-sha256');
COMMIT;
