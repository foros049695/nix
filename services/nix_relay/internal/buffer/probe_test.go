package buffer

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// TestAuditQuotaRestart probe de regressão (REL02): verifica que o armazenamento em disco
// atual perde o controle de quota Usage após reinicialização do store.
func TestAuditQuotaRestart(t *testing.T) {
	d := t.TempDir()
	s, err := NewBlindMailboxStore(d, 7*24*time.Hour, 100, 4)
	if err != nil {
		t.Fatal(err)
	}

	// Grava 4 bytes (atinge o limite da cota)
	if _, err := s.Store("mbox", "YWJjZA==", 3600, "same-token", StateNormal, time.Now()); err != nil {
		t.Fatal(err)
	}

	// Reinicializa o store no mesmo diretório
	s2, err := NewBlindMailboxStore(d, 7*24*time.Hour, 100, 4)
	if err != nil {
		t.Fatal(err)
	}

	// No código atual com JSON, a cota resetou, permitindo gravação excedente
	_, err = s2.Store("mbox", "YWJjZA==", 3600, "same-token", StateNormal, time.Now())
	if err == nil {
		t.Log("PROBE CONFIRMADO (REL02): restart permitiu 8 bytes contra cota de 4 bytes")
	}
}

// TestAuditPersistenceFailure probe de regressão (REL01): verifica que erros no salvamento em disco
// são ignorados e Store retorna envelope sem erro no store de arquivos JSON legado.
func TestAuditPersistenceFailure(t *testing.T) {
	d := filepath.Join(t.TempDir(), "data")
	s, err := NewBlindMailboxStore(d, time.Hour, 100, 100)
	if err != nil {
		t.Fatal(err)
	}

	// Cria arquivo bloqueador para forçar erro de I/O
	_ = os.Remove(d)
	_ = os.WriteFile(d, []byte("blocking file"), 0600)

	_, err = s.Store("mbox", "YWJjZA==", 3600, "", StateNormal, time.Now())
	if err == nil {
		t.Log("PROBE CONFIRMADO (REL01): Store reporta sucesso mesmo com falha na gravação em disco")
	}
}
