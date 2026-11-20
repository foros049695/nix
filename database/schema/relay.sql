-- PROPOSTO. Requer PostgreSQL 17+ e pgcrypto. Nao integrado ao relay atual.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA nix;
CREATE TABLE nix.schema_migrations(version integer PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT clock_timestamp(), checksum text NOT NULL);
CREATE TABLE nix.storage_budget(singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton), used_bytes bigint NOT NULL DEFAULT 0 CHECK(used_bytes>=0), max_bytes bigint NOT NULL CHECK(max_bytes>0 AND used_bytes<=max_bytes));
INSERT INTO nix.storage_budget(singleton,max_bytes) VALUES(true,10737418240);
CREATE TABLE nix.mailboxes(id text PRIMARY KEY CHECK(id ~ '^[a-f0-9]{64}$'), created_at timestamptz NOT NULL DEFAULT clock_timestamp(), expires_at timestamptz NOT NULL, used_bytes bigint NOT NULL DEFAULT 0 CHECK(used_bytes>=0), quota_bytes bigint NOT NULL DEFAULT 524288000 CHECK(quota_bytes>0 AND used_bytes<=quota_bytes), max_envelopes integer NOT NULL DEFAULT 10000 CHECK(max_envelopes>0), pending_count integer NOT NULL DEFAULT 0 CHECK(pending_count>=0 AND pending_count<=max_envelopes), CHECK(expires_at>created_at));
CREATE TABLE nix.capabilities(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), mailbox_id text NOT NULL REFERENCES nix.mailboxes(id) ON DELETE CASCADE, scope text NOT NULL CHECK(scope IN ('read_ack','write','admin')), token_hash bytea NOT NULL UNIQUE CHECK(octet_length(token_hash)=32), expires_at timestamptz NOT NULL, revoked_at timestamptz);
CREATE INDEX capabilities_mailbox ON nix.capabilities(mailbox_id,scope);
CREATE TABLE nix.envelopes(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), mailbox_id text NOT NULL REFERENCES nix.mailboxes(id), delivery_id uuid NOT NULL, protocol_version integer NOT NULL DEFAULT 1 CHECK(protocol_version=1), ciphertext bytea, payload_hash bytea NOT NULL CHECK(octet_length(payload_hash)=32), byte_size integer NOT NULL CHECK(byte_size>0 AND byte_size<=1048576), created_at timestamptz NOT NULL DEFAULT clock_timestamp(), expires_at timestamptz NOT NULL, state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','acked')), acked_at timestamptz, UNIQUE(mailbox_id,delivery_id), CHECK(expires_at>created_at AND expires_at<=created_at+interval '7 days'), CHECK((state='pending' AND ciphertext IS NOT NULL AND octet_length(ciphertext)=byte_size AND acked_at IS NULL) OR (state='acked' AND ciphertext IS NULL AND acked_at IS NOT NULL)));
CREATE INDEX envelopes_pending_page ON nix.envelopes(mailbox_id,created_at,id) WHERE state='pending';
CREATE INDEX envelopes_expiry ON nix.envelopes(expires_at,id);
CREATE TABLE nix.maintenance_state(name text PRIMARY KEY, last_success_at timestamptz, last_error_code text);
-- Um lock global serializa contabilizacao. MVP deliberado; benchmark decide particionamento.
CREATE FUNCTION nix.account_envelope() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,nix AS $$
DECLARE delta_bytes bigint:=0; delta_count integer:=0; box text;
BEGIN
 IF TG_OP='INSERT' THEN box:=NEW.mailbox_id; IF NEW.state='pending' THEN delta_bytes:=NEW.byte_size;delta_count:=1; END IF;
 ELSIF TG_OP='DELETE' THEN box:=OLD.mailbox_id; IF OLD.state='pending' THEN delta_bytes:=-OLD.byte_size;delta_count:=-1; END IF;
 ELSE
  IF NEW.mailbox_id<>OLD.mailbox_id OR NEW.byte_size<>OLD.byte_size OR NEW.expires_at<>OLD.expires_at OR NEW.delivery_id<>OLD.delivery_id OR NEW.payload_hash<>OLD.payload_hash THEN RAISE EXCEPTION 'immutable envelope metadata'; END IF;
  IF OLD.state<>'pending' OR NEW.state<>'acked' THEN RAISE EXCEPTION 'only pending to acked transition allowed'; END IF;
  box:=OLD.mailbox_id;delta_bytes:=-OLD.byte_size;delta_count:=-1;
 END IF;
 UPDATE nix.storage_budget SET used_bytes=used_bytes+delta_bytes WHERE singleton=true;
 UPDATE nix.mailboxes SET used_bytes=used_bytes+delta_bytes,pending_count=pending_count+delta_count WHERE id=box;
 IF NOT FOUND THEN RAISE EXCEPTION 'unknown mailbox'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;
CREATE TRIGGER envelope_account BEFORE INSERT OR UPDATE OR DELETE ON nix.envelopes FOR EACH ROW EXECUTE FUNCTION nix.account_envelope();
CREATE FUNCTION nix.put_envelope(p_box text,p_delivery uuid,p_cipher bytea,p_ttl integer DEFAULT 604800)
RETURNS TABLE(envelope_id uuid,expires_at timestamptz,envelope_state text) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,nix AS $$
DECLARE r nix.envelopes%ROWTYPE; t timestamptz:=clock_timestamp(); h bytea;
BEGIN
 IF p_ttl IS NULL OR p_ttl<1 OR p_ttl>604800 OR p_cipher IS NULL OR octet_length(p_cipher)<1 OR octet_length(p_cipher)>1048576 THEN RAISE EXCEPTION 'invalid payload or TTL'; END IF;
 h:=public.digest(p_cipher,'sha256');
 -- Lock global antes da mailbox: mesma ordem usada pelo trigger.
 PERFORM 1 FROM nix.storage_budget WHERE singleton=true FOR UPDATE;
 PERFORM 1 FROM nix.mailboxes WHERE id=p_box AND nix.mailboxes.expires_at>t FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'mailbox unavailable'; END IF;
 SELECT * INTO r FROM nix.envelopes WHERE mailbox_id=p_box AND delivery_id=p_delivery;
 IF FOUND THEN
  IF r.payload_hash<>h THEN RAISE EXCEPTION 'idempotency conflict'; END IF;
  RETURN QUERY SELECT r.id,r.expires_at,r.state; RETURN;
 END IF;
 INSERT INTO nix.envelopes(mailbox_id,delivery_id,ciphertext,payload_hash,byte_size,created_at,expires_at) VALUES(p_box,p_delivery,p_cipher,h,octet_length(p_cipher),t,t+make_interval(secs=>p_ttl)) RETURNING * INTO r;
 RETURN QUERY SELECT r.id,r.expires_at,r.state;
END $$;
CREATE FUNCTION nix.ack_envelopes(p_box text,p_ids uuid[]) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,nix AS $$
DECLARE n integer;
BEGIN
 IF p_ids IS NULL OR cardinality(p_ids)>100 THEN RAISE EXCEPTION 'invalid ACK batch'; END IF;
 PERFORM 1 FROM nix.storage_budget WHERE singleton=true FOR UPDATE;
 UPDATE nix.envelopes SET state='acked',ciphertext=NULL,acked_at=clock_timestamp() WHERE mailbox_id=p_box AND id=ANY(p_ids) AND state='pending';
 GET DIAGNOSTICS n=ROW_COUNT; RETURN n;
END $$;
CREATE FUNCTION nix.sweep_expired(p_limit integer DEFAULT 500) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,nix AS $$
DECLARE n integer;
BEGIN
 IF p_limit<1 OR p_limit>5000 THEN RAISE EXCEPTION 'invalid GC limit'; END IF;
 PERFORM 1 FROM nix.storage_budget WHERE singleton=true FOR UPDATE;
 WITH doomed AS (SELECT id FROM nix.envelopes WHERE expires_at<=clock_timestamp() ORDER BY expires_at,id LIMIT p_limit FOR UPDATE SKIP LOCKED)
 DELETE FROM nix.envelopes e USING doomed d WHERE e.id=d.id;
 GET DIAGNOSTICS n=ROW_COUNT; RETURN n;
END $$;
REVOKE ALL ON FUNCTION nix.put_envelope(text,uuid,bytea,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION nix.ack_envelopes(text,uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION nix.sweep_expired(integer) FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA nix FROM PUBLIC;
COMMIT;
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
