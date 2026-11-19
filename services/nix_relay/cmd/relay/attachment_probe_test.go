package main

import (
	"encoding/base64"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/projetonix/nix/services/nix_relay/internal/buffer"
)

func TestAuditAttachmentBodyLimit(t *testing.T) {
	for _, tc := range []struct {
		name string
		size int
		want int
	}{
		{"configured-cap", 17, http.StatusAccepted},
		{"one-byte-over", 18, http.StatusRequestEntityTooLarge},
	} {
		t.Run(tc.name, func(t *testing.T) {
			cfg := buffer.DefaultConfig()
			cfg.MaxAttachmentSizeBytes = 17
			store, err := buffer.NewBlindMailboxStore("", time.Hour, cfg.MaxAttachmentSizeBytes, cfg.MaxInFlightPerQuotaToken)
			if err != nil {
				t.Fatal(err)
			}
			encoded := base64.StdEncoding.EncodeToString(make([]byte, tc.size))
			body := io.MultiReader(strings.NewReader(`{"payload_b64":"`), strings.NewReader(encoded), strings.NewReader(`","ttl_seconds":3600}`))
			w := httptest.NewRecorder()
			NewMux(cfg, store, buffer.NewAutoPruner(75, 85, 92)).ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/v1/mailboxes/mbox/envelopes", body))
			if w.Code != tc.want {
				t.Fatalf("status=%d want=%d body=%s", w.Code, tc.want, w.Body.String())
			}
		})
	}
}

func TestAuditAttachmentBodyOverflow(t *testing.T) {
	cfg := buffer.DefaultConfig()
	cfg.MaxAttachmentSizeBytes = 3
	store, err := buffer.NewBlindMailboxStore("", time.Hour, 3, 100)
	if err != nil {
		t.Fatal(err)
	}
	mux := NewMux(cfg, store, buffer.NewAutoPruner(75, 85, 92))
	for _, body := range []string{
		`{"payload_b64":"` + strings.Repeat("A", 8192) + `"}`,
		`{"payload_b64":"YWJj"}` + strings.Repeat(" ", 8192),
	} {
		w := httptest.NewRecorder()
		mux.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/v1/mailboxes/mbox/envelopes", strings.NewReader(body)))
		if w.Code != http.StatusRequestEntityTooLarge {
			t.Errorf("status=%d want=413", w.Code)
		}
	}
	if store.Metrics().TotalStored != 0 {
		t.Error("body excessivo foi armazenado")
	}
}

func TestAttachmentPressureCapsAndMalformedJSON(t *testing.T) {
	cfg := buffer.DefaultConfig()
	store, err := buffer.NewBlindMailboxStore("", time.Hour, cfg.MaxAttachmentSizeBytes, cfg.MaxInFlightPerQuotaToken)
	if err != nil {
		t.Fatal(err)
	}
	pruner := buffer.NewAutoPruner(75, 85, 92)
	mux := NewMux(cfg, store, pruner)
	for _, tc := range []struct{ usage, size, want int }{
		{85, 10 * 1024 * 1024, http.StatusAccepted},
		{85, 10*1024*1024 + 1, http.StatusRequestEntityTooLarge},
		{95, 1024 * 1024, http.StatusAccepted},
		{95, 1024*1024 + 1, http.StatusInsufficientStorage},
	} {
		pruner.SetUsageSampler(func() int { return tc.usage })
		pruner.EvaluateNow(time.Now())
		body := `{"payload_b64":"` + base64.StdEncoding.EncodeToString(make([]byte, tc.size)) + `"}`
		w := httptest.NewRecorder()
		mux.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/v1/mailboxes/mbox/envelopes", strings.NewReader(body)))
		if w.Code != tc.want {
			t.Errorf("usage=%d size=%d status=%d want=%d", tc.usage, tc.size, w.Code, tc.want)
		}
	}
	for _, body := range []string{`{`, `{"payload_b64":"YWJj"} {}`} {
		w := httptest.NewRecorder()
		mux.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/v1/mailboxes/mbox/envelopes", strings.NewReader(body)))
		if w.Code != http.StatusBadRequest {
			t.Errorf("JSON inválido: status=%d", w.Code)
		}
	}
}

func TestAttachmentBodyLimitArithmetic(t *testing.T) {
	for _, tc := range []struct{ size, want int64 }{
		{1, 1028}, {2, 1028}, {3, 1028}, {4, 1032},
		{0, 69906092}, {1<<63 - 1, 1<<63 - 1},
	} {
		if got := attachmentBodyLimit(tc.size); got != tc.want {
			t.Errorf("size=%d got=%d want=%d", tc.size, got, tc.want)
		}
	}
}
