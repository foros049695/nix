package main

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"runtime"
	"sort"
	"sync"
	"sync/atomic"
	"time"

	"github.com/projetonix/nix/services/nix_relay/internal/buffer"
)

// Simulador de carga de 50 clientes concorrentes para o Nix Relay (Fase 4).
// Mede p50/p95/p99 de latência, RSS em memória do processo, crescimento em disco
// com mensagens + anexos de 2 MB e comportamento de reconexão.
func main() {
	clients := flag.Int("clients", 50, "Número de clientes concorrentes")
	duration := flag.Duration("duration", 20*time.Second, "Duração contínua do benchmark")
	attachRatio := flag.Int("attach-every", 25, "A cada N mensagens envia um anexo de 2 MB")
	flag.Parse()

	tmpDir, err := os.MkdirTemp("", "nix_bench_*")
	if err != nil {
		panic(err)
	}
	defer os.RemoveAll(tmpDir)

	cfg := buffer.DefaultConfig()
	cfg.DataDir = tmpDir
	cfg.MaxAttachmentSizeBytes = 50 * 1024 * 1024
	store, err := buffer.NewBlindMailboxStore(cfg.DataDir, 7*24*time.Hour, cfg.MaxAttachmentSizeBytes, cfg.MaxInFlightPerQuotaToken)
	if err != nil {
		panic(err)
	}
	pruner := buffer.NewAutoPruner(cfg.LightThresholdPercent, cfg.SevereThresholdPercent, cfg.CriticalThresholdPercent)
	pruner.AttachDiskMonitor(cfg.DataDir, 7*24*time.Hour, store)

	// Reproduz roteamento real completo de /v1/mailboxes/ com mux isolado
	srv := httptest.NewServer(newBenchMux(cfg, store, pruner))
	defer srv.Close()

	// Payloads pré-gerados em memória (texto pequeno E2EE e anexo de 2 MB cifrado)
	smallCipher := make([]byte, 512)
	_, _ = rand.Read(smallCipher)
	smallB64 := base64.StdEncoding.EncodeToString(smallCipher)

	twoMBCipher := make([]byte, 2*1024*1024)
	_, _ = rand.Read(twoMBCipher)
	twoMBB64 := base64.StdEncoding.EncodeToString(twoMBCipher)

	// Provisiona 50 mailboxes e tokens SHA-256 distintos
	mailboxes := make([]string, *clients)
	tokens := make([]string, *clients)
	for i := 0; i < *clients; i++ {
		sum := sha256.Sum256([]byte(fmt.Sprintf("bench-client-%d", i)))
		mailboxes[i] = hex.EncodeToString(sum[:])
		tokens[i] = fmt.Sprintf("cap-bench-%d", i)
		if err := store.ProvisionCapability(mailboxes[i], tokens[i], buffer.ScopeReadAck, 24*time.Hour); err != nil {
			panic(err)
		}
	}

	var (
		latMu      sync.Mutex
		latencies  []time.Duration
		totalOps   atomic.Int64
		total2MB   atomic.Int64
		totalErrs  atomic.Int64
		reconnects atomic.Int64
	)

	stopAt := time.Now().Add(*duration)
	startWall := time.Now()
	var wg sync.WaitGroup

	for c := 0; c < *clients; c++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			tr := &http.Transport{MaxIdleConnsPerHost: 4}
			client := &http.Client{Transport: tr, Timeout: 15 * time.Second}
			mbox := mailboxes[idx]
			tok := tokens[idx]
			step := 0

			for time.Now().Before(stopAt) {
				step++
				// Simula reconexão periódica fechando conexões ociosas a cada 15 ciclos
				if step%15 == 0 {
					tr.CloseIdleConnections()
					reconnects.Add(1)
				}

				targetMbox := mailboxes[(idx+1)%*clients]
				payloadB64 := smallB64
				isAttach := step%*attachRatio == 0
				if isAttach {
					payloadB64 = twoMBB64
				}

				t0 := time.Now()
				postBody, _ := json.Marshal(map[string]any{
					"payload_b64": payloadB64,
					"ttl_seconds": 3600,
				})
				req, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/mailboxes/"+targetMbox+"/envelopes", bytes.NewReader(postBody))
				req.Header.Set("Content-Type", "application/json")
				res, err := client.Do(req)
				if err != nil || res.StatusCode != http.StatusAccepted {
					totalErrs.Add(1)
					if res != nil {
						res.Body.Close()
					}
					continue
				}
				_, _ = io.Copy(io.Discard, res.Body)
				res.Body.Close()

				// Fetch + Ack do próprio mailbox
				getReq, _ := http.NewRequest(http.MethodGet, srv.URL+"/v1/mailboxes/"+mbox+"/envelopes", nil)
				getReq.Header.Set("Authorization", "Bearer "+tok)
				getRes, err := client.Do(getReq)
				if err == nil && getRes.StatusCode == http.StatusOK {
					var out struct {
						Envelopes []buffer.Envelope `json:"envelopes"`
					}
					_ = json.NewDecoder(getRes.Body).Decode(&out)
					getRes.Body.Close()
					if len(out.Envelopes) > 0 {
						ids := make([]string, len(out.Envelopes))
						for i, e := range out.Envelopes {
							ids[i] = e.ID
						}
						ackBody, _ := json.Marshal(map[string]any{"ids": ids})
						ackReq, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/mailboxes/"+mbox+"/ack", bytes.NewReader(ackBody))
						ackReq.Header.Set("Content-Type", "application/json")
						ackReq.Header.Set("Authorization", "Bearer "+tok)
						if ackRes, aErr := client.Do(ackReq); aErr == nil {
							ackRes.Body.Close()
						}
					}
				} else {
					if getRes != nil {
						getRes.Body.Close()
					}
					totalErrs.Add(1)
				}

				elapsed := time.Since(t0)
				latMu.Lock()
				latencies = append(latencies, elapsed)
				latMu.Unlock()
				totalOps.Add(1)
				if isAttach {
					total2MB.Add(1)
				}
				time.Sleep(40 * time.Millisecond)
			}
		}(c)
	}

	wg.Wait()
	wall := time.Since(startWall)

	// Dispara uma avaliação do AutoPruner com pressão simulada (histerese)
	pruner.SetUsageSampler(func() int { return 88 })
	prunerState, prunedCount := pruner.EvaluateNow(time.Now().UTC().Add(200 * time.Hour))

	sort.Slice(latencies, func(i, j int) bool { return latencies[i] < latencies[j] })
	p50, p95, p99 := time.Duration(0), time.Duration(0), time.Duration(0)
	if len(latencies) > 0 {
		p50 = latencies[len(latencies)*50/100]
		p95 = latencies[len(latencies)*95/100]
		p99 = latencies[len(latencies)*99/100]
	}

	var mem runtime.MemStats
	runtime.ReadMemStats(&mem)
	rssMB := float64(mem.Sys) / (1024 * 1024)
	heapAllocMB := float64(mem.HeapAlloc) / (1024 * 1024)
	m := store.Metrics()

	fmt.Printf("=== NIX RELAY 50-CLIENT BENCHMARK RESULT ===\n")
	fmt.Printf("clients=%d duration=%s reconnects=%d errors=%d\n", *clients, wall.Round(time.Millisecond), reconnects.Load(), totalErrs.Load())
	fmt.Printf("ops=%d throughput=%.2f ops/s attachments_2mb=%d\n", totalOps.Load(), float64(totalOps.Load())/wall.Seconds(), total2MB.Load())
	fmt.Printf("latency_p50=%s latency_p95=%s latency_p99=%s\n", p50.Round(time.Microsecond), p95.Round(time.Microsecond), p99.Round(time.Microsecond))
	fmt.Printf("mem_sys_mb=%.2f heap_alloc_mb=%.2f stored_bytes=%d total_stored=%d total_acked=%d\n", rssMB, heapAllocMB, m.StoredBytes, m.TotalStored, m.TotalAcked)
	fmt.Printf("autopruner_pressure_state=%s pruned_count=%d\n", prunerState, prunedCount)
}

func newBenchMux(cfg buffer.Config, store buffer.RelayStore, pruner *buffer.AutoPruner) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/mailboxes/", func(w http.ResponseWriter, r *http.Request) {
		rest := r.URL.Path[len("/v1/mailboxes/"):]
		idx := bytes.IndexByte([]byte(rest), '/')
		if idx <= 0 {
			http.NotFound(w, r)
			return
		}
		mboxID := rest[:idx]
		action := rest[idx+1:]
		switch action {
		case "envelopes":
			if r.Method == http.MethodPost {
				var req struct {
					PayloadB64 string `json:"payload_b64"`
					TTLSeconds int64  `json:"ttl_seconds"`
				}
				if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, cfg.MaxAttachmentSizeBytes*2)).Decode(&req); err != nil {
					http.Error(w, "bad json", http.StatusBadRequest)
					return
				}
				env, err := store.Store(mboxID, req.PayloadB64, req.TTLSeconds, "", pruner.State(), time.Now().UTC())
				if err != nil {
					http.Error(w, err.Error(), http.StatusBadRequest)
					return
				}
				w.WriteHeader(http.StatusAccepted)
				_ = json.NewEncoder(w).Encode(map[string]any{"id": env.ID})
				return
			}
			if r.Method == http.MethodGet {
				auth := r.Header.Get("Authorization")
				tok := ""
				if len(auth) > 7 {
					tok = auth[7:]
				}
				if !store.ValidateCapability(mboxID, tok, buffer.ScopeReadAck) {
					http.Error(w, "forbidden", http.StatusForbidden)
					return
				}
				envs, err := store.Fetch(mboxID, time.Now().UTC())
				if err != nil {
					http.Error(w, err.Error(), http.StatusInternalServerError)
					return
				}
				_ = json.NewEncoder(w).Encode(map[string]any{"envelopes": envs})
				return
			}
		case "ack":
			if r.Method == http.MethodPost {
				auth := r.Header.Get("Authorization")
				tok := ""
				if len(auth) > 7 {
					tok = auth[7:]
				}
				if !store.ValidateCapability(mboxID, tok, buffer.ScopeReadAck) {
					http.Error(w, "forbidden", http.StatusForbidden)
					return
				}
				var req struct {
					IDs []string `json:"ids"`
				}
				if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
					http.Error(w, "bad json", http.StatusBadRequest)
					return
				}
				deleted, err := store.Ack(mboxID, req.IDs)
				if err != nil {
					http.Error(w, err.Error(), http.StatusInternalServerError)
					return
				}
				_ = json.NewEncoder(w).Encode(map[string]any{"deleted": deleted})
				return
			}
		}
		http.NotFound(w, r)
	})
	return mux
}
