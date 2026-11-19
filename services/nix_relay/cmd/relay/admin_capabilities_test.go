package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/projetonix/nix/services/nix_relay/internal/buffer"
)

func TestAdminCapabilitiesProvisionEnforceWriteAndRevoke(t *testing.T) {
	cfg := buffer.DefaultConfig()
	cfg.DataDir = t.TempDir()

	store, err := buffer.NewBlindMailboxStore(cfg.DataDir, 24*time.Hour, cfg.MaxAttachmentSizeBytes, cfg.MaxInFlightPerQuotaToken)
	if err != nil {
		t.Fatal(err)
	}
	pruner := buffer.NewAutoPruner(75, 85, 92)
	publicMux := NewMux(cfg, store, pruner)
	adminMux := NewAdminMux(store)

	adminSrv := httptest.NewServer(adminMux)
	defer adminSrv.Close()
	publicSrv := httptest.NewServer(publicMux)
	defer publicSrv.Close()

	// Superfície pública Onion NÃO deve expor /admin/capabilities
	pubRes, err := http.Post(publicSrv.URL+"/admin/capabilities", "application/json", bytes.NewReader([]byte(`{}`)))
	if err != nil {
		t.Fatal(err)
	}
	pubRes.Body.Close()
	if pubRes.StatusCode != http.StatusNotFound {
		t.Fatalf("esperado 404 na superfície Onion para /admin/capabilities, got %d", pubRes.StatusCode)
	}

	// Provisiona capability write + read_ack via Admin loopback
	provWrite, _ := json.Marshal(map[string]any{
		"mailbox_id":  "mbox_scoped_99",
		"token":       "write_cap_secret",
		"scope":       "write",
		"ttl_seconds": 3600,
	})
	res, err := http.Post(adminSrv.URL+"/admin/capabilities", "application/json", bytes.NewReader(provWrite))
	if err != nil || res.StatusCode != http.StatusCreated {
		t.Fatalf("falha ao provisionar write capability: err=%v code=%v", err, res.StatusCode)
	}
	res.Body.Close()

	provRead, _ := json.Marshal(map[string]any{
		"mailbox_id":  "mbox_scoped_99",
		"token":       "read_cap_secret",
		"scope":       "read_ack",
		"ttl_seconds": 3600,
	})
	res2, err := http.Post(adminSrv.URL+"/admin/capabilities", "application/json", bytes.NewReader(provRead))
	if err != nil || res2.StatusCode != http.StatusCreated {
		t.Fatalf("falha ao provisionar read capability: err=%v code=%v", err, res2.StatusCode)
	}
	res2.Body.Close()

	envBody := `{"payload_b64":"` + base64.StdEncoding.EncodeToString([]byte("msg")) + `"}`

	// POST sem Bearer deve falhar com 401 quando ScopeWrite está explícito
	unauthPost, err := http.Post(publicSrv.URL+"/v1/mailboxes/mbox_scoped_99/envelopes", "application/json", bytes.NewReader([]byte(envBody)))
	if err != nil {
		t.Fatal(err)
	}
	unauthPost.Body.Close()
	if unauthPost.StatusCode != http.StatusUnauthorized {
		t.Fatalf("esperado 401 sem bearer quando write capability configurada, got %d", unauthPost.StatusCode)
	}

	// POST usando token read_only deve falhar com 403
	reqWrongScope, _ := http.NewRequest(http.MethodPost, publicSrv.URL+"/v1/mailboxes/mbox_scoped_99/envelopes", bytes.NewReader([]byte(envBody)))
	reqWrongScope.Header.Set("Content-Type", "application/json")
	reqWrongScope.Header.Set("Authorization", "Bearer read_cap_secret")
	wrongRes, _ := http.DefaultClient.Do(reqWrongScope)
	wrongRes.Body.Close()
	if wrongRes.StatusCode != http.StatusForbidden {
		t.Fatalf("esperado 403 para escopo read tentando escrever, got %d", wrongRes.StatusCode)
	}

	// POST usando token write_cap_secret deve aceitar (202)
	reqRightScope, _ := http.NewRequest(http.MethodPost, publicSrv.URL+"/v1/mailboxes/mbox_scoped_99/envelopes", bytes.NewReader([]byte(envBody)))
	reqRightScope.Header.Set("Content-Type", "application/json")
	reqRightScope.Header.Set("Authorization", "Bearer write_cap_secret")
	okRes, _ := http.DefaultClient.Do(reqRightScope)
	okRes.Body.Close()
	if okRes.StatusCode != http.StatusAccepted {
		t.Fatalf("esperado 202 com capability write válida, got %d", okRes.StatusCode)
	}

	// Revoga read_cap_secret e confirma bloqueio imediato
	delBody, _ := json.Marshal(map[string]any{
		"mailbox_id": "mbox_scoped_99",
		"token":      "read_cap_secret",
	})
	delReq, _ := http.NewRequest(http.MethodDelete, adminSrv.URL+"/admin/capabilities", bytes.NewReader(delBody))
	delRes, _ := http.DefaultClient.Do(delReq)
	delRes.Body.Close()
	if delRes.StatusCode != http.StatusOK {
		t.Fatalf("esperado 200 na revogação admin, got %d", delRes.StatusCode)
	}

	getRevoked, _ := http.NewRequest(http.MethodGet, publicSrv.URL+"/v1/mailboxes/mbox_scoped_99/envelopes", nil)
	getRevoked.Header.Set("Authorization", "Bearer read_cap_secret")
	getRes, _ := http.DefaultClient.Do(getRevoked)
	getRes.Body.Close()
	if getRes.StatusCode != http.StatusForbidden {
		t.Fatalf("esperado 403 após revogação da capability, got %d", getRes.StatusCode)
	}
}
