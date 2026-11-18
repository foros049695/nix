package buffer

import (
	"encoding/base64"
	"testing"
	"time"
)

func TestAutoPrunerHysteresisAndProgressiveRelief(t *testing.T) {
	store, err := NewBlindMailboxStore(t.TempDir(), 7*24*time.Hour, 52428800, 524288000)
	if err != nil {
		t.Fatalf("failed to init store: %v", err)
	}

	usage := 30
	pruner := NewAutoPruner(75, 85, 92)
	pruner.AttachDiskMonitor("", 7*24*time.Hour, store)
	pruner.SetUsageSampler(func() int { return usage })

	now := time.Unix(1_700_000_000, 0).UTC()
	payload := base64.StdEncoding.EncodeToString([]byte("encrypted-envelope-data"))

	// Envelope criado há 5 dias atrás (ainda dentro dos 7 dias normais)
	fiveDaysAgo := now.Add(-5 * 24 * time.Hour)
	if _, err := store.Store("mbox_alpha", payload, 0, "", StateNormal, fiveDaysAgo); err != nil {
		t.Fatalf("store failed: %v", err)
	}

	// Em 30%: permanece NORMAL, envelope de 5 dias preservado
	state, removed := pruner.EvaluateNow(now)
	if state != StateNormal || removed != 0 {
		t.Fatalf("expected NORMAL & 0 removed, got %s & %d", state, removed)
	}

	// Sobe para 76% -> LIGHT_RELIEF (teto de 96h / 4 dias) -> remove envelope de 5 dias
	usage = 76
	state, removed = pruner.EvaluateNow(now)
	if state != StateLightRelief || removed != 1 {
		t.Fatalf("expected LIGHT_RELIEF & 1 removed, got %s & %d", state, removed)
	}

	// Sobe para 93% -> CRITICAL_BLOCK -> bloqueia anexo acima de 1 MB
	usage = 93
	state, _ = pruner.EvaluateNow(now)
	if state != StateCriticalBlock {
		t.Fatalf("expected CRITICAL_BLOCK, got %s", state)
	}
	huge := base64.StdEncoding.EncodeToString(make([]byte, 2*1024*1024))
	if _, err := store.Store("mbox_alpha", huge, 0, "", state, now); err != ErrCriticalPressure {
		t.Fatalf("expected ErrCriticalPressure on >1MB upload, got %v", err)
	}

	// Desce para 72% -> por histerese (< 70%), não retorna a NORMAL ainda (vai para LIGHT_RELIEF)
	usage = 72
	state, _ = pruner.EvaluateNow(now)
	if state != StateLightRelief {
		t.Fatalf("expected hysteresis step to hold LIGHT_RELIEF at 72%%, got %s", state)
	}

	// Desce para 65% -> retorna a NORMAL
	usage = 65
	state, _ = pruner.EvaluateNow(now)
	if state != StateNormal {
		t.Fatalf("expected return to NORMAL at 65%%, got %s", state)
	}
}
