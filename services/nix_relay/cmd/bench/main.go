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
	"net/url"
	"os"
	"regexp"
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
	endpoint := flag.String("onion", "", "URL Onion v3 do relay de homologação")
	socks := flag.String("socks", "127.0.0.1:9050", "Endereço SOCKS5 local do Tor")
	credentials := flag.String("credentials", "", "Arquivo JSON privado com caixas de homologação provisionadas")
	flag.Parse()

	if *clients < 1 || *clients > 50 || *duration <= 0 || *attachRatio < 1 {
		fmt.Fprintln(os.Stderr, "use entre 1 e 50 clientes, duração positiva e attach-every >= 1")
		os.Exit(2)
	}

	boxes := make([]benchMailbox, *clients)
	var store buffer.RelayStore
	var pruner *buffer.AutoPruner
	var proxy func(*http.Request) (*url.URL, error)
	var baseURL string
	if *endpoint != "" {
		var err error
		baseURL, proxy, err = onionTransport(*endpoint, *socks)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		boxes, err = loadBenchMailboxes(*credentials, *clients)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
	} else {
		tmpDir, err := os.MkdirTemp("", "nix_bench_*")
		if err != nil {
			panic(err)
		}
		defer os.RemoveAll(tmpDir)

		cfg := buffer.DefaultConfig()
		cfg.DataDir = tmpDir
		store, err = buffer.NewBlindMailboxStore(cfg.DataDir, 7*24*time.Hour, cfg.MaxAttachmentSizeBytes, cfg.MaxInFlightPerQuotaToken)
		if err != nil {
			panic(err)
		}
		defer store.Close()
		pruner = buffer.NewAutoPruner(cfg.LightThresholdPercent, cfg.SevereThresholdPercent, cfg.CriticalThresholdPercent)
		pruner.AttachDiskMonitor(cfg.DataDir, 7*24*time.Hour, store)
		server := httptest.NewServer(newBenchMux(cfg, store, pruner))
		defer server.Close()
		baseURL = server.URL

		for i := range boxes {
			sum := sha256.Sum256([]byte(fmt.Sprintf("bench-client-%d", i)))
			boxes[i] = benchMailbox{ID: hex.EncodeToString(sum[:]), ReadToken: fmt.Sprintf("cap-bench-%d", i)}
			if err := store.ProvisionCapability(boxes[i].ID, boxes[i].ReadToken, buffer.ScopeReadAck, 24*time.Hour); err != nil {
				panic(err)
			}
		}
	}

	// Payloads pré-gerados em memória (texto pequeno E2EE e anexo de 2 MB cifrado)
	smallCipher := make([]byte, 512)
	_, _ = rand.Read(smallCipher)
	smallB64 := base64.StdEncoding.EncodeToString(smallCipher)

	twoMBCipher := make([]byte, 2*1024*1024)
	_, _ = rand.Read(twoMBCipher)
	twoMBB64 := base64.StdEncoding.EncodeToString(twoMBCipher)

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
			tr := &http.Transport{MaxIdleConnsPerHost: 4, Proxy: proxy}
			defer tr.CloseIdleConnections()
			client := &http.Client{
				Transport: tr, Timeout: 15 * time.Second,
				CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
			}
			mbox, tok := boxes[idx].ID, boxes[idx].ReadToken
			step := 0

			for time.Now().Before(stopAt) {
				step++
				// Simula reconexão periódica fechando conexões ociosas a cada 15 ciclos
				if step%15 == 0 {
					tr.CloseIdleConnections()
					reconnects.Add(1)
				}

				target := boxes[(idx+1)%*clients]
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
				req, _ := http.NewRequest(http.MethodPost, baseURL+"/v1/mailboxes/"+target.ID+"/envelopes", bytes.NewReader(postBody))
				req.Header.Set("Content-Type", "application/json")
				if target.WriteToken != "" {
					req.Header.Set("Authorization", "Bearer "+target.WriteToken)
				}
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
				getReq, _ := http.NewRequest(http.MethodGet, baseURL+"/v1/mailboxes/"+mbox+"/envelopes", nil)
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
						ackReq, _ := http.NewRequest(http.MethodPost, baseURL+"/v1/mailboxes/"+mbox+"/ack", bytes.NewReader(ackBody))
						ackReq.Header.Set("Content-Type", "application/json")
						ackReq.Header.Set("Authorization", "Bearer "+tok)
						ackRes, aErr := client.Do(ackReq)
						if aErr != nil || ackRes.StatusCode != http.StatusOK {
							totalErrs.Add(1)
						}
						if ackRes != nil {
							_, _ = io.Copy(io.Discard, ackRes.Body)
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

	fmt.Printf("=== NIX RELAY 50-CLIENT BENCHMARK RESULT ===\n")
	fmt.Printf("clients=%d duration=%s reconnects=%d errors=%d\n", *clients, wall.Round(time.Millisecond), reconnects.Load(), totalErrs.Load())
	fmt.Printf("ops=%d throughput=%.2f ops/s attachments_2mb=%d\n", totalOps.Load(), float64(totalOps.Load())/wall.Seconds(), total2MB.Load())
	fmt.Printf("latency_p50=%s latency_p95=%s latency_p99=%s\n", p50.Round(time.Microsecond), p95.Round(time.Microsecond), p99.Round(time.Microsecond))
	fmt.Printf("benchmark_mem_sys_mb=%.2f benchmark_heap_alloc_mb=%.2f\n", rssMB, heapAllocMB)
	if store != nil {
		pruner.SetUsageSampler(func() int { return 88 })
		state, pruned := pruner.EvaluateNow(time.Now().UTC().Add(200 * time.Hour))
		m := store.Metrics()
		fmt.Printf("stored_bytes=%d total_stored=%d total_acked=%d\n", m.StoredBytes, m.TotalStored, m.TotalAcked)
		fmt.Printf("autopruner_pressure_state=%s pruned_count=%d\n", state, pruned)
	}
}

type benchMailbox struct {
	ID         string `json:"id"`
	ReadToken  string `json:"read_token"`
	WriteToken string `json:"write_token"`
}

func onionTransport(endpoint, socks string) (string, func(*http.Request) (*url.URL, error), error) {
	dest, err := url.Parse(endpoint)
	onionName := regexp.MustCompile(`^[a-z2-7]{56}\.onion$`)
	if err != nil || (dest.Scheme != "http" && dest.Scheme != "https") ||
		!onionName.MatchString(dest.Hostname()) || dest.User != nil ||
		dest.RawQuery != "" || dest.Fragment != "" || (dest.Path != "" && dest.Path != "/") {
		return "", nil, fmt.Errorf("-onion requer a URL raiz de um serviço Onion v3")
	}
	proxyURL, err := url.Parse("socks5h://" + socks)
	if err != nil || proxyURL.User != nil || proxyURL.Port() == "" ||
		proxyURL.Path != "" || proxyURL.RawQuery != "" || proxyURL.Fragment != "" ||
		(proxyURL.Hostname() != "127.0.0.1" && proxyURL.Hostname() != "::1") {
		return "", nil, fmt.Errorf("-socks requer host e porta SOCKS5 em loopback")
	}
	dest.Path = ""
	return dest.String(), http.ProxyURL(proxyURL), nil
}

func loadBenchMailboxes(path string, count int) ([]benchMailbox, error) {
	info, err := os.Stat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 {
		return nil, fmt.Errorf("-credentials requer arquivo privado com modo 0600")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("falha ao ler credenciais de homologação")
	}
	var boxes []benchMailbox
	if err := json.Unmarshal(data, &boxes); err != nil || len(boxes) != count {
		return nil, fmt.Errorf("informe exatamente %d caixas de homologação", count)
	}
	idPattern := regexp.MustCompile(`^[a-zA-Z0-9_-]{3,128}$`)
	seen := make(map[string]bool, count)
	for _, box := range boxes {
		if !idPattern.MatchString(box.ID) || box.ReadToken == "" || seen[box.ID] {
			return nil, fmt.Errorf("cada caixa requer id único e credencial de leitura")
		}
		seen[box.ID] = true
	}
	return boxes, nil
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
