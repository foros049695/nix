package buffer

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
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

// Falhas ao remover o último arquivo e ao reescrever uma mailbox devem preservar
// envelopes, cotas e contadores até a persistência confirmar a operação.
func TestAuditRemovalPersistenceFailure(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("chmod não bloqueia escrita de root")
	}
	for _, operation := range []string{"ack", "fetch", "sweep"} {
		for _, keepOne := range []bool{false, true} {
			t.Run(fmt.Sprintf("%s/keep=%v", operation, keepOne), func(t *testing.T) {
				d := t.TempDir()
				s, err := NewBlindMailboxStore(d, 24*time.Hour, 100, 100)
				if err != nil {
					t.Fatal(err)
				}
				now := time.Now()
				env, err := s.Store("mbox", "YWJjZA==", 3600, "quota", StateNormal, now)
				if err != nil {
					t.Fatal(err)
				}
				if keepOne {
					if _, err := s.Store("mbox", "YWJjZA==", 86400, "quota", StateNormal, now); err != nil {
						t.Fatal(err)
					}
				}
				before := s.Metrics()
				if err := os.Chmod(d, 0500); err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() { _ = os.Chmod(d, 0700) })
				switch operation {
				case "ack":
					deleted, err := s.Ack("mbox", []string{env.ID})
					if err == nil || deleted != 0 {
						t.Errorf("ack deve falhar sem exclusões: deleted=%d err=%v", deleted, err)
					}
				case "fetch":
					got, err := s.Fetch("mbox", now.Add(2*time.Hour))
					if err == nil || len(got) != 0 {
						t.Errorf("fetch deve falhar: len=%d err=%v", len(got), err)
					}
				case "sweep":
					pruner := NewAutoPruner(75, 85, 92)
					pruner.AttachDiskMonitor("", 24*time.Hour, s)
					_, removed := pruner.EvaluateNow(now.Add(2 * time.Hour))
					if removed != 0 {
						t.Errorf("sweep reportou %d exclusões não persistidas", removed)
					}
				}
				if got := s.Metrics(); got != before {
					t.Errorf("contadores alterados: got=%+v want=%+v", got, before)
				}
				if s.quotaUsage[quotaTokenHash("quota")] != before.StoredBytes {
					t.Error("cota alterada após falha")
				}
				reloaded, err := NewBlindMailboxStore(d, 24*time.Hour, 100, 100)
				if err != nil {
					t.Fatal(err)
				}
				if !reflect.DeepEqual(s.mailboxes, reloaded.mailboxes) {
					t.Error("memória diverge do disco após falha")
				}
				if err := os.Chmod(d, 0700); err != nil {
					t.Fatal(err)
				}
				if operation == "ack" {
					if n, err := s.Ack("mbox", []string{env.ID}); err != nil || n != 1 {
						t.Fatalf("retry: n=%d err=%v", n, err)
					}
					reloaded, err = NewBlindMailboxStore(d, 24*time.Hour, 100, 100)
					if err != nil {
						t.Fatal(err)
					}
					if !reflect.DeepEqual(s.mailboxes, reloaded.mailboxes) {
						t.Error("ack confirmado ressuscitou após restart")
					}
				}
			})
		}
	}
}
