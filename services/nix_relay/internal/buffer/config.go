package buffer

import (
	"bufio"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// Config centraliza os parâmetros operacionais do Nix Relay.
type Config struct {
	ServerHost               string
	ServerPort               int
	OnionServiceHost         string
	DataDir                  string
	PostgresDSN              string
	MaxAttachmentSizeBytes   int64
	MaxInFlightPerQuotaToken int64
	BaseTTLSeconds           int64
	CheckIntervalSeconds     int
	LightThresholdPercent    int
	SevereThresholdPercent   int
	CriticalThresholdPercent int
	MetricsEnabled           bool
	MetricsListenAddr        string
	ZeroIdentifyingLabels    bool
}

// ValidateAdminListenAddr assegura isolamento estrito em loopback para endpoints administrativos e métricas (REL04).
func ValidateAdminListenAddr(addr string) error {
	host, _, err := net.SplitHostPort(strings.TrimSpace(addr))
	if err != nil {
		return errors.New("metrics.listen_addr inválido (esperado host:port)")
	}
	if strings.EqualFold(host, "localhost") {
		return nil
	}
	ip := net.ParseIP(host)
	if ip == nil || !ip.IsLoopback() {
		return errors.New("metrics.listen_addr deve vincular exclusivamente em endereço loopback (127.0.0.1/::1/localhost)")
	}
	return nil
}

// DefaultConfig retorna parâmetros seguros padrão (TTL de 7 dias e histerese 75/85/92).
func DefaultConfig() Config {
	return Config{
		ServerHost:               "127.0.0.1",
		ServerPort:               8080,
		OnionServiceHost:         "",
		DataDir:                  "/var/lib/nix_relay/data",
		MaxAttachmentSizeBytes:   52428800,  // 50 MB
		MaxInFlightPerQuotaToken: 524288000, // 500 MB
		BaseTTLSeconds:           604800,    // 7 dias
		CheckIntervalSeconds:     60,
		LightThresholdPercent:    75,
		SevereThresholdPercent:   85,
		CriticalThresholdPercent: 92,
		MetricsEnabled:           true,
		MetricsListenAddr:        "127.0.0.1:9090",
		ZeroIdentifyingLabels:    true,
	}
}

// LoadYAMLConfig carrega e valida rigorosamente configurações em seções YAML sem dependências externas.
func LoadYAMLConfig(path string) (Config, error) {
	cfg := DefaultConfig()
	f, err := os.Open(path)
	if err != nil {
		return cfg, err
	}
	defer f.Close()

	allowedSections := map[string]bool{
		"server":  true,
		"storage": true,
		"pruning": true,
		"metrics": true,
	}

	allowedKeys := map[string]bool{
		"server.host":                           true,
		"server.port":                           true,
		"server.onion_service_host":             true,
		"storage.base_dir":                      true,
		"storage.postgres_dsn":                  true,
		"storage.max_attachment_size_bytes":     true,
		"storage.max_in_flight_per_quota_token": true,
		"storage.base_ttl_seconds":              true,
		"pruning.check_interval_seconds":        true,
		"pruning.light_threshold_percent":       true,
		"pruning.severe_threshold_percent":      true,
		"pruning.critical_threshold_percent":    true,
		"metrics.enabled":                       true,
		"metrics.listen_addr":                   true,
		"metrics.zero_identifying_labels":       true,
	}

	var section string
	scanner := bufio.NewScanner(f)
	lineNum := 0
	for scanner.Scan() {
		lineNum++
		line := scanner.Text()
		if idx := strings.Index(line, "#"); idx >= 0 {
			line = line[:idx]
		}
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		if strings.HasSuffix(trimmed, ":") && !strings.Contains(trimmed, " ") {
			sec := strings.TrimSuffix(trimmed, ":")
			if !allowedSections[sec] {
				return cfg, fmt.Errorf("linha %d: seção desconhecida no arquivo de configuração: %q", lineNum, sec)
			}
			section = sec
			continue
		}
		colonIdx := strings.Index(trimmed, ":")
		if colonIdx <= 0 {
			return cfg, fmt.Errorf("linha %d: sintaxe YAML inválida: %q", lineNum, trimmed)
		}
		key := strings.TrimSpace(trimmed[:colonIdx])
		val := strings.TrimSpace(trimmed[colonIdx+1:])
		val = strings.Trim(val, `"'`)

		fullKey := section + "." + key
		if !allowedKeys[fullKey] {
			return cfg, fmt.Errorf("linha %d: chave de configuração desconhecida ou inválida: %q", lineNum, fullKey)
		}

		switch fullKey {
		case "server.host":
			if val == "" {
				return cfg, fmt.Errorf("linha %d: server.host não pode ser vazio", lineNum)
			}
			cfg.ServerHost = val
		case "server.port":
			p, err := strconv.Atoi(val)
			if err != nil || p < 1 || p > 65535 {
				return cfg, fmt.Errorf("linha %d: server.port inválido: %q (esperado inteiro entre 1 e 65535)", lineNum, val)
			}
			cfg.ServerPort = p
		case "server.onion_service_host":
			cfg.OnionServiceHost = val
		case "storage.base_dir":
			if val != "" {
				expanded, err := expandBaseDir(val)
				if err != nil {
					return cfg, err
				}
				cfg.DataDir = expanded
			}
		case "storage.postgres_dsn":
			cfg.PostgresDSN = val
		case "storage.max_attachment_size_bytes":
			n, err := strconv.ParseInt(val, 10, 64)
			if err != nil || n <= 0 {
				return cfg, fmt.Errorf("linha %d: storage.max_attachment_size_bytes inválido: %q (esperado inteiro positivo)", lineNum, val)
			}
			cfg.MaxAttachmentSizeBytes = n
		case "storage.max_in_flight_per_quota_token":
			n, err := strconv.ParseInt(val, 10, 64)
			if err != nil || n <= 0 {
				return cfg, fmt.Errorf("linha %d: storage.max_in_flight_per_quota_token inválido: %q (esperado inteiro positivo)", lineNum, val)
			}
			cfg.MaxInFlightPerQuotaToken = n
		case "storage.base_ttl_seconds":
			n, err := strconv.ParseInt(val, 10, 64)
			if err != nil || n <= 0 {
				return cfg, fmt.Errorf("linha %d: storage.base_ttl_seconds inválido: %q (esperado inteiro positivo)", lineNum, val)
			}
			cfg.BaseTTLSeconds = n
		case "pruning.check_interval_seconds":
			n, err := strconv.Atoi(val)
			if err != nil || n <= 0 {
				return cfg, fmt.Errorf("linha %d: pruning.check_interval_seconds inválido: %q (esperado inteiro positivo)", lineNum, val)
			}
			cfg.CheckIntervalSeconds = n
		case "pruning.light_threshold_percent":
			n, err := strconv.Atoi(val)
			if err != nil || n < 1 || n > 100 {
				return cfg, fmt.Errorf("linha %d: pruning.light_threshold_percent inválido: %q (esperado entre 1 e 100)", lineNum, val)
			}
			cfg.LightThresholdPercent = n
		case "pruning.severe_threshold_percent":
			n, err := strconv.Atoi(val)
			if err != nil || n < 1 || n > 100 {
				return cfg, fmt.Errorf("linha %d: pruning.severe_threshold_percent inválido: %q (esperado entre 1 e 100)", lineNum, val)
			}
			cfg.SevereThresholdPercent = n
		case "pruning.critical_threshold_percent":
			n, err := strconv.Atoi(val)
			if err != nil || n < 1 || n > 100 {
				return cfg, fmt.Errorf("linha %d: pruning.critical_threshold_percent inválido: %q (esperado entre 1 e 100)", lineNum, val)
			}
			cfg.CriticalThresholdPercent = n
		case "metrics.enabled":
			b, err := parseStrictBool(val)
			if err != nil {
				return cfg, fmt.Errorf("linha %d: metrics.enabled inválido: %q (esperado true ou false)", lineNum, val)
			}
			cfg.MetricsEnabled = b
		case "metrics.listen_addr":
			if val == "" {
				return cfg, fmt.Errorf("linha %d: metrics.listen_addr não pode ser vazio quando especificado", lineNum)
			}
			if err := ValidateAdminListenAddr(val); err != nil {
				return cfg, fmt.Errorf("linha %d: %w", lineNum, err)
			}
			cfg.MetricsListenAddr = val
		case "metrics.zero_identifying_labels":
			b, err := parseStrictBool(val)
			if err != nil {
				return cfg, fmt.Errorf("linha %d: metrics.zero_identifying_labels inválido: %q (esperado true ou false)", lineNum, val)
			}
			cfg.ZeroIdentifyingLabels = b
		}
	}
	if err := scanner.Err(); err != nil {
		return cfg, err
	}

	// Validação de histerese estrita: 0 < light < severe < critical <= 100
	if !(0 < cfg.LightThresholdPercent && cfg.LightThresholdPercent < cfg.SevereThresholdPercent && cfg.SevereThresholdPercent < cfg.CriticalThresholdPercent && cfg.CriticalThresholdPercent <= 100) {
		return cfg, fmt.Errorf("limiares de poda inconsistentes: light (%d) deve ser < severe (%d) que deve ser < critical (%d)",
			cfg.LightThresholdPercent, cfg.SevereThresholdPercent, cfg.CriticalThresholdPercent)
	}

	if cfg.MetricsEnabled {
		if err := ValidateAdminListenAddr(cfg.MetricsListenAddr); err != nil {
			return cfg, err
		}
	}

	if envDSN := strings.TrimSpace(os.Getenv("NIX_RELAY_PG_DSN")); envDSN != "" {
		cfg.PostgresDSN = envDSN
	}
	return cfg, nil
}

func parseStrictBool(val string) (bool, error) {
	switch strings.ToLower(val) {
	case "true", "yes", "1":
		return true, nil
	case "false", "no", "0":
		return false, nil
	default:
		return false, fmt.Errorf("valor booleano inválido: %q", val)
	}
}

func expandBaseDir(raw string) (string, error) {
	switch {
	case raw == "~":
		return resolveHomeDir("")
	case strings.HasPrefix(raw, "~/"):
		return resolveHomeDir(raw[2:])
	case raw == "$HOME", raw == "${HOME}":
		return resolveHomeDir("")
	case strings.HasPrefix(raw, "$HOME/"):
		return resolveHomeDir(strings.TrimPrefix(raw, "$HOME/"))
	case strings.HasPrefix(raw, "${HOME}/"):
		return resolveHomeDir(strings.TrimPrefix(raw, "${HOME}/"))
	default:
		return raw, nil
	}
}

func resolveHomeDir(rel string) (string, error) {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		if err != nil {
			return "", fmt.Errorf("storage.base_dir requer HOME válido: %w", err)
		}
		return "", fmt.Errorf("storage.base_dir requer HOME válido")
	}
	if rel == "" {
		return home, nil
	}
	return filepath.Join(home, rel), nil
}
