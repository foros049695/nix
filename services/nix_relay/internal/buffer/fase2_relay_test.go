package buffer

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestDurableCapabilitiesScopesExpirationAndRevocation(t *testing.T) {
	dir := t.TempDir()
	s, err := NewBlindMailboxStore(dir, 24*time.Hour, 1024*1024, 10*1024*1024)
	if err != nil {
		t.Fatal(err)
	}

	// Provisiona token de escrita e token de leitura/ack distintos
	if err := s.ProvisionCapability("mbox_cap_1", "tok-write-only", ScopeWrite, time.Hour); err != nil {
		t.Fatal(err)
	}
	if err := s.ProvisionCapability("mbox_cap_1", "tok-read-only", ScopeReadAck, time.Hour); err != nil {
		t.Fatal(err)
	}

	if !s.ValidateCapability("mbox_cap_1", "tok-write-only", ScopeWrite) {
		t.Fatal("token de escrita deveria validar ScopeWrite")
	}
	if s.ValidateCapability("mbox_cap_1", "tok-write-only", ScopeReadAck) {
		t.Fatal("token de escrita NÃO deve validar ScopeReadAck")
	}
	if s.ValidateCapability("mbox_cap_1", "tok-read-only", ScopeWrite) {
		t.Fatal("token de leitura NÃO deve validar ScopeWrite")
	}
	if !s.ValidateCapability("mbox_cap_1", "tok-read-only", ScopeReadAck) {
		t.Fatal("token de leitura deveria validar ScopeReadAck")
	}

	// Token com hash em claro NÃO deve vazar no arquivo em disco
	rawCapFile, err := os.ReadFile(s.capabilitiesPath())
	if err != nil {
		t.Fatal(err)
	}
	if string(rawCapFile) == "" || (containsString(string(rawCapFile), "tok-write-only") || containsString(string(rawCapFile), "tok-read-only")) {
		t.Fatal("segredo em claro encontrado no arquivo .capabilities.json")
	}

	// Simula reinicialização fria e verifica persistência das capabilities
	s2, err := NewBlindMailboxStore(dir, 24*time.Hour, 1024*1024, 10*1024*1024)
	if err != nil {
		t.Fatal(err)
	}
	if !s2.ValidateCapability("mbox_cap_1", "tok-read-only", ScopeReadAck) {
		t.Fatal("capability read_ack não sobreviveu à reinicialização")
	}

	// Revogação deve persistir após reinicialização
	if err := s2.RevokeCapability("mbox_cap_1", "tok-read-only"); err != nil {
		t.Fatal(err)
	}
	s3, err := NewBlindMailboxStore(dir, 24*time.Hour, 1024*1024, 10*1024*1024)
	if err != nil {
		t.Fatal(err)
	}
	if s3.ValidateCapability("mbox_cap_1", "tok-read-only", ScopeReadAck) {
		t.Fatal("capability revogada continuou aceita após reinicialização")
	}
}

func TestAdminListenAddrLoopbackValidation(t *testing.T) {
	for _, valid := range []string{"127.0.0.1:9090", "localhost:9091", "[::1]:9092"} {
		if err := ValidateAdminListenAddr(valid); err != nil {
			t.Errorf("endereço loopback válido rejeitado (%s): %v", valid, err)
		}
	}
	for _, unsafe := range []string{"0.0.0.0:9090", "[::]:9090", "192.168.1.10:9090", "badformat"} {
		if err := ValidateAdminListenAddr(unsafe); err == nil {
			t.Errorf("endereço administrativo não-loopback deveria ser bloqueado: %s", unsafe)
		}
	}
}

func TestPostgresMailboxStoreConcurrencyPersistenceAndGC(t *testing.T) {
	dsn := os.Getenv("NIX_TEST_PG_DSN")
	if dsn == "" {
		t.Skip("NIX_TEST_PG_DSN não definido; ignorando teste vivo PostgreSQL 17 neste job.")
	}

	ctx := context.Background()
	store, err := NewPostgresMailboxStore(ctx, dsn, 24*time.Hour, 1024*1024, 50*1024*1024, true)
	if err != nil {
		t.Fatalf("falha ao iniciar PostgresMailboxStore: %v", err)
	}
	defer store.Close()

	boxID := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	_ = store.ProvisionCapability(boxID, "pg-write-tok", ScopeWrite, time.Hour)
	_ = store.ProvisionCapability(boxID, "pg-read-tok", ScopeReadAck, time.Hour)

	if !store.ValidateCapability(boxID, "pg-write-tok", ScopeWrite) {
		t.Fatal("pg write capability failed")
	}
	if store.ValidateCapability(boxID, "pg-write-tok", ScopeReadAck) {
		t.Fatal("pg write capability should not allow read_ack")
	}
	if !store.ValidateCapability(boxID, "pg-read-tok", ScopeReadAck) {
		t.Fatal("pg read capability failed")
	}

	// Teste de concorrência real com lock + trigger storage_budget no PostgreSQL 17
	const workers = 12
	var wg sync.WaitGroup
	errCh := make(chan error, workers)
	payload := base64.StdEncoding.EncodeToString([]byte("pg17-cipher-blob-ok"))
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			_, err := store.Store(boxID, payload, 120, fmt.Sprintf("q-%d", idx), StateNormal, time.Now().UTC())
			if err != nil {
				errCh <- err
			}
		}(i)
	}
	wg.Wait()
	close(errCh)
	for e := range errCh {
		t.Fatalf("erro concorrente no PostgreSQL: %v", e)
	}

	// Reabre segunda instância simulando restart do processo relay
	store2, err := NewPostgresMailboxStore(ctx, dsn, 24*time.Hour, 1024*1024, 50*1024*1024, false)
	if err != nil {
		t.Fatal(err)
	}
	defer store2.Close()

	envs, err := store2.Fetch(boxID, time.Now().UTC())
	if err != nil {
		t.Fatal(err)
	}
	if len(envs) != workers {
		t.Fatalf("esperado %d envelopes após reinicialização, got %d", workers, len(envs))
	}

	ids := make([]string, 0, len(envs))
	for _, e := range envs {
		ids = append(ids, e.ID)
	}
	acked, err := store2.Ack(boxID, ids)
	if err != nil || acked != workers {
		t.Fatalf("expected ack=%d, got=%d err=%v", workers, acked, err)
	}

	// Envelope com TTL de 1 segundo deve ser removido pelo SweepExpired
	_, err = store2.Store(boxID, payload, 1, "q-exp", StateNormal, time.Now().UTC())
	if err != nil {
		t.Fatal(err)
	}
	time.Sleep(1500 * time.Millisecond)
	swept, err := store2.SweepExpired(time.Now().UTC(), 24*time.Hour)
	if err != nil || swept < 1 {
		t.Fatalf("esperado >= 1 envelope expirado removido, got=%d err=%v", swept, err)
	}
}

func containsString(haystack, needle string) bool {
	return len(needle) > 0 && len(haystack) >= len(needle) && (func() bool {
		for i := 0; i <= len(haystack)-len(needle); i++ {
			if haystack[i:i+len(needle)] == needle {
				return true
			}
		}
		return false
	})()
}

func TestWritePolicySurvivesRevocationAndRestart(t *testing.T) {
	dir := t.TempDir()
	open := func() (*BlindMailboxStore, error) {
		return NewBlindMailboxStore(dir, time.Hour, 1024, 1024)
	}
	store, err := open()
	if err != nil {
		t.Fatal(err)
	}
	if err := store.ProvisionCapability("restricted", "test-writer", ScopeWrite, time.Hour); err != nil {
		t.Fatal(err)
	}
	if err := store.ProvisionCapability("restricted", "test-writer", ScopeReadAck, time.Hour); err == nil {
		t.Fatal("o mesmo token não pode sobrescrever a política com outro escopo")
	}
	if err := store.RevokeCapability("restricted", "test-writer"); err != nil {
		t.Fatal(err)
	}
	for _, reopen := range []bool{false, true} {
		if reopen {
			store, err = open()
			if err != nil {
				t.Fatal(err)
			}
		}
		if !store.HasExplicitScope("restricted", ScopeWrite) ||
			store.ValidateCapability("restricted", "test-writer", ScopeWrite) {
			t.Fatal("a escrita continua protegida, com a credencial revogada")
		}
	}
	if err := os.WriteFile(store.capabilitiesPath(), []byte("{"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := open(); err == nil {
		t.Fatal("registro de capabilities inválido deve impedir a abertura")
	}
}

func TestCapabilityPersistenceRollsBack(t *testing.T) {
	store, err := NewBlindMailboxStore(t.TempDir(), time.Hour, 1024, 1024)
	if err != nil {
		t.Fatal(err)
	}
	if err := store.ProvisionCapability("restricted", "test-original", ScopeWrite, time.Hour); err != nil {
		t.Fatal(err)
	}
	// Bloqueia a gravação no arquivo temporário com um diretório.
	if err := os.Mkdir(store.capabilitiesPath()+".tmp", 0700); err != nil {
		t.Fatal(err)
	}
	if err := store.ProvisionCapability("restricted", "test-novo", ScopeWrite, time.Hour); err == nil {
		t.Fatal("esperava erro de persistência")
	}
	if err := store.RevokeCapability("restricted", "test-original"); err == nil {
		t.Fatal("esperava erro de persistência")
	}
	if store.ValidateCapability("restricted", "test-novo", ScopeWrite) ||
		!store.ValidateCapability("restricted", "test-original", ScopeWrite) {
		t.Fatal("uma alteração com falha mudou a autorização em memória")
	}
}

func TestRequestedTTLIsCappedBeforeOverflow(t *testing.T) {
	store, err := NewBlindMailboxStore("", time.Hour, 1024, 1024)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1700000000, 0)
	env, err := store.Store("ttl-box", "YQ==", math.MaxInt64, "", StateNormal, now)
	if err != nil {
		t.Fatal(err)
	}
	if env.ExpiresAt != now.Add(time.Hour).Unix() {
		t.Fatalf("TTL incorreto: %d", env.ExpiresAt)
	}
}

func TestLegacyQuotaTokenMigration(t *testing.T) {
	dir := t.TempDir()
	file := filepath.Join(dir, "legacy.json")
	now := time.Now()
	data, err := json.Marshal([]Envelope{{
		ID: "legacy-entry", PayloadB64: "YQ==", CreatedAt: now.Unix(),
		ExpiresAt: now.Add(time.Hour).Unix(), ByteSize: 1, QuotaToken: "legacy-fixture",
	}})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(file, data, 0600); err != nil {
		t.Fatal(err)
	}
	store, err := NewBlindMailboxStore(dir, time.Hour, 1024, 1)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.Store("legacy", "Yg==", 60, "legacy-fixture", StateNormal, now); !errors.Is(err, ErrQuotaExceeded) {
		t.Fatalf("a migração deve preservar a cota: %v", err)
	}
	persisted, err := os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(persisted), "legacy-fixture") || !strings.Contains(string(persisted), "quota_token_hash") {
		t.Fatal("a migração deve conservar apenas o hash de cota")
	}
}

func TestPostgresDurableQuotaAcrossStores(t *testing.T) {
	dsn := os.Getenv("NIX_TEST_PG_DSN")
	if dsn == "" {
		t.Skip("NIX_TEST_PG_DSN não definido")
	}
	const limit = 4
	ctx := context.Background()
	open := func(init bool) *PostgresMailboxStore {
		t.Helper()
		store, err := NewPostgresMailboxStore(ctx, dsn, time.Hour, 1024, limit, init)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = store.Close() })
		return store
	}
	first := open(true)
	second := open(false)
	pair := []*PostgresMailboxStore{first, second}
	boxes := []string{"quota-a-" + newRandomUUIDv4(), "quota-b-" + newRandomUUIDv4()}
	token := "quota-fixture-" + newRandomUUIDv4()

	type result struct {
		box string
		env Envelope
		err error
	}
	results := make(chan result, 2)
	for i, store := range pair {
		go func(store *PostgresMailboxStore, box string) {
			env, err := store.Store(box, "dGVzdA==", 60, token, StateNormal, time.Now())
			results <- result{box, env, err}
		}(store, boxes[i])
	}
	var accepted result
	var successes, denials int
	for range pair {
		result := <-results
		switch {
		case result.err == nil:
			successes++
			accepted = result
		case errors.Is(result.err, ErrQuotaExceeded):
			denials++
		default:
			t.Fatal(result.err)
		}
	}
	if successes != 1 || denials != 1 {
		t.Fatalf("esperado um envio aceito e um bloqueado, obtidos %d e %d", successes, denials)
	}

	reopened := open(false)
	storeFullPayload := func(ttl int64) (Envelope, error) {
		return reopened.Store(boxes[0], "dGVzdA==", ttl, token, StateNormal, time.Now())
	}
	if _, err := storeFullPayload(60); !errors.Is(err, ErrQuotaExceeded) {
		t.Fatalf("a segunda instância deve respeitar a cota persistida: %v", err)
	}
	if n, err := second.Ack(accepted.box, []string{accepted.env.ID}); err != nil || n != 1 {
		t.Fatalf("ACK deve liberar a cota: removidos=%d, erro=%v", n, err)
	}
	if _, err := storeFullPayload(1); err != nil {
		t.Fatal(err)
	}
	// Espera a expiração registrada pelo servidor, com um limite para o teste.
	deadline := time.Now().Add(5 * time.Second)
	for {
		_, err := storeFullPayload(60)
		if err == nil {
			break
		}
		if !errors.Is(err, ErrQuotaExceeded) || time.Now().After(deadline) {
			t.Fatalf("cota não liberada após expiração: %v", err)
		}
		time.Sleep(50 * time.Millisecond)
	}
}

func TestEmbeddedQuotaMigrationMatchesRelease(t *testing.T) {
	migration, err := os.ReadFile("../../../../database/migrations/relay_002_durable_quota.sql")
	if err != nil {
		t.Fatal(err)
	}
	if string(migration) != postgresQuotaMigrationSQL {
		t.Fatal("a migração embutida difere da migração distribuída")
	}
}
