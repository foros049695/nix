package buffer

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"sync"
	"time"
)

var (
	ErrInvalidMailbox   = errors.New("mailbox_id inválido")
	ErrPayloadTooLarge  = errors.New("payload excede limite máximo permitido")
	ErrQuotaExceeded    = errors.New("cota máxima em trânsito excedida para o token")
	ErrCriticalPressure = errors.New("relay sob pressão crítica de disco: mídias grandes bloqueadas")
	validMailboxRegex   = regexp.MustCompile(`^[a-zA-Z0-9_-]{3,128}$`)
)

// Envelope representa um payload cifrado opaco armazenado em trânsito.
type Envelope struct {
	ID         string `json:"id"`
	PayloadB64 string `json:"payload_b64"`
	CreatedAt  int64  `json:"created_at"`
	ExpiresAt  int64  `json:"expires_at"`
	ByteSize   int64  `json:"byte_size"`
	QuotaToken string `json:"-"`
}

// StoreMetrics resume contadores agregados sem rótulos identificadores.
type StoreMetrics struct {
	ActiveMailboxes int   `json:"active_mailboxes"`
	ActiveEnvelopes int   `json:"active_envelopes"`
	StoredBytes     int64 `json:"stored_bytes"`
	TotalStored     int64 `json:"total_stored"`
	TotalAcked      int64 `json:"total_acked"`
	TotalPruned     int64 `json:"total_pruned"`
}

// BlindMailboxStore mantém caixas postais cegas com persistência opcional em disco e expurgo por TTL.
type BlindMailboxStore struct {
	mu                       sync.RWMutex
	dataDir                  string
	baseTTL                  time.Duration
	maxAttachmentBytes       int64
	maxInFlightPerQuotaToken int64
	mailboxes                map[string][]Envelope
	quotaUsage               map[string]int64
	storedBytes              int64
	totalStored              int64
	totalAcked               int64
	totalPruned              int64
}

func NewBlindMailboxStore(dataDir string, baseTTL time.Duration, maxAttachmentBytes, maxInFlightPerQuotaToken int64) (*BlindMailboxStore, error) {
	if baseTTL <= 0 {
		baseTTL = 7 * 24 * time.Hour
	}
	if maxAttachmentBytes <= 0 {
		maxAttachmentBytes = 52428800
	}
	if maxInFlightPerQuotaToken <= 0 {
		maxInFlightPerQuotaToken = 524288000
	}
	store := &BlindMailboxStore{
		dataDir:                  dataDir,
		baseTTL:                  baseTTL,
		maxAttachmentBytes:       maxAttachmentBytes,
		maxInFlightPerQuotaToken: maxInFlightPerQuotaToken,
		mailboxes:                make(map[string][]Envelope),
		quotaUsage:               make(map[string]int64),
	}
	if dataDir != "" {
		if err := os.MkdirAll(dataDir, 0o700); err != nil {
			return nil, err
		}
		if err := store.loadFromDisk(); err != nil {
			return nil, err
		}
	}
	return store, nil
}

func (s *BlindMailboxStore) Store(
	mailboxID string,
	payloadB64 string,
	requestedTTLSeconds int64,
	quotaToken string,
	prunerState string,
	now time.Time,
) (Envelope, error) {
	if !validMailboxRegex.MatchString(mailboxID) {
		return Envelope{}, ErrInvalidMailbox
	}
	raw, err := base64.StdEncoding.DecodeString(payloadB64)
	if err != nil || len(raw) == 0 {
		return Envelope{}, errors.New("payload_b64 inválido ou vazio")
	}
	byteSize := int64(len(raw))

	effectiveMax := s.maxAttachmentBytes
	if prunerState == StateCriticalBlock {
		// Prioridade de texto em situação crítica: limita uploads acima de 1 MB.
		if byteSize > 1048576 {
			return Envelope{}, ErrCriticalPressure
		}
		effectiveMax = 1048576
	} else if prunerState == StateSevereRelief && effectiveMax > 10485760 {
		effectiveMax = 10485760
	}
	if byteSize > effectiveMax {
		return Envelope{}, ErrPayloadTooLarge
	}

	ttl := s.baseTTL
	if requestedTTLSeconds > 0 && time.Duration(requestedTTLSeconds)*time.Second < ttl {
		ttl = time.Duration(requestedTTLSeconds) * time.Second
	}
	if capDur := MaxTTLForState(prunerState, s.baseTTL); capDur < ttl {
		ttl = capDur
	}

	env := Envelope{
		ID:         randomID(),
		PayloadB64: payloadB64,
		CreatedAt:  now.Unix(),
		ExpiresAt:  now.Add(ttl).Unix(),
		ByteSize:   byteSize,
		QuotaToken: quotaToken,
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	if quotaToken != "" && s.quotaUsage[quotaToken]+byteSize > s.maxInFlightPerQuotaToken {
		return Envelope{}, ErrQuotaExceeded
	}
	if quotaToken != "" {
		s.quotaUsage[quotaToken] += byteSize
	}
	s.mailboxes[mailboxID] = append(s.mailboxes[mailboxID], env)
	s.storedBytes += byteSize
	s.totalStored++
	s.persistMailboxLocked(mailboxID)
	return env, nil
}

func (s *BlindMailboxStore) Fetch(mailboxID string, now time.Time) ([]Envelope, error) {
	if !validMailboxRegex.MatchString(mailboxID) {
		return nil, ErrInvalidMailbox
	}
	s.mu.Lock()
	defer s.mu.Unlock()

	list := s.mailboxes[mailboxID]
	if len(list) == 0 {
		return []Envelope{}, nil
	}

	nowUnix := now.Unix()
	active := make([]Envelope, 0, len(list))
	changed := false
	for _, env := range list {
		if env.ExpiresAt <= nowUnix {
			s.subtractAccountingLocked(env)
			s.totalPruned++
			changed = true
			continue
		}
		active = append(active, env)
	}
	if changed {
		if len(active) == 0 {
			delete(s.mailboxes, mailboxID)
		} else {
			s.mailboxes[mailboxID] = active
		}
		s.persistMailboxLocked(mailboxID)
	}
	out := make([]Envelope, len(active))
	copy(out, active)
	return out, nil
}

func (s *BlindMailboxStore) Ack(mailboxID string, ids []string) (int, error) {
	if !validMailboxRegex.MatchString(mailboxID) {
		return 0, ErrInvalidMailbox
	}
	idSet := make(map[string]struct{}, len(ids))
	for _, id := range ids {
		idSet[id] = struct{}{}
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	list := s.mailboxes[mailboxID]
	if len(list) == 0 {
		return 0, nil
	}
	kept := make([]Envelope, 0, len(list))
	deleted := 0
	for _, env := range list {
		if _, found := idSet[env.ID]; found {
			s.subtractAccountingLocked(env)
			s.totalAcked++
			deleted++
			continue
		}
		kept = append(kept, env)
	}
	if deleted > 0 {
		if len(kept) == 0 {
			delete(s.mailboxes, mailboxID)
		} else {
			s.mailboxes[mailboxID] = kept
		}
		s.persistMailboxLocked(mailboxID)
	}
	return deleted, nil
}

// SweepExpired remove envelopes expirados ou que ultrapassem a idade máxima ditada pela pressão do disco.
func (s *BlindMailboxStore) SweepExpired(now time.Time, maxAgeCap time.Duration) int {
	s.mu.Lock()
	defer s.mu.Unlock()

	nowUnix := now.Unix()
	cutoffCreated := int64(0)
	if maxAgeCap > 0 && maxAgeCap < s.baseTTL {
		cutoffCreated = now.Add(-maxAgeCap).Unix()
	}

	removed := 0
	for mboxID, list := range s.mailboxes {
		kept := make([]Envelope, 0, len(list))
		dirty := false
		for _, env := range list {
			expiredByTTL := env.ExpiresAt <= nowUnix
			expiredByPressure := cutoffCreated > 0 && env.CreatedAt <= cutoffCreated
			if expiredByTTL || expiredByPressure {
				s.subtractAccountingLocked(env)
				s.totalPruned++
				removed++
				dirty = true
				continue
			}
			kept = append(kept, env)
		}
		if dirty {
			if len(kept) == 0 {
				delete(s.mailboxes, mboxID)
			} else {
				s.mailboxes[mboxID] = kept
			}
			s.persistMailboxLocked(mboxID)
		}
	}
	return removed
}

func (s *BlindMailboxStore) Metrics() StoreMetrics {
	s.mu.RLock()
	defer s.mu.RUnlock()

	count := 0
	for _, list := range s.mailboxes {
		count += len(list)
	}
	return StoreMetrics{
		ActiveMailboxes: len(s.mailboxes),
		ActiveEnvelopes: count,
		StoredBytes:     s.storedBytes,
		TotalStored:     s.totalStored,
		TotalAcked:      s.totalAcked,
		TotalPruned:     s.totalPruned,
	}
}

func (s *BlindMailboxStore) subtractAccountingLocked(env Envelope) {
	s.storedBytes -= env.ByteSize
	if s.storedBytes < 0 {
		s.storedBytes = 0
	}
	if env.QuotaToken != "" {
		s.quotaUsage[env.QuotaToken] -= env.ByteSize
		if s.quotaUsage[env.QuotaToken] <= 0 {
			delete(s.quotaUsage, env.QuotaToken)
		}
	}
}

func (s *BlindMailboxStore) persistMailboxLocked(mailboxID string) {
	if s.dataDir == "" {
		return
	}
	path := filepath.Join(s.dataDir, mailboxID+".json")
	list := s.mailboxes[mailboxID]
	if len(list) == 0 {
		_ = os.Remove(path)
		return
	}
	data, err := json.Marshal(list)
	if err != nil {
		return
	}
	tmpPath := path + ".tmp"
	if err := os.WriteFile(tmpPath, data, 0o600); err == nil {
		_ = os.Rename(tmpPath, path)
	}
}

func (s *BlindMailboxStore) loadFromDisk() error {
	entries, err := os.ReadDir(s.dataDir)
	if err != nil {
		return err
	}
	nowUnix := time.Now().Unix()
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".json" {
			continue
		}
		mboxID := entry.Name()[:len(entry.Name())-len(".json")]
		if !validMailboxRegex.MatchString(mboxID) {
			continue
		}
		raw, err := os.ReadFile(filepath.Join(s.dataDir, entry.Name()))
		if err != nil {
			continue
		}
		var list []Envelope
		if err := json.Unmarshal(raw, &list); err != nil {
			continue
		}
		var valid []Envelope
		for _, env := range list {
			if env.ExpiresAt > nowUnix {
				valid = append(valid, env)
				s.storedBytes += env.ByteSize
			}
		}
		if len(valid) > 0 {
			s.mailboxes[mboxID] = valid
		} else {
			_ = os.Remove(filepath.Join(s.dataDir, entry.Name()))
		}
	}
	return nil
}

func randomID() string {
	var b [12]byte
	if _, err := rand.Read(b[:]); err != nil {
		return hex.EncodeToString([]byte(time.Now().Format("150405.000000")))
	}
	return hex.EncodeToString(b[:])
}
