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

	adminSrv := httptest.NewServer(NewAdminMux(store))
	defer adminSrv.Close()

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

	// 3. Fetch GET sem autenticação DEVE retornar 401 Unauthorized (Marco P0-4 / SEC01)
	unauthGetReq, _ := http.NewRequest(http.MethodGet, srv.URL+"/v1/mailboxes/mbox_test_1/envelopes", nil)
	unauthGetRes, err := http.DefaultClient.Do(unauthGetReq)
	if err != nil {
		t.Fatalf("unauth fetch failed: %v", err)
	}
	unauthGetRes.Body.Close()
	if unauthGetRes.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401 on unauthenticated fetch, got %d", unauthGetRes.StatusCode)
	}

	// Nenhuma credencial pode ser criada por uma leitura inicial.
	unprovisionedReq, _ := http.NewRequest(http.MethodGet, srv.URL+"/v1/mailboxes/mbox_test_1/envelopes", nil)
	unprovisionedReq.Header.Set("Authorization", "Bearer my_secret_token_123")
	unprovisioned, err := http.DefaultClient.Do(unprovisionedReq)
	if err != nil {
		t.Fatal(err)
	}
	unprovisioned.Body.Close()
	if unprovisioned.StatusCode != http.StatusForbidden {
		t.Fatalf("expected 403 without provisioned capability, got %d", unprovisioned.StatusCode)
	}
	if err := store.ProvisionCapability("mbox_test_1", "my_secret_token_123", buffer.ScopeReadAck, time.Hour); err != nil {
		t.Fatal(err)
	}

	// 4. Fetch GET autenticado com capability token
	authGetReq, _ := http.NewRequest(http.MethodGet, srv.URL+"/v1/mailboxes/mbox_test_1/envelopes", nil)
	authGetReq.Header.Set("Authorization", "Bearer my_secret_token_123")
	getRes, err := http.DefaultClient.Do(authGetReq)
	if err != nil {
		t.Fatalf("fetch GET failed: %v", err)
	}
	defer getRes.Body.Close()
	if getRes.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 on authenticated fetch, got %d", getRes.StatusCode)
	}
	var fetchOut struct {
		Envelopes []buffer.Envelope `json:"envelopes"`
	}
	if err := json.NewDecoder(getRes.Body).Decode(&fetchOut); err != nil {
		t.Fatalf("decode fetch failed: %v", err)
	}
	if len(fetchOut.Envelopes) != 1 || fetchOut.Envelopes[0].ID != storeOut.ID {
		t.Fatalf("unexpected envelopes: %+v", fetchOut.Envelopes)
	}

	// 5. Ack POST sem autenticação DEVE retornar 401 Unauthorized (Marco P0-4 / SEC01)
	ackBody, _ := json.Marshal(map[string]any{"ids": []string{storeOut.ID}})
	unauthAckReq, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/mailboxes/mbox_test_1/ack", bytes.NewReader(ackBody))
	unauthAckReq.Header.Set("Content-Type", "application/json")
	unauthAckRes, err := http.DefaultClient.Do(unauthAckReq)
	if err != nil {
		t.Fatalf("unauth ack failed: %v", err)
	}
	unauthAckRes.Body.Close()
	if unauthAckRes.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401 on unauthenticated ack, got %d", unauthAckRes.StatusCode)
	}

	// 6. Ack POST com token errado DEVE retornar 403 Forbidden
	wrongAckReq, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/mailboxes/mbox_test_1/ack", bytes.NewReader(ackBody))
	wrongAckReq.Header.Set("Content-Type", "application/json")
	wrongAckReq.Header.Set("Authorization", "Bearer wrong_token")
	wrongAckRes, err := http.DefaultClient.Do(wrongAckReq)
	if err != nil {
		t.Fatalf("wrong token ack failed: %v", err)
	}
	wrongAckRes.Body.Close()
	if wrongAckRes.StatusCode != http.StatusForbidden {
		t.Fatalf("expected 403 on wrong token ack, got %d", wrongAckRes.StatusCode)
	}

	// 7. Ack POST autenticado com token legítimo
	authAckReq, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/mailboxes/mbox_test_1/ack", bytes.NewReader(ackBody))
	authAckReq.Header.Set("Content-Type", "application/json")
	authAckReq.Header.Set("Authorization", "Bearer my_secret_token_123")
	ackRes, err := http.DefaultClient.Do(authAckReq)
	if err != nil {
		t.Fatalf("ack POST failed: %v", err)
	}
	defer ackRes.Body.Close()
	if ackRes.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 on authorized ack, got %d", ackRes.StatusCode)
	}
	var ackOut struct {
		Deleted int `json:"deleted"`
	}
	if err := json.NewDecoder(ackRes.Body).Decode(&ackOut); err != nil || ackOut.Deleted != 1 {
		t.Fatalf("expected deleted=1, got %d (err=%v)", ackOut.Deleted, err)
	}

	// 8. /metrics na superfície pública NewMux DEVE retornar 404 (isolamento do Onion)
	onionMetricsRes, err := http.Get(srv.URL + "/metrics")
	if err != nil {
		t.Fatalf("metrics onion request failed: %v", err)
	}
	onionMetricsRes.Body.Close()
	if onionMetricsRes.StatusCode != http.StatusNotFound {
		t.Fatalf("expected 404 on public onion /metrics, got %d", onionMetricsRes.StatusCode)
	}

	// 9. /metrics no adminSrv DEVE retornar 200 OK com métricas sem identificadores pessoais
	metRes, err := http.Get(adminSrv.URL + "/metrics")
	if err != nil {
		t.Fatalf("admin metrics GET failed: %v", err)
	}
	defer metRes.Body.Close()
	if metRes.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 on admin /metrics, got %d", metRes.StatusCode)
	}
	var buf bytes.Buffer
	_, _ = buf.ReadFrom(metRes.Body)
	if !strings.Contains(buf.String(), "nix_relay_total_acked 1") {
		t.Fatalf("expected metric nix_relay_total_acked 1, got:\n%s", buf.String())
	}
}
