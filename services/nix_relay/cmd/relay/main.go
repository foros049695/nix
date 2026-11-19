package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/projetonix/nix/services/nix_relay/internal/buffer"
)

func NewMux(cfg buffer.Config, store buffer.RelayStore, pruner *buffer.AutoPruner) *http.ServeMux {
	mux := http.NewServeMux()
	bodyLimit := attachmentBodyLimit(cfg.MaxAttachmentSizeBytes)

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

	// /metrics removido da superfície pública Onion (Marco P0-4 / REL04).
	// O endpoint de métricas agora reside exclusivamente em NewAdminMux.

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
				if store.HasExplicitScope(mailboxID, buffer.ScopeWrite) {
					token, err := parseBearerToken(r)
					if err != nil {
						http.Error(w, err.Error(), http.StatusUnauthorized)
						return
					}
					if !store.ValidateCapability(mailboxID, token, buffer.ScopeWrite) {
						http.Error(w, "capability de escrita não autorizada para esta mailbox", http.StatusForbidden)
						return
					}
				}
				var req struct {
					PayloadB64 string `json:"payload_b64"`
					TTLSeconds int64  `json:"ttl_seconds"`
				}
				decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, bodyLimit))
				err := decoder.Decode(&req)
				if err == nil {
					// Exige um único objeto e consome o corpo inteiro, inclusive espaços.
					var extra any
					err = decoder.Decode(&extra)
					if errors.Is(err, io.EOF) {
						err = nil
					} else if err == nil {
						err = errors.New("objeto JSON adicional")
					}
				}
				if err != nil {
					var tooLarge *http.MaxBytesError
					if errors.As(err, &tooLarge) {
						http.Error(w, "corpo excede limite máximo permitido", http.StatusRequestEntityTooLarge)
					} else {
						http.Error(w, "json inválido", http.StatusBadRequest)
					}
					return
				}
				quotaToken := r.Header.Get("X-Nix-Quota-Token")
				env, err := store.Store(mailboxID, req.PayloadB64, req.TTLSeconds, quotaToken, pruner.State(), time.Now().UTC())
				if err != nil {
					switch {
					case errors.Is(err, buffer.ErrPersistence):
						http.Error(w, buffer.ErrPersistence.Error(), http.StatusInternalServerError)
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
				token, err := parseBearerToken(r)
				if err != nil {
					http.Error(w, err.Error(), http.StatusUnauthorized)
					return
				}
				if !store.ValidateCapability(mailboxID, token, buffer.ScopeReadAck) {
					http.Error(w, "capability de leitura não autorizada para esta mailbox", http.StatusForbidden)
					return
				}

				envs, err := store.Fetch(mailboxID, time.Now().UTC())
				if err != nil {
					writeStoreError(w, err)
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
			token, err := parseBearerToken(r)
			if err != nil {
				http.Error(w, err.Error(), http.StatusUnauthorized)
				return
			}
			if !store.ValidateCapability(mailboxID, token, buffer.ScopeReadAck) {
				http.Error(w, "capability de ack não autorizada para esta mailbox", http.StatusForbidden)
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
				writeStoreError(w, err)
				return
			}
			writeJSON(w, http.StatusOK, map[string]any{"deleted": deleted})

		default:
			http.NotFound(w, r)
		}
	})

	return mux
}

// NewAdminMux cria mux exclusivo para listener administrativo/métricas local (Marco P0-4 / REL04).
func NewAdminMux(store buffer.RelayStore) *http.ServeMux {
	mux := http.NewServeMux()
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

	// Provisionamento e revogação de capabilities SHA-256 restrito ao listener loopback administrativo.
	mux.HandleFunc("/admin/capabilities", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodPost:
			var req struct {
				MailboxID  string `json:"mailbox_id"`
				Token      string `json:"token"`
				Scope      string `json:"scope"`
				TTLSeconds int64  `json:"ttl_seconds"`
			}
			if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192)).Decode(&req); err != nil {
				http.Error(w, "json inválido", http.StatusBadRequest)
				return
			}
			scope := buffer.CapabilityScope(req.Scope)
			if scope == "" {
				scope = buffer.ScopeReadAck
			}
			if scope != buffer.ScopeReadAck && scope != buffer.ScopeWrite && scope != buffer.ScopeAdmin {
				http.Error(w, "escopo de capability inválido", http.StatusBadRequest)
				return
			}
			ttl := time.Duration(req.TTLSeconds) * time.Second
			if err := store.ProvisionCapability(req.MailboxID, req.Token, scope, ttl); err != nil {
				writeStoreError(w, err)
				return
			}
			writeJSON(w, http.StatusCreated, map[string]any{"status": "provisioned", "scope": string(scope)})

		case http.MethodDelete:
			var req struct {
				MailboxID string `json:"mailbox_id"`
				Token     string `json:"token"`
			}
			if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192)).Decode(&req); err != nil {
				http.Error(w, "json inválido", http.StatusBadRequest)
				return
			}
			if err := store.RevokeCapability(req.MailboxID, req.Token); err != nil {
				writeStoreError(w, err)
				return
			}
			writeJSON(w, http.StatusOK, map[string]any{"status": "revoked"})

		default:
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	})
	return mux
}

// Reserva espaço para nomes dos campos, TTL e formatação além do base64.
func attachmentBodyLimit(maxBytes int64) int64 {
	if maxBytes <= 0 {
		maxBytes = buffer.DefaultConfig().MaxAttachmentSizeBytes
	}
	const overhead int64 = 1024
	groups := maxBytes / 3
	if maxBytes%3 != 0 {
		groups++
	}
	if groups > (math.MaxInt64-overhead)/4 {
		return math.MaxInt64
	}
	return groups*4 + overhead
}

func parseBearerToken(r *http.Request) (string, error) {
	auth := r.Header.Get("Authorization")
	if auth == "" {
		return "", errors.New("cabeçalho Authorization obrigatório ausente")
	}
	parts := strings.SplitN(auth, " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || strings.TrimSpace(parts[1]) == "" {
		return "", errors.New("esquema de autorização inválido; esperado Bearer <token>")
	}
	return strings.TrimSpace(parts[1]), nil
}

func writeStoreError(w http.ResponseWriter, err error) {
	if errors.Is(err, buffer.ErrPersistence) {
		http.Error(w, buffer.ErrPersistence.Error(), http.StatusInternalServerError)
		return
	}
	http.Error(w, err.Error(), http.StatusBadRequest)
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

	var store buffer.RelayStore
	if cfg.PostgresDSN != "" {
		pgStore, pgErr := buffer.NewPostgresMailboxStore(
			context.Background(),
			cfg.PostgresDSN,
			time.Duration(cfg.BaseTTLSeconds)*time.Second,
			cfg.MaxAttachmentSizeBytes,
			cfg.MaxInFlightPerQuotaToken,
			true,
		)
		if pgErr != nil {
			log.Fatalf("[NIX-RELAY] Erro ao conectar no PostgreSQL: %v", pgErr)
		}
		store = pgStore
		log.Printf("[NIX-RELAY] Persistência ativa: PostgreSQL 17+ (schema nix.*).")
	} else {
		fsStore, fsErr := buffer.NewBlindMailboxStore(
			cfg.DataDir,
			time.Duration(cfg.BaseTTLSeconds)*time.Second,
			cfg.MaxAttachmentSizeBytes,
			cfg.MaxInFlightPerQuotaToken,
		)
		if fsErr != nil {
			log.Fatalf("[NIX-RELAY] Erro ao iniciar armazenamento cego (%s): %v", cfg.DataDir, fsErr)
		}
		store = fsStore
	}
	defer func() { _ = store.Close() }()

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

	var adminSrv *http.Server
	if cfg.MetricsEnabled && cfg.MetricsListenAddr != "" {
		if err := buffer.ValidateAdminListenAddr(cfg.MetricsListenAddr); err != nil {
			log.Fatalf("[NIX-RELAY] Bloqueio de segurança administrativa: %v", err)
		}
		adminMux := NewAdminMux(store)
		adminSrv = &http.Server{
			Addr:              cfg.MetricsListenAddr,
			Handler:           adminMux,
			ReadHeaderTimeout: 5 * time.Second,
		}
		go func() {
			log.Printf("[NIX-RELAY] Listener administrativo/métricas ativo em http://%s (isolado da superfície Onion).", cfg.MetricsListenAddr)
			if err := adminSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
				log.Printf("[NIX-RELAY] Listener de métricas finalizado: %v", err)
			}
		}()
	}

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		close(stopCh)
		if adminSrv != nil {
			_ = adminSrv.Close()
		}
		_ = srv.Close()
	}()

	log.Printf("[NIX-RELAY] Store-and-Forward cego ativo em http://%s (TTL=%ds, zero logs de IP).", addr, cfg.BaseTTLSeconds)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("[NIX-RELAY] Falha no servidor HTTP: %v", err)
	}
}
