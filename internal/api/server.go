// Package api provides the main HTTP API server for Bitcoin Sprint
package api

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"time"

	"go.uber.org/zap"
)

// ===== ROUTE REGISTRATION =====

// RegisterSprintValueRoutes registers the competitive advantage endpoints
func (s *Server) RegisterSprintValueRoutes() {
	// Universal multi-chain API endpoints demonstrating Sprint's competitive advantages

	// Core value proposition endpoints
	if s.httpMux != nil {
		// Universal chain endpoint - single API for all chains (with auth)
		s.httpMux.HandleFunc("/api/v1/universal/", s.auth(s.universalChainHandler))

		// Performance monitoring endpoints (with auth)
		s.httpMux.HandleFunc("/api/v1/sprint/latency-stats", s.auth(s.latencyStatsHandler))
		s.httpMux.HandleFunc("/api/v1/sprint/cache-stats", s.auth(s.cacheStatsHandler))
		s.httpMux.HandleFunc("/api/v1/sprint/tier-comparison", s.auth(s.tierComparisonHandler))

		// Simple endpoints for inlined components (with auth)
		s.httpMux.HandleFunc("/api/v1/latency", s.auth(s.simpleLatencyHandler))
		s.httpMux.HandleFunc("/api/v1/cache", s.auth(s.simpleCacheHandler))
		s.httpMux.HandleFunc("/api/v1/tiers", s.auth(s.simpleTiersHandler))

		// Value demonstration endpoint (with auth)
		s.httpMux.HandleFunc("/api/v1/sprint/value", s.auth(SprintValueHandler))

		s.logger.Info("Sprint competitive advantage routes registered with authentication",
			zap.String("universal_endpoint", "/api/v1/universal/{chain}/{method}"),
			zap.String("auth_required", "true"),
			zap.String("value_props", "flat_p99,unified_api,predictive_cache,enterprise_tiers"))
	}
}

// ===== SERVER LIFECYCLE METHODS =====

// InitializeEnterpriseManager initializes the enterprise security manager
func (s *Server) InitializeEnterpriseManager() {
	if s.enterpriseManager == nil {
		s.enterpriseManager = NewEnterpriseSecurityManager(s, s.logger)
		s.enterpriseManager.RegisterEnterpriseRoutes()
	}
}

// Run starts the API server and blocks until shutdown
func (s *Server) Run(ctx context.Context) {
	// Set server start time for uptime tracking
	s.startTime = time.Now()

	// Ensure we're using a proper binding address
	if s.cfg.APIHost == "" {
		s.cfg.APIHost = "0.0.0.0" // Default to all interfaces if not specified
		s.logger.Info("No API host specified, defaulting to 0.0.0.0 (all interfaces)")
	}

	addr := fmt.Sprintf("%s:%d", s.cfg.APIHost, s.cfg.APIPort)
	s.logger.Info("Starting API server", zap.String("addr", addr))

	// Debug: Log configuration
	s.logger.Info("API server configuration",
		zap.String("host", s.cfg.APIHost),
		zap.Int("port", s.cfg.APIPort),
		zap.String("full_addr", addr),
		zap.String("version", "2.5.0")) // Add version to logs

	// Check if we're binding to the right interface
	if s.cfg.APIHost == "0.0.0.0" {
		s.logger.Info("Binding to all interfaces (0.0.0.0) - Docker compatible")
	} else if s.cfg.APIHost == "127.0.0.1" {
		s.logger.Warn("Binding to localhost only (127.0.0.1) - not Docker compatible")
	} else {
		s.logger.Info("Binding to specific interface", zap.String("interface", s.cfg.APIHost))
	}

	// Validate port number
	if s.cfg.APIPort <= 0 || s.cfg.APIPort > 65535 {
		s.logger.Error("Invalid port number, must be between 1-65535", zap.Int("port", s.cfg.APIPort))
		return
	}

	// Initialize mux if missing
	if s.httpMux == nil {
		s.logger.Info("HTTP mux was nil, initializing")
		s.httpMux = http.NewServeMux()
		s.logger.Info("HTTP mux initialized")
	} else {
		s.logger.Info("HTTP mux already initialized")
	}

	// Core routes (public)
	s.httpMux.HandleFunc("/health", s.healthHandler)
	s.httpMux.HandleFunc("/version", s.versionHandler)
	s.httpMux.HandleFunc("/status", s.statusHandler)
	s.httpMux.HandleFunc("/metrics", s.metricsHandler)

	// Competitive advantage and universal API routes
	s.RegisterSprintValueRoutes()

	// Chain-aware router (e.g., /v1/btc/latest)
	s.httpMux.HandleFunc("/v1/", s.chainAwareHandler)

	// Enterprise endpoints
	s.InitializeEnterpriseManager()
	if s.enterpriseManager != nil {
		// System
		s.httpMux.HandleFunc("/api/v1/enterprise/system/fingerprint", s.enterpriseManager.handleSystemFingerprint)
		s.httpMux.HandleFunc("/api/v1/enterprise/system/temperature", s.enterpriseManager.handleCPUTemperature)
		// Entropy
		s.httpMux.HandleFunc("/api/v1/enterprise/entropy/fast", s.enterpriseManager.handleFastEntropy)
		s.httpMux.HandleFunc("/api/v1/enterprise/entropy/hybrid", s.enterpriseManager.handleHybridEntropy)
		// Secure buffer
		s.httpMux.HandleFunc("/api/v1/enterprise/buffer/new", s.enterpriseManager.handleNewSecureBuffer)
		// Audit
		s.httpMux.HandleFunc("/api/v1/enterprise/security/audit-status", s.enterpriseManager.handleAuditStatus)
		s.httpMux.HandleFunc("/api/v1/enterprise/security/audit/enable", s.enterpriseManager.handleEnableAudit)
		s.httpMux.HandleFunc("/api/v1/enterprise/security/audit/disable", s.enterpriseManager.handleDisableAudit)
	}

	// Admin keystore endpoints (require admin auth middleware applied by s.auth)
	if s.httpMux != nil {
		s.httpMux.HandleFunc("/api/v1/admin/keystore/list", s.adminOnly(s.keystoreListHandler))
		s.httpMux.HandleFunc("/api/v1/admin/keystore/save", s.adminOnly(s.keystoreSaveHandler))
		s.httpMux.HandleFunc("/api/v1/admin/keystore/load", s.adminOnly(s.keystoreLoadHandler))
		s.httpMux.HandleFunc("/api/v1/admin/keystore/delete", s.adminOnly(s.keystoreDeleteHandler))
		s.httpMux.HandleFunc("/api/v1/admin/keystore/import", s.adminOnly(s.keystoreImportHandler))
	}

	// Wrap with security middleware
	handler := s.securityMiddleware(s.httpMux)
	s.logger.Info("Security middleware applied")

	// Create server with comprehensive configuration for reliable binding and connections
	srvCtx := ctx
	s.srv = &http.Server{
		Addr:              addr,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
		MaxHeaderBytes:    1 << 20, // 1 MB
		// Explicitly set BaseContext to ensure proper context propagation
		BaseContext: func(listener net.Listener) context.Context {
			if srvCtx != nil {
				return srvCtx
			}
			return context.Background()
		},
	}

	s.logger.Info("HTTP server configured with enhanced settings",
		zap.String("addr", addr),
		zap.Duration("read_timeout", 30*time.Second),
		zap.Duration("write_timeout", 60*time.Second))

	// Pre-warm relays to reduce cold-start latency
	go func() {
		// Small delay to ensure server is up
		time.Sleep(200 * time.Millisecond)
		if s.ethereumRelay != nil && !s.ethereumRelay.IsConnected() {
			ctxC, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			if err := s.ethereumRelay.Connect(ctxC); err != nil {
				s.logger.Warn("ETH relay warm-up failed", zap.Error(err))
			} else {
				s.logger.Info("ETH relay pre-warmed")
			}
		}
		if s.solanaRelay != nil && !s.solanaRelay.IsConnected() {
			ctxC, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			if err := s.solanaRelay.Connect(ctxC); err != nil {
				s.logger.Warn("SOL relay warm-up failed", zap.Error(err))
			} else {
				s.logger.Info("SOL relay pre-warmed")
			}
		}

		// Periodic lightweight pings to keep connections hot
		ticker := time.NewTicker(10 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				// Best-effort: query peer counts
				if s.ethereumRelay != nil && s.ethereumRelay.IsConnected() {
					_ = s.ethereumRelay.GetPeerCount()
				}
				if s.solanaRelay != nil && s.solanaRelay.IsConnected() {
					_ = s.solanaRelay.GetPeerCount()
				}
			}
		}
	}()

	// Graceful shutdown watcher
	go func() {
		<-ctx.Done()
		s.logger.Info("Shutdown signal received, stopping HTTP server")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := s.srv.Shutdown(shutdownCtx); err != nil {
			s.logger.Error("HTTP server shutdown error", zap.Error(err))
		}
	}()

	// Only start listening if we created the server ourselves
	s.logger.Info("Starting HTTP server listen", zap.String("addr", addr))

	// Add explicit route logging to verify health endpoint registration
	s.logger.Debug("Registered HTTP routes:",
		zap.String("health", "/health"),
		zap.String("version", "/version"),
		zap.String("status", "/status"),
		zap.String("metrics", "/metrics"),
		zap.String("universal", "/api/v1/universal/*"))

	// Print startup banner before starting server
	fmt.Println("Bitcoin Sprint starting…")
	fmt.Printf(" API:      http://%s\n", addr)
	fmt.Printf(" Metrics:  http://127.0.0.1:%d/metrics\n", s.cfg.PrometheusPort)
	fmt.Println(" PProf:    disabled")
	fmt.Println(" P2P:      enabled (min proto 70016, witness only)")
	fmt.Println(" Workers:  16")
	fmt.Println()

	// Defer diagnostics until after listener is created to avoid false failures

	// Try to listen on the specified port with explicit socket options
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		s.logger.Error("Failed to create listener",
			zap.String("addr", addr),
			zap.Error(err))
		return
	}

	// Set TCP keep-alive to detect dead connections
	if _, ok := listener.(*net.TCPListener); ok {
		s.logger.Info("TCP listener created successfully")
		// Note: Keep-alive settings would require custom implementation
	} else {
		s.logger.Warn("Could not access TCP listener options")
	}

	s.logger.Info("HTTP server listener created successfully", zap.String("addr", addr))

	// Start the HTTP server with our prepared listener
	// Spawn a self-test once the listener is ready
	go func() {
		// Wait a moment to ensure Serve has started accepting
		time.Sleep(500 * time.Millisecond)

		// Create a transport with explicit connection timeout
		transport := &http.Transport{
			DialContext: (&net.Dialer{
				Timeout:   5 * time.Second,
				KeepAlive: 30 * time.Second,
			}).DialContext,
			MaxIdleConns:          100,
			IdleConnTimeout:       90 * time.Second,
			TLSHandshakeTimeout:   5 * time.Second,
			ExpectContinueTimeout: 1 * time.Second,
			ResponseHeaderTimeout: 5 * time.Second,
		}

		client := http.Client{Timeout: 5 * time.Second, Transport: transport}
		localURL := fmt.Sprintf("http://127.0.0.1:%d/health", s.cfg.APIPort)
		bindURL := fmt.Sprintf("http://%s:%d/health", s.cfg.APIHost, s.cfg.APIPort)

		// Try up to 5 times alternating URLs
		for attempt := 0; attempt < 5; attempt++ {
			testURL := localURL
			if attempt >= 3 {
				testURL = bindURL
			}
			s.logger.Info("Attempting self-test HTTP request",
				zap.String("url", testURL),
				zap.Int("attempt", attempt+1))
			resp, err := client.Get(testURL)
			if err == nil {
				resp.Body.Close()
				s.logger.Info("Self-test HTTP request successful",
					zap.String("url", testURL),
					zap.Int("status", resp.StatusCode),
					zap.Int("attempt", attempt+1))
				return
			}
			s.logger.Warn("Self-test HTTP request failed, retrying",
				zap.String("url", testURL),
				zap.Error(err),
				zap.Int("attempt", attempt+1))
			time.Sleep(time.Duration(500*(1<<attempt)) * time.Millisecond)
		}

		// After retries, log a port check
		conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", s.cfg.APIPort), 2*time.Second)
		if err != nil {
			s.logger.Error("TCP connection to local port failed",
				zap.Int("port", s.cfg.APIPort),
				zap.Error(err))
		} else {
			_ = conn.Close()
			s.logger.Info("TCP connection to local port succeeded, HTTP layer issue likely",
				zap.Int("port", s.cfg.APIPort))
		}
	}()

	if err := s.srv.Serve(listener); err != nil && err != http.ErrServerClosed {
		s.logger.Error("HTTP server error", zap.Error(err))
		return
	}

	s.logger.Info("HTTP server shutdown completed", zap.String("addr", addr))
}
