// Package fastpath provides ultra-low-latency handlers for Bitcoin Sprint.
// These handlers are optimized for 5ms p99 latency in-region.
package fastpath

import (
	"net/http"
	"strconv"
	"sync/atomic"
)

// Snapshot holds an immutable []byte that can be atomically loaded and stored.
type Snapshot struct {
	b atomic.Value // holds []byte
}

// Load returns the current snapshot bytes.
func (s *Snapshot) Load() []byte {
	if v := s.b.Load(); v != nil {
		return v.([]byte)
	}
	return nil
}

// Store atomically replaces the snapshot with p.
// p must be immutable after passing to Store.
func (s *Snapshot) Store(p []byte) {
	s.b.Store(append([]byte(nil), p...)) // ensure immutable copy
}

// NewSnapshot creates a new snapshot with the given initial bytes.
func NewSnapshot(init []byte) *Snapshot {
	var s Snapshot
	s.Store(init)
	return &s
}

// Global snapshots for frequently accessed endpoints
var (
	latestSnap = NewSnapshot([]byte(`{"height":0,"hash":""}`))
	statusSnap = NewSnapshot([]byte(`{"status":"ok","connections":0,"uptime_seconds":0}`))
	
	// Simple atomic counters for metrics
	latestHits uint64
	statusHits uint64
)

// LatestHandler serves pre-encoded JSON for the /latest endpoint.
// Expected p99 ≤ 5ms for in-region clients.
func LatestHandler(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&latestHits, 1)
	
	b := latestSnap.Load()
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Content-Length", strconv.Itoa(len(b)))
	_, _ = w.Write(b) // ~sub-ms on hit
}

// StatusHandler serves pre-encoded JSON for the /status endpoint.
// Expected p99 ≤ 5ms for in-region clients.
func StatusHandler(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&statusHits, 1)
	
	b := statusSnap.Load()
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Content-Length", strconv.Itoa(len(b)))
	_, _ = w.Write(b) // ~sub-ms on hit
}

// GetLatestHits returns the number of hits to the latest endpoint.
func GetLatestHits() uint64 {
	return atomic.LoadUint64(&latestHits)
}

// GetStatusHits returns the number of hits to the status endpoint.
func GetStatusHits() uint64 {
	return atomic.LoadUint64(&statusHits)
}

// RefreshLatest updates the latest snapshot with new data.
// This should be called from a background process, not directly in handlers.
func RefreshLatest(height int64, hash string) {
	b := make([]byte, 0, 96)
	b = append(b, `{"height":`...)
	b = strconv.AppendInt(b, height, 10)
	b = append(b, `,"hash":"`...)
	b = append(b, hash...)
	b = append(b, `"}`...)
	latestSnap.Store(b) // atomic swap
}

// RefreshStatus updates the status snapshot with new data.
// This should be called from a background process, not directly in handlers.
func RefreshStatus(status string, connections int, uptimeSeconds int64) {
	b := make([]byte, 0, 128)
	b = append(b, `{"status":"`...)
	b = append(b, status...)
	b = append(b, `","connections":`...)
	b = strconv.AppendInt(b, int64(connections), 10)
	b = append(b, `,"uptime_seconds":`...)
	b = strconv.AppendInt(b, uptimeSeconds, 10)
	b = append(b, `}`...)
	statusSnap.Store(b) // atomic swap
}
