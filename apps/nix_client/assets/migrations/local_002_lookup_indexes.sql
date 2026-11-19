-- PROPOSTO: aplicar uma vez, depois de 001. Runner verifica user_version=1.
BEGIN;
CREATE INDEX attachments_object ON attachments(object_id);
CREATE INDEX library_media ON library_entries(media_id);
CREATE INDEX members_device ON members(device_id);
CREATE INDEX skipped_expiry ON skipped_keys(expires_at);
CREATE INDEX inbox_expiry ON inbox_dedup(expires_at);
CREATE INDEX replay_expiry ON replay_nonces(expires_at);
PRAGMA user_version = 2;
COMMIT;
