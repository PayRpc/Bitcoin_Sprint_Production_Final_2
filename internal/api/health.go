// Package api provides the main HTTP API server for Bitcoin Sprint
package api

// IsHealthy returns whether the server is in a healthy state
func (s *Server) IsHealthy() bool {
	// Check backend health
	backend, exists := s.backends.Get("bitcoin")
	if !exists {
		s.logger.Warn("Bitcoin backend not available for health check")
		return false
	}

	// Check if the backend has a health method
	if healthChecker, ok := backend.(interface{ IsHealthy() bool }); ok {
		if !healthChecker.IsHealthy() {
			s.logger.Warn("Bitcoin backend reports unhealthy state")
			return false
		}
	}

	// Check circuit breaker if exists
	if s.circuitBreaker != nil && s.circuitBreaker.IsTripped() {
		s.logger.Warn("Circuit breaker is tripped")
		return false
	}

	// Everything seems ok
	return true
}
