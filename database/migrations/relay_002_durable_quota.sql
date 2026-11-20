BEGIN;

-- Envelopes antigos não possuem vínculo recuperável com um token de cota.
ALTER TABLE nix.envelopes
  ADD COLUMN IF NOT EXISTS quota_token_hash bytea
  CHECK (octet_length(quota_token_hash) = 32);

CREATE INDEX IF NOT EXISTS envelopes_pending_quota
  ON nix.envelopes(quota_token_hash, expires_at) INCLUDE (byte_size)
  WHERE state = 'pending' AND quota_token_hash IS NOT NULL;

CREATE OR REPLACE FUNCTION nix.put_envelope_with_quota(
  p_box text, p_delivery uuid, p_cipher bytea, p_ttl integer,
  p_quota_hash bytea, p_quota_max bigint
)
RETURNS TABLE(envelope_id uuid, expires_at timestamptz, envelope_state text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,nix AS $$
DECLARE
  r nix.envelopes%ROWTYPE;
  t timestamptz;
  h bytea;
  used bigint;
BEGIN
  IF p_ttl IS NULL OR p_ttl < 1 OR p_ttl > 604800 OR
     p_cipher IS NULL OR octet_length(p_cipher) NOT BETWEEN 1 AND 1048576 OR
     (p_quota_hash IS NOT NULL AND
       (octet_length(p_quota_hash) <> 32 OR p_quota_max IS NULL OR p_quota_max <= 0)) THEN
    RAISE EXCEPTION 'invalid payload, TTL or quota';
  END IF;

  -- Usa a mesma ordem de locks da inserção original, ACK e expiração.
  PERFORM 1 FROM nix.storage_budget WHERE singleton = true FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'storage budget unavailable'; END IF;
  t := clock_timestamp();
  PERFORM 1 FROM nix.mailboxes WHERE id = p_box AND nix.mailboxes.expires_at > t FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mailbox unavailable'; END IF;

  h := public.digest(p_cipher, 'sha256');
  SELECT * INTO r FROM nix.envelopes WHERE mailbox_id = p_box AND delivery_id = p_delivery;
  IF FOUND THEN
    IF r.payload_hash <> h OR r.quota_token_hash IS DISTINCT FROM p_quota_hash THEN
      RAISE EXCEPTION 'idempotency conflict';
    END IF;
    RETURN QUERY SELECT r.id, r.expires_at, r.state;
    RETURN;
  END IF;

  IF p_quota_hash IS NOT NULL THEN
    SELECT coalesce(sum(byte_size), 0) INTO used
      FROM nix.envelopes
      WHERE quota_token_hash = p_quota_hash AND state = 'pending' AND nix.envelopes.expires_at > t;
    IF octet_length(p_cipher) > p_quota_max - used THEN
      RAISE EXCEPTION USING ERRCODE = 'NX001', MESSAGE = 'envelope quota exceeded';
    END IF;
  END IF;

  INSERT INTO nix.envelopes(mailbox_id, delivery_id, ciphertext, payload_hash,
      byte_size, created_at, expires_at, quota_token_hash)
    VALUES (p_box, p_delivery, p_cipher, h, octet_length(p_cipher),
      t, t + make_interval(secs => p_ttl), p_quota_hash)
    RETURNING * INTO r;
  RETURN QUERY SELECT r.id, r.expires_at, r.state;
END $$;

REVOKE ALL ON FUNCTION nix.put_envelope_with_quota(text,uuid,bytea,integer,bytea,bigint) FROM PUBLIC;

COMMIT;
