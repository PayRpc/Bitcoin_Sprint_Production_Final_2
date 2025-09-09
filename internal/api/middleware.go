// Package api provides HTTP middleware functionality
package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"runtime/debug"
	"strings"

	"github.com/PayRpc/Bitcoin-Sprint/internal/config"
	"go.uber.org/zap"
)

// ===== MIDDLEWARE IMPLEMENTATION =====

// securityMiddleware applies security headers and measures to all requests
func (s *Server) securityMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Set security headers
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("X-XSS-Protection", "1; mode=block")
		w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		w.Header().Set("Content-Security-Policy", "default-src 'self'")

		// Block common web attack paths
		path := strings.ToLower(r.URL.Path)
		if strings.Contains(path, "../") ||
			strings.Contains(path, "..\\") ||
			strings.Contains(path, "/.ht") ||
			strings.Contains(path, "/.git") ||
			strings.Contains(path, "/wp-") ||
			strings.Contains(path, "/.env") {
			http.Error(w, "Not Found", http.StatusNotFound)
			return
		}

		// API Key Authentication for data endpoints
		if s.requiresAuth(r.URL.Path) {
			apiKey := r.Header.Get("X-API-Key")
			if apiKey == "" {
				// Try query parameter as fallback
				apiKey = r.URL.Query().Get("api_key")
			}

			if apiKey == "" {
				s.logger.Warn("Missing API key for protected endpoint",
					zap.String("ip", getClientIP(r)),
					zap.String("path", r.URL.Path),
				)
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusUnauthorized)
				fmt.Fprintf(w, `{"error":"Missing API Key","message":"X-API-Key header is required for this endpoint","request_id":"%s"}`, r.Header.Get("X-Request-ID"))
				return
			}

			// Validate API key (simple validation for soak test)
			if !s.validateAPIKey(apiKey) {
				s.logger.Warn("Invalid API key",
					zap.String("ip", getClientIP(r)),
					zap.String("path", r.URL.Path),
				)
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusForbidden)
				fmt.Fprintf(w, `{"error":"Invalid API Key","message":"The provided API key is not valid","request_id":"%s"}`, r.Header.Get("X-Request-ID"))
				return
			}

			s.logger.Debug("API key validated",
				zap.String("path", r.URL.Path),
				zap.String("ip", getClientIP(r)),
			)
		}

		// Implement rate limiting based on IP (config-driven)
		clientIP := getClientIP(r)
		generalRateLimit := s.cfg.GeneralRateLimit
		if generalRateLimit <= 0 {
			generalRateLimit = 100 // fallback default
		}
		if !s.rateLimiter.Allow(clientIP, float64(generalRateLimit), 1) {
			s.logger.Warn("Rate limit exceeded",
				zap.String("ip", clientIP),
				zap.String("path", r.URL.Path),
			)
			http.Error(w, "Rate limit exceeded", http.StatusTooManyRequests)
			return
		}

		// Proceed with request
		next.ServeHTTP(w, r)
	})
}

// recoveryMiddleware catches panics and returns 500 error
func (s *Server) recoveryMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				stack := debug.Stack()
				s.logger.Error("Panic in handler",
					zap.Any("panic", rec),
					zap.String("stack", string(stack)),
					zap.String("url", r.URL.String()),
					zap.String("method", r.Method),
				)
				http.Error(w, "Internal Server Error", http.StatusInternalServerError)
			}
		}()
		next(w, r)
	}
}

// auth middleware validates API keys and manages rate limiting
func (s *Server) auth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		apiKey := r.Header.Get("X-API-Key")
		if apiKey == "" {
			// Try to get from query param (less secure, but allowed for some endpoints)
			apiKey = r.URL.Query().Get("api_key")
		}

		if apiKey == "" {
			s.logger.Warn("Missing API key",
				zap.String("ip", getClientIP(r)),
				zap.String("path", r.URL.Path),
			)
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		// Validate API key using customer key manager
		customerKey, valid := s.keyManager.ValidateKey(apiKey)
		if !valid {
			// Log failed auth attempts (potential brute force)
			s.logger.Warn("Invalid API key",
				zap.String("ip", getClientIP(r)),
				zap.String("path", r.URL.Path),
				zap.String("user_agent", r.UserAgent()),
			)
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		// Check rate limit based on customer tier
		keyIdentifier := string(customerKey.Hash)
		tierRateLimit := s.getTierRateLimit(customerKey.Tier)
		if !s.rateLimiter.Allow(keyIdentifier, tierRateLimit, 1) {
			s.logger.Warn("Tier rate limit exceeded",
				zap.String("key_hash", customerKey.Hash[:8]),
				zap.String("tier", string(customerKey.Tier)),
				zap.Float64("limit", tierRateLimit),
				zap.String("ip", getClientIP(r)),
				zap.String("path", r.URL.Path),
			)
			http.Error(w, "Rate limit exceeded", http.StatusTooManyRequests)
			return
		}

		// Update key usage statistics
		s.keyManager.UpdateKeyUsage(apiKey, getClientIP(r), r.UserAgent())

		// Add customer tier to request context for handlers to use
		ctx := context.WithValue(r.Context(), "customer_tier", customerKey.Tier)
		r = r.WithContext(ctx)

		// Use custom response writer to ensure status code is always set
		customWriter := &responseWriter{
			ResponseWriter: w,
			statusCode:     http.StatusOK,
		}

		next(customWriter, r)

		// Log request (successful auth)
		s.logger.Debug("Authorized request",
			zap.String("path", r.URL.Path),
			zap.Int("status", customWriter.statusCode),
			zap.String("tier", string(customerKey.Tier)),
			zap.String("key_hash", customerKey.Hash[:8]),
		)
	}
}

// responseWriter is a custom ResponseWriter that tracks status code
type responseWriter struct {
	http.ResponseWriter
	statusCode int
	written    bool
}

// WriteHeader overrides the WriteHeader method to capture status code
func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.written = true
	rw.ResponseWriter.WriteHeader(code)
}

// Write overrides the Write method to track if anything was written
func (rw *responseWriter) Write(data []byte) (int, error) {
	if !rw.written {
		rw.statusCode = http.StatusOK
		rw.written = true
	}
	return rw.ResponseWriter.Write(data)
}

// getTierRateLimit returns the rate limit for a given tier
func (s *Server) getTierRateLimit(tier config.Tier) float64 {
	if s.cfg.RateLimits == nil {
		// Fallback to basic limits if not configured
		switch tier {
		case config.TierFree:
			return 1.0
		case config.TierPro:
			return 10.0
		case config.TierBusiness:
			return 50.0
		case config.TierTurbo:
			return 100.0
		case config.TierEnterprise:
			return 500.0
		default:
			return 1.0
		}
	}

	if tierLimit, exists := s.cfg.RateLimits[tier]; exists {
		return tierLimit.RefillRate
	}

	// Default fallback
	return 1.0
}

// jsonResponse safely writes a JSON response with proper error handling
func (s *Server) jsonResponse(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)

	if err := json.NewEncoder(w).Encode(data); err != nil {
		s.logger.Error("Failed to encode JSON response",
			zap.Error(err),
			zap.Any("data", data),
		)
		// We've already written headers, so we can't change the status code
		// But we can log the error and write a simple error message
		fmt.Fprintf(w, `{"error":"Internal encoding error"}`)
	}
}

// turboJsonResponse Zero-allocation JSON response with pre-allocated buffers
func (s *Server) turboJsonResponse(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)

	// Use pre-allocated encoder for turbo mode to reduce allocations
	if s.cfg.Tier == config.TierTurbo || s.cfg.Tier == config.TierEnterprise {
		s.turboEncodeJSON(w, data)
	} else {
		json.NewEncoder(w).Encode(data)
	}
}

// turboEncodeJSON Zero-allocation JSON encoding for turbo mode
func (s *Server) turboEncodeJSON(w http.ResponseWriter, data interface{}) {
	// Use a custom encoder that minimizes allocations
	encoder := json.NewEncoder(w)
	encoder.SetEscapeHTML(false) // Disable HTML escaping for performance
	encoder.SetIndent("", "")    // Disable indentation for performance

	if err := encoder.Encode(data); err != nil {
		s.logger.Error("Failed to encode JSON response",
			zap.Error(err),
			zap.Any("data", data),
		)
		w.Write([]byte(`{"error":"Internal encoding error"}`))
	}
}

// getClientIP extracts the real client IP from the request
func getClientIP(r *http.Request) string {
	// Check X-Forwarded-For header (most common with proxies/load balancers)
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		// X-Forwarded-For can contain multiple IPs, take the first one
		ips := strings.Split(xff, ",")
		if len(ips) > 0 {
			return strings.TrimSpace(ips[0])
		}
	}

	// Check X-Real-IP header (nginx)
	if xri := r.Header.Get("X-Real-IP"); xri != "" {
		return strings.TrimSpace(xri)
	}

	// Check X-Forwarded header
	if xf := r.Header.Get("X-Forwarded"); xf != "" {
		return strings.TrimSpace(xf)
	}

	// Fall back to RemoteAddr
	ip, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return ip
}

// requiresAuth determines if a path requires API key authentication
func (s *Server) requiresAuth(path string) bool {
	// Public endpoints that don't require auth
	publicPaths := []string{
		"/health",
		"/version",
		"/status",
		"/metrics",
		"/api/simple-signup",
		"/api/signup",
		"/api/entropy", // Public entropy endpoint
	}

	for _, publicPath := range publicPaths {
		if strings.HasPrefix(path, publicPath) {
			return false
		}
	}

	// All other endpoints require authentication
	return true
}

// validateAPIKey validates the provided API key
func (s *Server) validateAPIKey(apiKey string) bool {
	// For soak test, accept any of these keys
	validKeys := []string{
		"bitcoin_sprint_prod_key_123456789",
		"test_api_key_12345",
		"soak_test_key_2025",
		"YmuWANtGBbzJg60CqVSrlxjsF84Xno5fKyPpO3E9DawTL2cI7Mkd1RhQeHZviU", // Generated API key
	}

	for _, validKey := range validKeys {
		if apiKey == validKey {
			return true
		}
	}

	// Also check environment variable for dynamic key
	if envKey := os.Getenv("BITCOIN_SPRINT_API_KEY"); envKey != "" && apiKey == envKey {
		return true
	}

	return false
}
