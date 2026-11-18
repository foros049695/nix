package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/projetonix/nix/services/nix_relay/internal/buffer"
)

func TestRelayHTTPStoreFetchAckAndHealthz(t *testing.T) {
	cfg := buffer.DefaultConfig()
	cfg.DataDir = t.TempDir()

	store, err := buffer.NewBlindMailboxStore(cfg.DataDir, 7*24*time.Hour, cfg.MaxAttachmentSizeBytes, cfg.MaxInFlightPerQuotaToken)
	if err != nil {
		t.Fatalf("store init failed: %v", err)
	}
	pruner := buffer.NewAutoPruner(75, 85, 92)
	pruner.AttachDiskMonitor(cfg.DataDir, 7*24*time.Hour, store)

	srv := httptest.NewServer(NewMux(cfg, store, pruner))
	defer srv.Close()

	// 1. /healthz
	resp, err := http.Get(srv.URL + "/healthz")
	if err != nil {
		t.Fatalf("healthz request failed: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 on healthz, got %d", resp.StatusCode)
	}

	// 2. Store POST /v1/mailboxes/{id}/envelopes
	bodyBytes, _ := json.Marshal(map[string]any{
		"payload_b64": base64.StdEncoding.EncodeToString([]byte("secret-blob-v4")),
		"ttl_seconds": 3600,
	})
	postRes, err := http.Post(srv.URL+"/v1/mailboxes/mbox_test_1/envelopes", "application/json", bytes.NewReader(bodyBytes))
	if err != nil {
		t.Fatalf("store POST failed: %v", err)
	}
	defer postRes.Body.Close()
	if postRes.StatusCode != http.StatusAccepted {
		t.Fatalf("expected 202 Accepted, got %d", postRes.StatusCode)
	}
	var storeOut struct {
		ID string `json:"id"`
	}
	if err := json.NewDecoder(postRes.Body).Decode(&storeOut); err != nil || storeOut.ID == "" {
		t.Fatalf("invalid store response: %v / id=%s", err, storeOut.ID)
	}

	// 3. Fetch GET /v1/mailboxes/{id}/envelopes
	getRes, err := http.Get(srv.URL + "/v1/mailboxes/mbox_test_1/envelopes")
	if err != nil {
		t.Fatalf("fetch GET failed: %v", err)
	}
	defer getRes.Body.Close()
	var fetchOut struct {
		Envelopes []buffer.Envelope `json:"envelopes"`
	}
	if err := json.NewDecoder(getRes.Body).Decode(&fetchOut); err != nil {
		t.Fatalf("decode fetch failed: %v", err)
	}
	if len(fetchOut.Envelopes) != 1 || fetchOut.Envelopes[0].ID != storeOut.ID {
		t.Fatalf("unexpected envelopes: %+v", fetchOut.Envelopes)
	}

	// 4. Ack POST /v1/mailboxes/{id}/ack
	ackBody, _ := json.Marshal(map[string]any{"ids": []string{storeOut.ID}})
	ackRes, err := http.Post(srv.URL+"/v1/mailboxes/mbox_test_1/ack", "application/json", bytes.NewReader(ackBody))
	if err != nil {
		t.Fatalf("ack POST failed: %v", err)
	}
	defer ackRes.Body.Close()
	var ackOut struct {
		Deleted int `json:"deleted"`
	}
	if err := json.NewDecoder(ackRes.Body).Decode(&ackOut); err != nil || ackOut.Deleted != 1 {
		t.Fatalf("expected deleted=1, got %d (err=%v)", ackOut.Deleted, err)
	}

	// 5. /metrics sem rótulos pessoais
	metRes, err := http.Get(srv.URL + "/metrics")
	if err != nil {
		t.Fatalf("metrics GET failed: %v", err)
	}
	defer metRes.Body.Close()
	var buf bytes.Buffer
	_, _ = buf.ReadFrom(metRes.Body)
	if !strings.Contains(buf.String(), "nix_relay_total_acked 1") {
		t.Fatalf("expected metric nix_relay_total_acked 1, got:\n%s", buf.String())
	}
}
