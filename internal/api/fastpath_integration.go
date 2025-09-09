// Package api provides the main HTTP API server for Bitcoin Sprint
package api

import (
	"context"
	"sync"
	"time"

	"github.com/PayRpc/Bitcoin-Sprint/internal/fastpath"
	"go.uber.org/zap"
)

// FastpathIntegration handles the integration between the API server and the fastpath package
type FastpathIntegration struct {
	server       *Server
	logger       *zap.Logger
	ctx          context.Context
	cancel       context.CancelFunc
	refreshMutex sync.Mutex
	initialized  bool
}

// NewFastpathIntegration creates a new FastpathIntegration
func NewFastpathIntegration(server *Server, logger *zap.Logger) *FastpathIntegration {
	ctx, cancel := context.WithCancel(context.Background())
	return &FastpathIntegration{
		server:       server,
		logger:       logger.Named("fastpath"),
		ctx:          ctx,
		cancel:       cancel,
		refreshMutex: sync.Mutex{},
		initialized:  false,
	}
}

// StartRefreshers starts the background refreshers for fastpath snapshots
func (f *FastpathIntegration) StartRefreshers() {
	f.refreshMutex.Lock()
	defer f.refreshMutex.Unlock()

	if f.initialized {
		f.logger.Warn("Fastpath refreshers already started, ignoring duplicate call")
		return
	}

	f.logger.Info("Starting fastpath integration and background refreshers")

	// Initialize with current data
	f.refreshLatestSnapshot()
	f.refreshStatusSnapshot()

	// Start background refreshers
	go f.runLatestRefresher()
	go f.runStatusRefresher()

	f.initialized = true
	f.logger.Info("Fastpath integration initialized successfully")
}

// Stop stops all background refreshers
func (f *FastpathIntegration) Stop() {
	f.logger.Info("Stopping fastpath integration and background refreshers")
	f.cancel()
}

// refreshLatestSnapshot fetches the latest block and updates the snapshot
func (f *FastpathIntegration) refreshLatestSnapshot() {
	backend, exists := f.server.backends.Get("bitcoin")
	if !exists {
		f.logger.Warn("Bitcoin backend not available for refreshing latest snapshot")
		return
	}

	block, err := backend.GetLatestBlock()
	if err != nil {
		f.logger.Error("Failed to get latest block for snapshot", zap.Error(err))
		return
	}

	// Update the snapshot using direct field access
	fastpath.RefreshLatest(int64(block.Height), block.Hash)
	f.logger.Debug("Updated latest snapshot with direct field access",
		zap.Uint32("height", block.Height),
		zap.String("hash", block.Hash))
}

// refreshStatusSnapshot updates the status snapshot
func (f *FastpathIntegration) refreshStatusSnapshot() {
	// Get current status information
	status := "ok" // Default to ok
	uptime := time.Since(f.server.startTime).Seconds()
	connections := 0

	// Try to get connection count from backend
	backend, exists := f.server.backends.Get("bitcoin")
	if exists {
		// Check if backend has a GetConnectionCount method
		if connGetter, ok := backend.(interface{ GetConnectionCount() (int, error) }); ok {
			count, err := connGetter.GetConnectionCount()
			if err == nil {
				connections = count
			} else {
				f.logger.Debug("Failed to get connection count", zap.Error(err))
			}
		}
	}

	// Check system health
	if !f.server.IsHealthy() {
		status = "degraded"
	}

	// Update the snapshot
	fastpath.RefreshStatus(status, connections, int64(uptime))
	f.logger.Debug("Updated status snapshot",
		zap.String("status", status),
		zap.Int("connections", connections),
		zap.Float64("uptime_seconds", uptime))
}

// runLatestRefresher runs a loop that refreshes the latest snapshot periodically
func (f *FastpathIntegration) runLatestRefresher() {
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			f.refreshLatestSnapshot()
		case <-f.ctx.Done():
			f.logger.Info("Latest snapshot refresher stopped")
			return
		}
	}
}

// runStatusRefresher runs a loop that refreshes the status snapshot periodically
func (f *FastpathIntegration) runStatusRefresher() {
	ticker := time.NewTicker(5 * time.Second) // Status doesn't need to be refreshed as often
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			f.refreshStatusSnapshot()
		case <-f.ctx.Done():
			f.logger.Info("Status snapshot refresher stopped")
			return
		}
	}
}
