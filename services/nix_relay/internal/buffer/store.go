package buffer

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sync"
	"time"
)

var (
	ErrPersistence      = errors.New("falha de persistência em disco no relay")
	ErrInvalidMailbox   = errors.New("mailbox_id inválido")
	ErrPayloadTooLarge  = errors.New("payload excede limite máximo permitido")
	ErrQuotaExceeded    = errors.New("cota máxima em trânsito excedida para o token")
	ErrCriticalPressure = errors.New("relay sob pressão crítica de disco: mídias grandes bloqueadas")
	legacyReadToken     = regexp.MustCompile(`^read_[0-9a-f]{64}$`)
	validMailboxRegex   = regexp.MustCompile(`^[a-zA-Z0-9_-]{3,128}$`)
)

// Envelope representa um payload cifrado opaco armazenado em trânsito.
type Envelope struct {
	ID         string `json:"id"`
	PayloadB64 string `json:"payload_b64"`
	CreatedAt  int64  `json:"created_at"`
	ExpiresAt  int64  `json:"expires_at"`
	ByteSize   int64  `json:"byte_size"`
	QuotaToken string `json:"quota_token,omitempty"`
}

// CapabilityScope define os escopos de autorização de tokens de acesso cego.
type CapabilityScope string

const (
	ScopeReadAck CapabilityScope = "read_ack"
	ScopeWrite   CapabilityScope = "write"
	ScopeAdmin   CapabilityScope = "admin"
)

// StoreMetrics resume contadores agregados sem rótulos identificadores.
type StoreMetrics struct {
	ActiveMailboxes int   `json:"active_mailboxes"`
	ActiveEnvelopes int   `json:"active_envelopes"`
	StoredBytes     int64 `json:"stored_bytes"`
	TotalStored     int64 `json:"total_stored"`
	TotalAcked      int64 `json:"total_acked"`
	TotalPruned     int64 `json:"total_pruned"`
}

type capabilityRecord struct {
	MailboxID     string          `json:"mailbox_id"`
	Scope         CapabilityScope `json:"scope"`
	TokenHashHex  string          `json:"token_hash_hex"`
	ExpiresAtUnix int64           `json:"expires_at"`
	RevokedAtUnix int64           `json:"revoked_at,omitempty"`
}

// BlindMailboxStore mantém caixas postais cegas com persistência opcional em disco e expurgo por TTL.
type BlindMailboxStore struct {
	mu                       sync.RWMutex
	dataDir                  string
	baseTTL                  time.Duration
	maxAttachmentBytes       int64
	maxInFlightPerQuotaToken int64
	mailboxes                map[string][]Envelope
	capabilities             map[string][]capabilityRecord
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
		capabilities:             make(map[string][]capabilityRecord),
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

func (s *BlindMailboxStore) Close() error {
	return nil
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
	if requestedTTLSeconds > 0 && requestedTTLSeconds <= int64(ttl/time.Second) {
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
	if err := s.persistMailboxLocked(mailboxID); err != nil {
		// Rollback in-memory state on persistence failure (Marco P0-4 / REL01)
		list := s.mailboxes[mailboxID]
		if len(list) > 0 {
			s.mailboxes[mailboxID] = list[:len(list)-1]
		}
		s.storedBytes -= byteSize
		s.totalStored--
		if quotaToken != "" {
			s.quotaUsage[quotaToken] -= byteSize
		}
		return Envelope{}, fmt.Errorf("%w: %v", ErrPersistence, err)
	}
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
	removed := make([]Envelope, 0)
	for _, env := range list {
		if env.ExpiresAt <= nowUnix {
			removed = append(removed, env)
			continue
		}
		active = append(active, env)
	}
	if len(removed) > 0 {
		if err := s.removeEnvelopesLocked(mailboxID, active, removed); err != nil {
			return nil, err
		}
		s.totalPruned += int64(len(removed))
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
	removed := make([]Envelope, 0)
	for _, env := range list {
		if _, found := idSet[env.ID]; found {
			removed = append(removed, env)
			continue
		}
		kept = append(kept, env)
	}
	if len(removed) > 0 {
		if err := s.removeEnvelopesLocked(mailboxID, kept, removed); err != nil {
			return 0, err
		}
		s.totalAcked += int64(len(removed))
	}
	return len(removed), nil
}

// SweepExpired remove envelopes expirados ou que ultrapassem a idade máxima ditada pela pressão do disco.
func (s *BlindMailboxStore) SweepExpired(now time.Time, maxAgeCap time.Duration) (int, error) {
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
		expired := make([]Envelope, 0)
		for _, env := range list {
			expiredByTTL := env.ExpiresAt <= nowUnix
			expiredByPressure := cutoffCreated > 0 && env.CreatedAt <= cutoffCreated
			if expiredByTTL || expiredByPressure {
				expired = append(expired, env)
				continue
			}
			kept = append(kept, env)
		}
		if len(expired) > 0 {
			if err := s.removeEnvelopesLocked(mboxID, kept, expired); err != nil {
				// Mailboxes anteriores já foram confirmadas em disco.
				return removed, err
			}
			removed += len(expired)
			s.totalPruned += int64(len(expired))
		}
	}
	return removed, nil
}

// Confirma a persistência antes de alterar cotas e contadores. A lista original
// permanece intacta para rollback, inclusive quando a mailbox fica vazia.
func (s *BlindMailboxStore) removeEnvelopesLocked(mailboxID string, kept, removed []Envelope) error {
	original := s.mailboxes[mailboxID]
	if len(kept) == 0 {
		delete(s.mailboxes, mailboxID)
	} else {
		s.mailboxes[mailboxID] = kept
	}
	if err := s.persistMailboxLocked(mailboxID); err != nil {
		s.mailboxes[mailboxID] = original
		return fmt.Errorf("%w: %v", ErrPersistence, err)
	}
	for _, env := range removed {
		s.subtractAccountingLocked(env)
	}
	return nil
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

func (s *BlindMailboxStore) persistMailboxLocked(mailboxID string) error {
	if s.dataDir == "" {
		return nil
	}
	path := filepath.Join(s.dataDir, mailboxID+".json")
	list := s.mailboxes[mailboxID]
	if len(list) == 0 {
		err := os.Remove(path)
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	data, err := json.Marshal(list)
	if err != nil {
		return err
	}
	tmpPath := path + ".tmp"
	if err := os.WriteFile(tmpPath, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmpPath, path)
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
				// Reconstrói cotas consumidas em trânsito (Marco P0-4 / REL02)
				if env.QuotaToken != "" {
					s.quotaUsage[env.QuotaToken] += env.ByteSize
				}
			}
		}
		if len(valid) > 0 {
			s.mailboxes[mboxID] = valid
		} else {
			_ = os.Remove(filepath.Join(s.dataDir, entry.Name()))
		}
	}
	return s.loadCapabilitiesLocked()
}

func hashTokenHex(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func (s *BlindMailboxStore) capabilitiesPath() string {
	return filepath.Join(s.dataDir, ".capabilities.json")
}

func (s *BlindMailboxStore) persistCapabilitiesLocked() error {
	if s.dataDir == "" {
		return nil
	}
	var all []capabilityRecord
	for _, list := range s.capabilities {
		all = append(all, list...)
	}
	data, err := json.Marshal(all)
	if err != nil {
		return err
	}
	path := s.capabilitiesPath()
	tmpPath := path + ".tmp"
	if err := os.WriteFile(tmpPath, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmpPath, path)
}

func (s *BlindMailboxStore) loadCapabilitiesLocked() error {
	if s.dataDir == "" {
		return nil
	}
	raw, err := os.ReadFile(s.capabilitiesPath())
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	var all []capabilityRecord
	if err := json.Unmarshal(raw, &all); err != nil {
		return err
	}
	nowUnix := time.Now().UTC().Unix()
	for _, rec := range all {
		if rec.Scope == ScopeWrite || (rec.ExpiresAtUnix > nowUnix && rec.RevokedAtUnix == 0) {
			s.capabilities[rec.MailboxID] = append(s.capabilities[rec.MailboxID], rec)
		}
	}
	return nil
}

// ProvisionCapability registra uma capability com hash SHA-256, escopo explícito e expiração em disco.
func (s *BlindMailboxStore) ProvisionCapability(mailboxID, token string, scope CapabilityScope, ttl time.Duration) error {
	if mailboxID == "" || token == "" {
		return ErrInvalidMailbox
	}
	if ttl <= 0 {
		ttl = 30 * 24 * time.Hour
	}
	s.mu.Lock()
	defer s.mu.Unlock()

	rec := capabilityRecord{
		MailboxID:     mailboxID,
		Scope:         scope,
		TokenHashHex:  hashTokenHex(token),
		ExpiresAtUnix: time.Now().UTC().Add(ttl).Unix(),
	}
	// Atualiza ou insere mantendo imutabilidade de outros tokens
	original, existed := s.capabilities[mailboxID]
	list := append([]capabilityRecord(nil), original...)
	replaced := false
	for i := range list {
		if list[i].TokenHashHex == rec.TokenHashHex {
			if list[i].Scope != scope {
				return errors.New("token já associado a outro escopo")
			}
			list[i] = rec
			replaced = true
			break
		}
	}
	if !replaced {
		list = append(list, rec)
	}
	s.capabilities[mailboxID] = list
	if err := s.persistCapabilitiesLocked(); err != nil {
		if existed {
			s.capabilities[mailboxID] = original
		} else {
			delete(s.capabilities, mailboxID)
		}
		return fmt.Errorf("%w: %v", ErrPersistence, err)
	}
	return nil
}

// RevokeCapability marca um token existente como revogado e persiste o estado em disco.
func (s *BlindMailboxStore) RevokeCapability(mailboxID, token string) error {
	if mailboxID == "" || token == "" {
		return nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()

	targetHash := hashTokenHex(token)
	nowUnix := time.Now().UTC().Unix()
	original, existed := s.capabilities[mailboxID]
	list := append([]capabilityRecord(nil), original...)
	changed := false
	for i := range list {
		if subtleConstantTimeCompare(list[i].TokenHashHex, targetHash) {
			list[i].RevokedAtUnix = nowUnix
			changed = true
		}
	}
	if changed {
		s.capabilities[mailboxID] = list
		if err := s.persistCapabilitiesLocked(); err != nil {
			if existed {
				s.capabilities[mailboxID] = original
			} else {
				delete(s.capabilities, mailboxID)
			}
			return fmt.Errorf("%w: %v", ErrPersistence, err)
		}
	}
	return nil
}

// HasExplicitScope conserva a exigência de escrita após a expiração ou revogação dos tokens.
func (s *BlindMailboxStore) HasExplicitScope(mailboxID string, scope CapabilityScope) bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	nowUnix := time.Now().UTC().Unix()
	for _, rec := range s.capabilities[mailboxID] {
		if rec.Scope == scope && (scope == ScopeWrite || (rec.RevokedAtUnix == 0 && rec.ExpiresAtUnix > nowUnix)) {
			return true
		}
	}
	return false
}

// ValidateCapability valida hash SHA-256, revogação, expiração e escopo do token (Marco P0-4 / SEC01).
func (s *BlindMailboxStore) ValidateCapability(mailboxID, token string, scope CapabilityScope) bool {
	if token == "" || mailboxID == "" || legacyReadToken.MatchString(token) {
		return false
	}
	s.mu.Lock()
	defer s.mu.Unlock()

	nowUnix := time.Now().UTC().Unix()
	tokenHash := hashTokenHex(token)
	records := s.capabilities[mailboxID]
	if len(records) > 0 {
		for _, rec := range records {
			if rec.RevokedAtUnix != 0 || rec.ExpiresAtUnix <= nowUnix {
				continue
			}
			if rec.Scope != scope && rec.Scope != ScopeAdmin {
				continue
			}
			if subtle.ConstantTimeCompare([]byte(rec.TokenHashHex), []byte(tokenHash)) == 1 {
				return true
			}
		}
		return false
	}

	return false
}

func subtleConstantTimeCompare(a, b string) bool {
	if len(a) != len(b) {
		return false
	}
	var res byte
	for i := 0; i < len(a); i++ {
		res |= a[i] ^ b[i]
	}
	return res == 0
}

func randomID() string {
	var b [12]byte
	if _, err := rand.Read(b[:]); err != nil {
		return hex.EncodeToString([]byte(time.Now().Format("150405.000000")))
	}
	return hex.EncodeToString(b[:])
}
