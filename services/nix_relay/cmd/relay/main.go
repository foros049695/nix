package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/projetonix/nix/services/nix_relay/internal/buffer"
)

func NewMux(cfg buffer.Config, store *buffer.BlindMailboxStore, pruner *buffer.AutoPruner) *http.ServeMux {
	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"status":       "ok",
			"version":      "0.4.0-dev",
			"ttl_seconds":  cfg.BaseTTLSeconds,
			"pruner_state": pruner.State(),
			"onion_host":   cfg.OnionServiceHost,
		})
	})

	mux.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		m := store.Metrics()
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		fmt.Fprintf(w, "# TYPE nix_relay_active_mailboxes gauge\nnix_relay_active_mailboxes %d\n", m.ActiveMailboxes)
		fmt.Fprintf(w, "# TYPE nix_relay_active_envelopes gauge\nnix_relay_active_envelopes %d\n", m.ActiveEnvelopes)
		fmt.Fprintf(w, "# TYPE nix_relay_stored_bytes gauge\nnix_relay_stored_bytes %d\n", m.StoredBytes)
		fmt.Fprintf(w, "# TYPE nix_relay_total_stored counter\nnix_relay_total_stored %d\n", m.TotalStored)
		fmt.Fprintf(w, "# TYPE nix_relay_total_acked counter\nnix_relay_total_acked %d\n", m.TotalAcked)
		fmt.Fprintf(w, "# TYPE nix_relay_total_pruned counter\nnix_relay_total_pruned %d\n", m.TotalPruned)
	})

	mux.HandleFunc("/v1/mailboxes/", func(w http.ResponseWriter, r *http.Request) {
		trimmed := strings.TrimPrefix(r.URL.Path, "/v1/mailboxes/")
		parts := strings.Split(trimmed, "/")
		if len(parts) != 2 {
			http.NotFound(w, r)
			return
		}
		mailboxID := parts[0]
		action := parts[1]

		switch action {
		case "envelopes":
			if r.Method == http.MethodPost {
				var req struct {
					PayloadB64 string `json:"payload_b64"`
					TTLSeconds int64  `json:"ttl_seconds"`
				}
				if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64*1024*1024)).Decode(&req); err != nil {
					http.Error(w, "json inválido", http.StatusBadRequest)
					return
				}
				quotaToken := r.Header.Get("X-Nix-Quota-Token")
				env, err := store.Store(mailboxID, req.PayloadB64, req.TTLSeconds, quotaToken, pruner.State(), time.Now().UTC())
				if err != nil {
					switch {
					case errors.Is(err, buffer.ErrInvalidMailbox):
						http.Error(w, err.Error(), http.StatusBadRequest)
					case errors.Is(err, buffer.ErrPayloadTooLarge):
						http.Error(w, err.Error(), http.StatusRequestEntityTooLarge)
					case errors.Is(err, buffer.ErrQuotaExceeded), errors.Is(err, buffer.ErrCriticalPressure):
						http.Error(w, err.Error(), http.StatusInsufficientStorage)
					default:
						http.Error(w, err.Error(), http.StatusBadRequest)
					}
					return
				}
				writeJSON(w, http.StatusAccepted, map[string]any{
					"id":         env.ID,
					"expires_at": env.ExpiresAt,
				})
				return
			}

			if r.Method == http.MethodGet {
				envs, err := store.Fetch(mailboxID, time.Now().UTC())
				if err != nil {
					http.Error(w, err.Error(), http.StatusBadRequest)
					return
				}
				writeJSON(w, http.StatusOK, map[string]any{"envelopes": envs})
				return
			}
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)

		case "ack":
			if r.Method != http.MethodPost {
				http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
				return
			}
			var req struct {
				IDs []string `json:"ids"`
			}
			if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 2*1024*1024)).Decode(&req); err != nil {
				http.Error(w, "json inválido", http.StatusBadRequest)
				return
			}
			deleted, err := store.Ack(mailboxID, req.IDs)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, http.StatusOK, map[string]any{"deleted": deleted})

		default:
			http.NotFound(w, r)
		}
	})

	return mux
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func main() {
	configPath := flag.String("config", "configs/relay.example.yaml", "Caminho do arquivo de configuração do relay")
	flag.Parse()

	cfg, err := buffer.LoadYAMLConfig(*configPath)
	if err != nil {
		log.Printf("[NIX-RELAY] Aviso ao ler %s (%v); usando configuração padrão em memória/local.", *configPath, err)
		cfg = buffer.DefaultConfig()
	}

	store, err := buffer.NewBlindMailboxStore(
		cfg.DataDir,
		time.Duration(cfg.BaseTTLSeconds)*time.Second,
		cfg.MaxAttachmentSizeBytes,
		cfg.MaxInFlightPerQuotaToken,
	)
	if err != nil {
		log.Fatalf("[NIX-RELAY] Erro ao iniciar armazenamento cego (%s): %v", cfg.DataDir, err)
	}

	pruner := buffer.NewAutoPruner(
		cfg.LightThresholdPercent,
		cfg.SevereThresholdPercent,
		cfg.CriticalThresholdPercent,
	)
	pruner.AttachDiskMonitor(cfg.DataDir, time.Duration(cfg.BaseTTLSeconds)*time.Second, store)

	stopCh := make(chan struct{})
	go pruner.Start(time.Duration(cfg.CheckIntervalSeconds)*time.Second, stopCh)

	mux := NewMux(cfg, store, pruner)
	addr := fmt.Sprintf("%s:%d", cfg.ServerHost, cfg.ServerPort)
	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		close(stopCh)
		_ = srv.Close()
	}()

	log.Printf("[NIX-RELAY] Store-and-Forward cego ativo em http://%s (TTL=%ds, zero logs de IP).", addr, cfg.BaseTTLSeconds)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("[NIX-RELAY] Falha no servidor HTTP: %v", err)
	}
}
