package buffer

import "time"

// RelayStore abstrai o armazenamento cego de envelopes (em disco ou PostgreSQL).
type RelayStore interface {
	Store(
		mailboxID string,
		payloadB64 string,
		requestedTTLSeconds int64,
		quotaToken string,
		prunerState string,
		now time.Time,
	) (Envelope, error)
	Fetch(mailboxID string, now time.Time) ([]Envelope, error)
	Ack(mailboxID string, ids []string) (int, error)
	SweepExpired(now time.Time, maxAgeCap time.Duration) (int, error)
	ValidateCapability(mailboxID, token string, scope CapabilityScope) bool
	HasExplicitScope(mailboxID string, scope CapabilityScope) bool
	ProvisionCapability(mailboxID, token string, scope CapabilityScope, ttl time.Duration) error
	RevokeCapability(mailboxID, token string) error
	Metrics() StoreMetrics
	Close() error
}
