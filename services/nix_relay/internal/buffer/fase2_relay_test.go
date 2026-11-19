package buffer

import (
	"context"
	"encoding/base64"
	"fmt"
	"os"
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
