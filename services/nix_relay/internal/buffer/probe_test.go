package buffer

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// TestAuditQuotaRestart verifica que a cota em trânsito é restaurada após reinicialização do store (REL02 resolvido).
func TestAuditQuotaRestart(t *testing.T) {
	d := t.TempDir()
	s, err := NewBlindMailboxStore(d, 7*24*time.Hour, 100, 4)
	if err != nil {
		t.Fatal(err)
	}

	// Grava 4 bytes (atinge o teto da cota de 4 bytes)
	if _, err := s.Store("mbox", "YWJjZA==", 3600, "same-token", StateNormal, time.Now()); err != nil {
		t.Fatal(err)
	}

	// Reinicializa o store no mesmo diretório
	s2, err := NewBlindMailboxStore(d, 7*24*time.Hour, 100, 4)
	if err != nil {
		t.Fatal(err)
	}

	// Agora com a cota reconstruída de forma durável, Store DEVE recusar com ErrQuotaExceeded
	_, err = s2.Store("mbox", "YWJjZA==", 3600, "same-token", StateNormal, time.Now())
	if !errors.Is(err, ErrQuotaExceeded) {
		t.Fatalf("esperado ErrQuotaExceeded após restart, obteve: %v", err)
	}
}

// TestAuditPersistenceFailure verifica que falhas de persistência em disco retornam erro e abortam a operação (REL01 resolvido).
func TestAuditPersistenceFailure(t *testing.T) {
	d := filepath.Join(t.TempDir(), "data")
	s, err := NewBlindMailboxStore(d, time.Hour, 100, 100)
	if err != nil {
		t.Fatal(err)
	}

	// Cria arquivo bloqueador com o mesmo nome do diretório para forçar falha de I/O
	_ = os.RemoveAll(d)
	_ = os.WriteFile(d, []byte("blocking file"), 0600)

	_, err = s.Store("mbox", "YWJjZA==", 3600, "", StateNormal, time.Now())
	if err == nil {
		t.Fatal("esperado erro ao falhar escrita em disco, mas Store retornou sucesso")
	}
}
