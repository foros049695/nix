package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/projetonix/nix/services/nix_relay/internal/buffer"
)

func main() {
	configPath := flag.String("config", "configs/relay.example.yaml", "Caminho do arquivo de configuração do relay")
	flag.Parse()

	log.Printf("[NIX-RELAY] Inicializando relay transitório (Config: %s)...", *configPath)
	log.Println("[NIX-RELAY] Modo: Store-and-Forward efêmero (TTL base: 7 dias)")
	log.Println("[NIX-RELAY] Zero logs com IPs ou dados pessoais ativos.")

	// Inicializa o AutoPruner com os limiares de histerese
	pruner := buffer.NewAutoPruner(75, 85, 92)
	go pruner.Start(1 * time.Minute)

	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, "OK (Nix Relay v0.1.0-alpha)")
	})

	log.Println("[NIX-RELAY] Servidor escutando em 127.0.0.1:8080 (Aguardando Tor Onion Service)...")
	if err := http.ListenAndServe("127.0.0.1:8080", nil); err != nil {
		log.Fatalf("[NIX-RELAY] Falha no servidor: %v", err)
	}
}
