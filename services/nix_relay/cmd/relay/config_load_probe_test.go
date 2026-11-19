package main

import (
	"context"
	"flag"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestExplicitConfigFailureProbe(t *testing.T) {
	for _, scenario := range []string{"missing", "invalid", "empty"} {
		t.Run(scenario, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "relay.yaml")
			if scenario == "invalid" {
				if err := os.WriteFile(path, []byte(strings.Repeat("x", 70*1024)), 0600); err != nil {
					t.Fatal(err)
				}
			}
			if scenario == "empty" {
				path = ""
			}
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			cmd := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestConfigStartupHelper$")
			cmd.Env = append(os.Environ(), "NIX_CONFIG_PROBE=1", "NIX_CONFIG_PATH="+path)
			out, err := cmd.CombinedOutput()
			if ctx.Err() != nil {
				t.Fatalf("relay did not reject config before starting: %s", out)
			}
			if err == nil || !strings.Contains(string(out), "Erro ao carregar configuração") {
				t.Fatalf("expected explicit configuration error and nonzero exit, got %v: %s", err, out)
			}
			if strings.Contains(string(out), "armazenamento") || strings.Contains(string(out), "Listener") {
				t.Fatalf("relay initialized services after config failure: %s", out)
			}
		})
	}
}

func TestConfigStartupHelper(t *testing.T) {
	if os.Getenv("NIX_CONFIG_PROBE") != "1" {
		return
	}
	flag.CommandLine = flag.NewFlagSet("relay", flag.ExitOnError)
	os.Args = []string{"relay", "-config", os.Getenv("NIX_CONFIG_PATH")}
	main()
}
