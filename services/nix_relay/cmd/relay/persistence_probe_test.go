package main

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/projetonix/nix/services/nix_relay/internal/buffer"
)

func TestAuditPersistenceHTTPStatus(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("chmod não bloqueia escrita de root")
	}
	for _, operation := range []string{"store", "fetch", "ack"} {
		t.Run(operation, func(t *testing.T) {
			cfg := buffer.DefaultConfig()
			cfg.DataDir = t.TempDir()
			store, err := buffer.NewBlindMailboxStore(cfg.DataDir, time.Hour, 100, 100)
			if err != nil {
				t.Fatal(err)
			}
			now := time.Now()
			if operation == "fetch" {
				now = now.Add(-2 * time.Hour)
			}
			env, err := store.Store("mbox", "YWJjZA==", 3600, "", buffer.StateNormal, now)
			if err != nil {
				t.Fatal(err)
			}
			if err := os.Chmod(cfg.DataDir, 0500); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = os.Chmod(cfg.DataDir, 0700) })
			method, action, body := http.MethodPost, "envelopes", `{"payload_b64":"YWJjZA=="}`
			if operation == "fetch" {
				method, body = http.MethodGet, ""
			}
			if operation == "ack" {
				action, body = "ack", fmt.Sprintf(`{"ids":[%q]}`, env.ID)
			}
			req := httptest.NewRequest(method, "/v1/mailboxes/mbox/"+action, strings.NewReader(body))
			req.Header.Set("Authorization", "Bearer test-capability")
			w := httptest.NewRecorder()
			NewMux(cfg, store, buffer.NewAutoPruner(75, 85, 92)).ServeHTTP(w, req)
			if w.Code != http.StatusInternalServerError {
				t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
			}
			if strings.Contains(w.Body.String(), cfg.DataDir) {
				t.Error("resposta expõe caminho interno")
			}
		})
	}
}
