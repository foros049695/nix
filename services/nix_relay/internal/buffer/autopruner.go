package buffer

import (
	"log"
	"sync"
	"syscall"
	"time"
)

const (
	StateNormal        = "NORMAL"
	StateLightRelief   = "LIGHT_RELIEF"
	StateSevereRelief  = "SEVERE_RELIEF"
	StateCriticalBlock = "CRITICAL_BLOCK"
)

// MaxTTLForState retorna o teto efetivo de retenção compatível com o estado de pressão do disco.
func MaxTTLForState(state string, baseTTL time.Duration) time.Duration {
	switch state {
	case StateCriticalBlock:
		if 24*time.Hour < baseTTL {
			return 24 * time.Hour
		}
	case StateSevereRelief:
		if 48*time.Hour < baseTTL {
			return 48 * time.Hour
		}
	case StateLightRelief:
		if 96*time.Hour < baseTTL {
			return 96 * time.Hour
		}
	}
	return baseTTL
}

// AutoPruner gerencia o expurgo progressivo com histerese conforme ocupação de armazenamento.
type AutoPruner struct {
	mu                     sync.RWMutex
	lightReliefThreshold   int // ex: 75%
	severeReliefThreshold  int // ex: 85%
	criticalBlockThreshold int // ex: 92%
	hysteresisFloor        int // ex: 70%
	currentState           string
	baseTTL                time.Duration
	usageSampler           func() int
	store                  RelayStore
}

func NewAutoPruner(light, severe, critical int) *AutoPruner {
	floor := light - 5
	if floor < 10 {
		floor = 10
	}
	return &AutoPruner{
		lightReliefThreshold:   light,
		severeReliefThreshold:  severe,
		criticalBlockThreshold: critical,
		hysteresisFloor:        floor,
		currentState:           StateNormal,
		baseTTL:                7 * 24 * time.Hour,
		usageSampler:           func() int { return 25 },
	}
}

// AttachDiskMonitor conecta leitura real de ocupação do sistema de arquivos e o RelayStore para expurgo ativo.
func (ap *AutoPruner) AttachDiskMonitor(dataDir string, baseTTL time.Duration, store RelayStore) {
	ap.mu.Lock()
	defer ap.mu.Unlock()
	if baseTTL > 0 {
		ap.baseTTL = baseTTL
	}
	ap.store = store
	if dataDir != "" {
		ap.usageSampler = func() int { return readDiskUsagePercent(dataDir) }
	}
}

// SetUsageSampler permite injetar amostrador determinístico em testes.
func (ap *AutoPruner) SetUsageSampler(fn func() int) {
	ap.mu.Lock()
	defer ap.mu.Unlock()
	ap.usageSampler = fn
}

func (ap *AutoPruner) State() string {
	ap.mu.RLock()
	defer ap.mu.RUnlock()
	return ap.currentState
}

// Start inicia o loop contínuo de verificação e expurgo até o encerramento via canal stop.
func (ap *AutoPruner) Start(interval time.Duration, stop <-chan struct{}) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			ap.EvaluateNow(time.Now().UTC())
		}
	}
}

// EvaluateNow executa uma avaliação síncrona de pressão e aplica expurgo no store conectado.
func (ap *AutoPruner) EvaluateNow(now time.Time) (string, int) {
	ap.mu.Lock()
	usagePercent := ap.usageSampler()
	prev := ap.currentState

	next := prev
	switch {
	case usagePercent >= ap.criticalBlockThreshold:
		next = StateCriticalBlock
	case usagePercent >= ap.severeReliefThreshold:
		if prev != StateCriticalBlock || usagePercent < ap.criticalBlockThreshold-5 {
			next = StateSevereRelief
		}
	case usagePercent >= ap.lightReliefThreshold:
		if prev == StateNormal || usagePercent < ap.severeReliefThreshold-5 || prev == StateLightRelief {
			next = StateLightRelief
		} else if prev == StateCriticalBlock && usagePercent < ap.criticalBlockThreshold-5 {
			next = StateSevereRelief
		}
	case usagePercent >= ap.hysteresisFloor:
		// Banda de histerese inferior: quem vem de estados altos relaxa para LIGHT_RELIEF;
		// quem já está em NORMAL permanece NORMAL.
		if prev != StateNormal {
			next = StateLightRelief
		}
	default:
		next = StateNormal
	}

	if next != prev {
		ap.currentState = next
		log.Printf("[AUTOPRUNER] Transição %s -> %s (uso=%d%%)", prev, next, usagePercent)
	}
	store := ap.store
	baseTTL := ap.baseTTL
	ap.mu.Unlock()

	removed := 0
	if store != nil {
		capDur := MaxTTLForState(next, baseTTL)
		var err error
		removed, err = store.SweepExpired(now, capDur)
		if err != nil {
			// Não registra identificadores de mailbox nem payloads.
			log.Printf("[AUTOPRUNER] Falha de persistência no expurgo; nova tentativa no próximo ciclo")
		}
	}
	return next, removed
}

func readDiskUsagePercent(path string) int {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil || stat.Blocks == 0 {
		return 0
	}
	used := stat.Blocks - stat.Bfree
	pct := int((used * 100) / stat.Blocks)
	if pct < 0 {
		return 0
	}
	if pct > 100 {
		return 100
	}
	return pct
}
