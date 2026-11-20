package buffer

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/lib/pq"
)

var hexMailbox64Regex = regexp.MustCompile(`^[a-f0-9]{64}$`)

// PostgresMailboxStore integra o Nix Relay ao PostgreSQL 17+ usando o schema formal `nix.*`
// (`mailboxes`, `capabilities`, `envelopes`, `storage_budget`, `put_envelope`, `ack_envelopes`, `sweep_expired`).
type PostgresMailboxStore struct {
	db                       *sql.DB
	baseTTL                  time.Duration
	maxAttachmentBytes       int64
	maxInFlightPerQuotaToken int64
	mu                       sync.RWMutex
	quotaUsage               map[string]int64
	totalStored              atomic.Int64
	totalAcked               atomic.Int64
	totalPruned              atomic.Int64
}

const postgresSchemaBootstrapSQL = `
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS nix;
CREATE TABLE IF NOT EXISTS nix.schema_migrations(version integer PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT clock_timestamp(), checksum text NOT NULL);
CREATE TABLE IF NOT EXISTS nix.storage_budget(singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton), used_bytes bigint NOT NULL DEFAULT 0 CHECK(used_bytes>=0), max_bytes bigint NOT NULL CHECK(max_bytes>0 AND used_bytes<=max_bytes));
INSERT INTO nix.storage_budget(singleton,max_bytes) VALUES(true,10737418240) ON CONFLICT (singleton) DO NOTHING;
CREATE TABLE IF NOT EXISTS nix.mailboxes(id text PRIMARY KEY CHECK(id ~ '^[a-f0-9]{64}$'), created_at timestamptz NOT NULL DEFAULT clock_timestamp(), expires_at timestamptz NOT NULL, used_bytes bigint NOT NULL DEFAULT 0 CHECK(used_bytes>=0), quota_bytes bigint NOT NULL DEFAULT 524288000 CHECK(quota_bytes>0 AND used_bytes<=quota_bytes), max_envelopes integer NOT NULL DEFAULT 10000 CHECK(max_envelopes>0), pending_count integer NOT NULL DEFAULT 0 CHECK(pending_count>=0 AND pending_count<=max_envelopes), CHECK(expires_at>created_at));
CREATE TABLE IF NOT EXISTS nix.capabilities(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), mailbox_id text NOT NULL REFERENCES nix.mailboxes(id) ON DELETE CASCADE, scope text NOT NULL CHECK(scope IN ('read_ack','write','admin')), token_hash bytea NOT NULL UNIQUE CHECK(octet_length(token_hash)=32), expires_at timestamptz NOT NULL, revoked_at timestamptz);
CREATE INDEX IF NOT EXISTS capabilities_mailbox ON nix.capabilities(mailbox_id,scope);
CREATE INDEX IF NOT EXISTS capabilities_expiry ON nix.capabilities(expires_at);
CREATE INDEX IF NOT EXISTS mailboxes_expiry ON nix.mailboxes(expires_at);
CREATE TABLE IF NOT EXISTS nix.envelopes(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), mailbox_id text NOT NULL REFERENCES nix.mailboxes(id), delivery_id uuid NOT NULL, protocol_version integer NOT NULL DEFAULT 1 CHECK(protocol_version=1), ciphertext bytea, payload_hash bytea NOT NULL CHECK(octet_length(payload_hash)=32), byte_size integer NOT NULL CHECK(byte_size>0 AND byte_size<=1048576), created_at timestamptz NOT NULL DEFAULT clock_timestamp(), expires_at timestamptz NOT NULL, state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','acked')), acked_at timestamptz, UNIQUE(mailbox_id,delivery_id), CHECK(expires_at>created_at AND expires_at<=created_at+interval '7 days'), CHECK((state='pending' AND ciphertext IS NOT NULL AND octet_length(ciphertext)=byte_size AND acked_at IS NULL) OR (state='acked' AND ciphertext IS NULL AND acked_at IS NOT NULL)));
CREATE INDEX IF NOT EXISTS envelopes_pending_page ON nix.envelopes(mailbox_id,created_at,id) WHERE state='pending';
CREATE INDEX IF NOT EXISTS envelopes_expiry ON nix.envelopes(expires_at,id);
CREATE TABLE IF NOT EXISTS nix.maintenance_state(name text PRIMARY KEY, last_success_at timestamptz, last_error_code text);
CREATE OR REPLACE FUNCTION nix.account_envelope() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,nix AS $$
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
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='envelope_account') THEN
  CREATE TRIGGER envelope_account BEFORE INSERT OR UPDATE OR DELETE ON nix.envelopes FOR EACH ROW EXECUTE FUNCTION nix.account_envelope();
 END IF;
END $$;
CREATE OR REPLACE FUNCTION nix.put_envelope(p_box text,p_delivery uuid,p_cipher bytea,p_ttl integer DEFAULT 604800)
RETURNS TABLE(envelope_id uuid,expires_at timestamptz,envelope_state text) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,nix AS $$
DECLARE r nix.envelopes%ROWTYPE; t timestamptz:=clock_timestamp(); h bytea;
BEGIN
 IF p_ttl IS NULL OR p_ttl<1 OR p_ttl>604800 OR p_cipher IS NULL OR octet_length(p_cipher)<1 OR octet_length(p_cipher)>1048576 THEN RAISE EXCEPTION 'invalid payload or TTL'; END IF;
 h:=public.digest(p_cipher,'sha256');
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
CREATE OR REPLACE FUNCTION nix.ack_envelopes(p_box text,p_ids uuid[]) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,nix AS $$
DECLARE n integer;
BEGIN
 IF p_ids IS NULL OR cardinality(p_ids)>100 THEN RAISE EXCEPTION 'invalid ACK batch'; END IF;
 PERFORM 1 FROM nix.storage_budget WHERE singleton=true FOR UPDATE;
 UPDATE nix.envelopes SET state='acked',ciphertext=NULL,acked_at=clock_timestamp() WHERE mailbox_id=p_box AND id=ANY(p_ids) AND state='pending';
 GET DIAGNOSTICS n=ROW_COUNT; RETURN n;
END $$;
CREATE OR REPLACE FUNCTION nix.sweep_expired(p_limit integer DEFAULT 500) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,nix AS $$
DECLARE n integer;
BEGIN
 IF p_limit<1 OR p_limit>5000 THEN RAISE EXCEPTION 'invalid GC limit'; END IF;
 PERFORM 1 FROM nix.storage_budget WHERE singleton=true FOR UPDATE;
 WITH doomed AS (SELECT id FROM nix.envelopes WHERE expires_at<=clock_timestamp() ORDER BY expires_at,id LIMIT p_limit FOR UPDATE SKIP LOCKED)
 DELETE FROM nix.envelopes e USING doomed d WHERE e.id=d.id;
 GET DIAGNOSTICS n=ROW_COUNT; RETURN n;
END $$;
`

// NewPostgresMailboxStore abre pool PostgreSQL 17+ com parâmetros conservadores e opcionalmente garante o schema.
func NewPostgresMailboxStore(ctx context.Context, dsn string, baseTTL time.Duration, maxAttachmentBytes, maxInFlightPerQuotaToken int64, initSchema bool) (*PostgresMailboxStore, error) {
	if baseTTL <= 0 {
		baseTTL = 7 * 24 * time.Hour
	}
	if maxAttachmentBytes <= 0 || maxAttachmentBytes > 1048576 {
		// Schema PostgreSQL 001 limita cada envelope direto em 1 MiB (anexos maiores vão em chunks E2EE)
		maxAttachmentBytes = 1048576
	}
	if maxInFlightPerQuotaToken <= 0 {
		maxInFlightPerQuotaToken = 524288000
	}
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(32)
	db.SetMaxIdleConns(8)
	db.SetConnMaxLifetime(30 * time.Minute)

	pingCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err := db.PingContext(pingCtx); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("%w: %v", ErrPersistence, err)
	}

	if initSchema {
		if _, err := db.ExecContext(ctx, postgresSchemaBootstrapSQL); err != nil {
			_ = db.Close()
			return nil, fmt.Errorf("%w: schema init: %v", ErrPersistence, err)
		}
	}

	return &PostgresMailboxStore{
		db:                       db,
		baseTTL:                  baseTTL,
		maxAttachmentBytes:       maxAttachmentBytes,
		maxInFlightPerQuotaToken: maxInFlightPerQuotaToken,
		quotaUsage:               make(map[string]int64),
	}, nil
}

func (s *PostgresMailboxStore) Close() error {
	return s.db.Close()
}

// canonicalMailboxHex aceita ID já cego em 64-hex diretamente ou faz hash SHA-256 determinístico para compatibilidade.
func canonicalMailboxHex(mailboxID string) string {
	lower := strings.ToLower(strings.TrimSpace(mailboxID))
	if hexMailbox64Regex.MatchString(lower) {
		return lower
	}
	sum := sha256.Sum256([]byte(mailboxID))
	return hex.EncodeToString(sum[:])
}

func newRandomUUIDv4() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",
		b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

func (s *PostgresMailboxStore) ensureMailbox(ctx context.Context, boxHex string) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO nix.mailboxes(id, expires_at) VALUES($1, clock_timestamp() + interval '30 days')
		 ON CONFLICT (id) DO UPDATE SET expires_at = GREATEST(nix.mailboxes.expires_at, clock_timestamp() + interval '7 days')`,
		boxHex,
	)
	return err
}

func (s *PostgresMailboxStore) Store(
	mailboxID string,
	payloadB64 string,
	requestedTTLSeconds int64,
	quotaToken string,
	prunerState string,
	now time.Time,
) (Envelope, error) {
	if !validMailboxRegex.MatchString(mailboxID) && !hexMailbox64Regex.MatchString(strings.ToLower(mailboxID)) {
		return Envelope{}, ErrInvalidMailbox
	}
	raw, err := base64.StdEncoding.DecodeString(payloadB64)
	if err != nil || len(raw) == 0 {
		return Envelope{}, errors.New("payload_b64 inválido ou vazio")
	}
	byteSize := int64(len(raw))
	if byteSize > s.maxAttachmentBytes {
		return Envelope{}, ErrPayloadTooLarge
	}
	if prunerState == StateSevereRelief && byteSize > 10*1024*1024 {
		return Envelope{}, ErrPayloadTooLarge
	}
	if prunerState == StateCriticalBlock && byteSize > 1*1024*1024 {
		return Envelope{}, ErrCriticalPressure
	}
	if quotaToken != "" {
		s.mu.Lock()
		if s.quotaUsage[quotaToken]+byteSize > s.maxInFlightPerQuotaToken {
			s.mu.Unlock()
			return Envelope{}, ErrQuotaExceeded
		}
		s.quotaUsage[quotaToken] += byteSize
		s.mu.Unlock()
	}

	effTTL := int64(MaxTTLForState(prunerState, s.baseTTL).Seconds())
	if requestedTTLSeconds > 0 && requestedTTLSeconds < effTTL {
		effTTL = requestedTTLSeconds
	}
	if effTTL < 1 {
		effTTL = 1
	}

	boxHex := canonicalMailboxHex(mailboxID)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := s.ensureMailbox(ctx, boxHex); err != nil {
		if quotaToken != "" {
			s.mu.Lock()
			s.quotaUsage[quotaToken] -= byteSize
			s.mu.Unlock()
		}
		return Envelope{}, fmt.Errorf("%w: %v", ErrPersistence, err)
	}

	deliveryUUID := newRandomUUIDv4()
	var envID string
	var expiresAt time.Time
	var state string
	err = s.db.QueryRowContext(
		ctx,
		`SELECT envelope_id::text, expires_at, envelope_state FROM nix.put_envelope($1, $2::uuid, $3, $4)`,
		boxHex, deliveryUUID, raw, effTTL,
	).Scan(&envID, &expiresAt, &state)
	if err != nil {
		if quotaToken != "" {
			s.mu.Lock()
			s.quotaUsage[quotaToken] -= byteSize
			s.mu.Unlock()
		}
		return Envelope{}, fmt.Errorf("%w: %v", ErrPersistence, err)
	}

	s.totalStored.Add(1)
	return Envelope{
		ID:         envID,
		PayloadB64: payloadB64,
		CreatedAt:  now.UTC().Unix(),
		ExpiresAt:  expiresAt.UTC().Unix(),
		ByteSize:   byteSize,
		QuotaToken: quotaToken,
	}, nil
}

func (s *PostgresMailboxStore) Fetch(mailboxID string, now time.Time) ([]Envelope, error) {
	boxHex := canonicalMailboxHex(mailboxID)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	rows, err := s.db.QueryContext(
		ctx,
		`SELECT id::text, ciphertext, EXTRACT(EPOCH FROM created_at)::bigint, EXTRACT(EPOCH FROM expires_at)::bigint, byte_size
		 FROM nix.envelopes
		 WHERE mailbox_id = $1 AND state = 'pending' AND expires_at > clock_timestamp()
		 ORDER BY created_at ASC, id ASC LIMIT 500`,
		boxHex,
	)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrPersistence, err)
	}
	defer rows.Close()

	var result []Envelope
	for rows.Next() {
		var id string
		var cipher []byte
		var createdAt, expiresAt, byteSize int64
		if err := rows.Scan(&id, &cipher, &createdAt, &expiresAt, &byteSize); err != nil {
			return nil, fmt.Errorf("%w: %v", ErrPersistence, err)
		}
		result = append(result, Envelope{
			ID:         id,
			PayloadB64: base64.StdEncoding.EncodeToString(cipher),
			CreatedAt:  createdAt,
			ExpiresAt:  expiresAt,
			ByteSize:   byteSize,
		})
	}
	return result, rows.Err()
}

func (s *PostgresMailboxStore) Ack(mailboxID string, ids []string) (int, error) {
	if len(ids) == 0 {
		return 0, nil
	}
	boxHex := canonicalMailboxHex(mailboxID)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var deleted int
	err := s.db.QueryRowContext(
		ctx,
		`SELECT nix.ack_envelopes($1, $2::uuid[])`,
		boxHex, pq.Array(ids),
	).Scan(&deleted)
	if err != nil {
		return 0, fmt.Errorf("%w: %v", ErrPersistence, err)
	}
	s.totalAcked.Add(int64(deleted))
	return deleted, nil
}

func (s *PostgresMailboxStore) SweepExpired(now time.Time, maxAgeCap time.Duration) (int, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var swept int
	err := s.db.QueryRowContext(ctx, `SELECT nix.sweep_expired(5000)`).Scan(&swept)
	if err != nil {
		return 0, fmt.Errorf("%w: %v", ErrPersistence, err)
	}
	s.totalPruned.Add(int64(swept))
	return swept, nil
}

func hashTokenBytes(token string) []byte {
	sum := sha256.Sum256([]byte(token))
	return sum[:]
}

func (s *PostgresMailboxStore) ProvisionCapability(mailboxID, token string, scope CapabilityScope, ttl time.Duration) error {
	if mailboxID == "" || token == "" {
		return ErrInvalidMailbox
	}
	if ttl <= 0 {
		ttl = 30 * 24 * time.Hour
	}
	boxHex := canonicalMailboxHex(mailboxID)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := s.ensureMailbox(ctx, boxHex); err != nil {
		return fmt.Errorf("%w: %v", ErrPersistence, err)
	}
	_, err := s.db.ExecContext(
		ctx,
		`INSERT INTO nix.capabilities(mailbox_id, scope, token_hash, expires_at)
		 VALUES($1, $2, $3, clock_timestamp() + ($4 || ' seconds')::interval)
		 ON CONFLICT (token_hash) DO UPDATE SET scope = EXCLUDED.scope, expires_at = EXCLUDED.expires_at, revoked_at = NULL`,
		boxHex, string(scope), hashTokenBytes(token), int64(ttl.Seconds()),
	)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrPersistence, err)
	}
	return nil
}

func (s *PostgresMailboxStore) RevokeCapability(mailboxID, token string) error {
	if mailboxID == "" || token == "" {
		return nil
	}
	boxHex := canonicalMailboxHex(mailboxID)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := s.db.ExecContext(
		ctx,
		`UPDATE nix.capabilities SET revoked_at = clock_timestamp() WHERE mailbox_id = $1 AND token_hash = $2`,
		boxHex, hashTokenBytes(token),
	)
	return err
}

func (s *PostgresMailboxStore) HasExplicitScope(mailboxID string, scope CapabilityScope) bool {
	boxHex := canonicalMailboxHex(mailboxID)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	var exists bool
	_ = s.db.QueryRowContext(
		ctx,
		`SELECT EXISTS(SELECT 1 FROM nix.capabilities WHERE mailbox_id = $1 AND scope = $2 AND revoked_at IS NULL AND expires_at > clock_timestamp())`,
		boxHex, string(scope),
	).Scan(&exists)
	return exists
}

func (s *PostgresMailboxStore) ValidateCapability(mailboxID, token string, scope CapabilityScope) bool {
	if mailboxID == "" || token == "" || legacyReadToken.MatchString(token) {
		return false
	}
	boxHex := canonicalMailboxHex(mailboxID)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	var count int
	err := s.db.QueryRowContext(
		ctx,
		`SELECT count(*) FROM nix.capabilities
		 WHERE mailbox_id = $1 AND token_hash = $2 AND revoked_at IS NULL
		   AND expires_at > clock_timestamp() AND (scope = $3 OR scope = 'admin')`,
		boxHex, hashTokenBytes(token), string(scope),
	).Scan(&count)
	return err == nil && count > 0
}

func (s *PostgresMailboxStore) Metrics() StoreMetrics {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	var activeBoxes int
	var activeEnv int
	var storedBytes int64
	_ = s.db.QueryRowContext(ctx, `SELECT count(*) FROM nix.mailboxes WHERE expires_at > clock_timestamp()`).Scan(&activeBoxes)
	_ = s.db.QueryRowContext(ctx, `SELECT count(*), coalesce(sum(byte_size), 0) FROM nix.envelopes WHERE state = 'pending'`).Scan(&activeEnv, &storedBytes)

	return StoreMetrics{
		ActiveMailboxes: activeBoxes,
		ActiveEnvelopes: activeEnv,
		StoredBytes:     storedBytes,
		TotalStored:     s.totalStored.Load(),
		TotalAcked:      s.totalAcked.Load(),
		TotalPruned:     s.totalPruned.Load(),
	}
}
