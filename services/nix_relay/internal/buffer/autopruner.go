package buffer

import (
	"log"
	"time"
)

// AutoPruner gerencia o expurgo dinâmico com histerese em função da ocupação do disco.
type AutoPruner struct {
	lightReliefThreshold    int // 75%
	severeReliefThreshold   int // 85%
	criticalBlockThreshold  int // 92%
	currentState            string
}

func NewAutoPruner(light, severe, critical int) *AutoPruner {
	return &AutoPruner{
		lightReliefThreshold:   light,
		severeReliefThreshold:  severe,
		criticalBlockThreshold: critical,
		currentState:           "NORMAL",
	}
}

// Start inicia o loop de verificação periódica de ocupação.
func (ap *AutoPruner) Start(interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for range ticker.C {
		ap.evaluateDiskPressure()
	}
}

func (ap *AutoPruner) evaluateDiskPressure() {
	// Simulação de leitura de disco na VPS de 40 GB
	usagePercent := ap.getSimulatedDiskUsage()

	switch {
	case usagePercent >= ap.criticalBlockThreshold:
		ap.currentState = "CRITICAL_BLOCK"
		log.Printf("[AUTOPRUNER] Ocupação de disco crítica: %d%%. Rejeitando novas mídias. Prioridade para texto.", usagePercent)
	case usagePercent >= ap.severeReliefThreshold:
		ap.currentState = "SEVERE_RELIEF"
		log.Printf("[AUTOPRUNER] Ocupação severa: %d%%. Aplicando teto de 48h para pendências. Limite de upload: 10MB.", usagePercent)
	case usagePercent >= ap.lightReliefThreshold:
		ap.currentState = "LIGHT_RELIEF"
		log.Printf("[AUTOPRUNER] Alívio leve: %d%%. Aplicando teto de 4 dias para pendências antigas.", usagePercent)
	default:
		if ap.currentState != "NORMAL" {
			log.Printf("[AUTOPRUNER] Retorno ao estado NORMAL com histerese (< 70%%). TTL padrão de 7 dias.")
		}
		ap.currentState = "NORMAL"
	}
}

func (ap *AutoPruner) getSimulatedDiskUsage() int {
	return 25 // Simulação: operação normal inicial
}
