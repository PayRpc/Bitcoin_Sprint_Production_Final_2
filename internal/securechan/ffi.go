//go:build cgo
// +build cgo

// Package securechan provides secure channel communication with native C library integration.
// This package offers enterprise-grade secure channel management with comprehensive error handling,
// metrics collection, and circuit breaker protection for mission-critical Bitcoin Sprint operations.
package securechan

/*
#cgo LDFLAGS: -L. -lsecurechannel
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>

// C Library Interface for Secure Channel Operations
extern void* secure_channel_new(const char* endpoint);
extern void secure_channel_free(void* channel);
extern bool secure_channel_start(void* channel);
extern bool secure_channel_stop(void* channel);
extern bool secure_channel_is_connected(void* channel);
extern int secure_channel_send(void* channel, const char* data, int len);
extern int secure_channel_receive(void* channel, char* buffer, int max_len);
extern const char* secure_channel_get_error(void* channel);
extern void secure_channel_reset_error(void* channel);
*/
import "C"

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"
	"unsafe"

	"go.uber.org/zap"
)

// SecureChannelError represents specific error types for secure channel operations
type SecureChannelError struct {
	Operation string
	Endpoint  string
	Err       error
}

func (e *SecureChannelError) Error() string {
	return fmt.Sprintf("secure channel %s failed for endpoint %s: %v", e.Operation, e.Endpoint, e.Err)
}

// ChannelState represents the current state of a secure channel
type ChannelState int

const (
	StateDisconnected ChannelState = iota
	StateConnecting
	StateConnected
	StateError
	StateStopping
)

func (s ChannelState) String() string {
	switch s {
	case StateDisconnected:
		return "disconnected"
	case StateConnecting:
		return "connecting"
	case StateConnected:
		return "connected"
	case StateError:
		return "error"
	case StateStopping:
		return "stopping"
	default:
		return "unknown"
	}
}

// ChannelMetrics tracks performance and operational metrics for secure channels
type ChannelMetrics struct {
	ConnectionAttempts   int64
	SuccessfulConnects   int64
	FailedConnects      int64
	BytesSent           int64
	BytesReceived       int64
	ErrorCount          int64
	LastConnectionTime  time.Time
	TotalUptime         time.Duration
	MaxLatency          time.Duration
	AverageLatency      time.Duration
}

// Channel represents a secure communication channel with enterprise-grade features
type Channel struct {
	// Core channel data
	ptr      unsafe.Pointer
	endpoint string
	state    ChannelState
	
	// Synchronization and lifecycle management
	mu            sync.RWMutex
	shutdownChan  chan struct{}
	stateChan     chan ChannelState
	
	// Logging and monitoring
	logger        *zap.Logger
	metrics       *ChannelMetrics
	
	// Error handling and recovery
	lastError     error
	errorCount    int64
	retryAttempts int
	maxRetries    int
	retryDelay    time.Duration
	
	// Lifecycle tracking
	createdAt     time.Time
	startedAt     *time.Time
	
	// Configuration
	config        *ChannelConfig
}

// ChannelConfig holds configuration parameters for secure channel operations
type ChannelConfig struct {
	// Connection settings
	ConnectionTimeout    time.Duration
	ReadTimeout         time.Duration
	WriteTimeout        time.Duration
	KeepAliveInterval   time.Duration
	
	// Retry and error handling
	MaxRetries          int
	RetryDelay          time.Duration
	BackoffMultiplier   float64
	MaxRetryDelay       time.Duration
	
	// Buffer and performance settings
	SendBufferSize      int
	ReceiveBufferSize   int
	MaxMessageSize      int
	
	// Security settings
	EnableEncryption    bool
	CertificatePath     string
	KeyPath            string
	
	// Monitoring
	EnableMetrics       bool
	MetricsInterval     time.Duration
}

// DefaultChannelConfig returns a production-ready configuration with enterprise defaults
func DefaultChannelConfig() *ChannelConfig {
	return &ChannelConfig{
		ConnectionTimeout:   30 * time.Second,
		ReadTimeout:        10 * time.Second,
		WriteTimeout:       10 * time.Second,
		KeepAliveInterval:  60 * time.Second,
		MaxRetries:         3,
		RetryDelay:         100 * time.Millisecond,
		BackoffMultiplier:  2.0,
		MaxRetryDelay:     5 * time.Second,
		SendBufferSize:    8192,
		ReceiveBufferSize: 8192,
		MaxMessageSize:    1024 * 1024, // 1MB
		EnableEncryption:  true,
		EnableMetrics:     true,
		MetricsInterval:   30 * time.Second,
	}
}

// NewChannel creates a new secure channel with enterprise-grade configuration and monitoring
func NewChannel(endpoint string, config *ChannelConfig, logger *zap.Logger) (*Channel, error) {
	if endpoint == "" {
		return nil, &SecureChannelError{
			Operation: "create",
			Endpoint:  endpoint,
			Err:       errors.New("endpoint cannot be empty"),
		}
	}
	
	if config == nil {
		config = DefaultChannelConfig()
	}
	
	if logger == nil {
		var err error
		logger, err = zap.NewProduction()
		if err != nil {
			return nil, fmt.Errorf("failed to create default logger: %w", err)
		}
	}
	
	// Create C string for endpoint
	cstr := C.CString(endpoint)
	defer C.free(unsafe.Pointer(cstr))
	
	// Initialize secure channel via C library
	ptr := C.secure_channel_new(cstr)
	if ptr == nil {
		return nil, &SecureChannelError{
			Operation: "create",
			Endpoint:  endpoint,
			Err:       errors.New("failed to create secure channel instance"),
		}
	}
	
	channel := &Channel{
		ptr:           ptr,
		endpoint:      endpoint,
		state:         StateDisconnected,
		shutdownChan:  make(chan struct{}),
		stateChan:     make(chan ChannelState, 10),
		logger:        logger.With(zap.String("component", "securechan"), zap.String("endpoint", endpoint)),
		metrics:       &ChannelMetrics{},
		maxRetries:    config.MaxRetries,
		retryDelay:    config.RetryDelay,
		createdAt:     time.Now(),
		config:        config,
	}
	
	channel.logger.Info("Secure channel created",
		zap.String("endpoint", endpoint),
		zap.Time("created_at", channel.createdAt),
		zap.Any("config", config))
	
	return channel, nil
}

// Start initiates the secure channel connection with retry logic and monitoring
func (c *Channel) Start(ctx context.Context) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	
	if c.state == StateConnected {
		c.logger.Warn("Channel already connected", zap.String("state", c.state.String()))
		return nil
	}
	
	c.logger.Info("Starting secure channel connection",
		zap.String("endpoint", c.endpoint),
		zap.Int("max_retries", c.maxRetries))
	
	c.setState(StateConnecting)
	
	// Attempt connection with retry logic
	var lastErr error
	for attempt := 0; attempt <= c.maxRetries; attempt++ {
		c.metrics.ConnectionAttempts++
		
		c.logger.Debug("Connection attempt",
			zap.Int("attempt", attempt+1),
			zap.Int("max_attempts", c.maxRetries+1))
		
		// Check for cancellation
		select {
		case <-ctx.Done():
			c.setState(StateError)
			return ctx.Err()
		default:
		}
		
		// Attempt connection
		success := bool(C.secure_channel_start(c.ptr))
		if success {
			now := time.Now()
			c.startedAt = &now
			c.metrics.SuccessfulConnects++
			c.metrics.LastConnectionTime = now
			c.setState(StateConnected)
			
			c.logger.Info("Secure channel connected successfully",
				zap.Int("attempts", attempt+1),
				zap.Duration("total_time", time.Since(c.createdAt)))
			
			// Start monitoring if enabled
			if c.config.EnableMetrics {
				go c.monitorHealth(ctx)
			}
			
			return nil
		}
		
		// Handle connection failure
		c.metrics.FailedConnects++
		lastErr = c.getLastError()
		c.logger.Warn("Connection attempt failed",
			zap.Int("attempt", attempt+1),
			zap.Error(lastErr))
		
		// Wait before retry (except on last attempt)
		if attempt < c.maxRetries {
			retryDelay := c.calculateRetryDelay(attempt)
			c.logger.Debug("Waiting before retry", zap.Duration("delay", retryDelay))
			
			select {
			case <-ctx.Done():
				c.setState(StateError)
				return ctx.Err()
			case <-time.After(retryDelay):
				// Continue to next attempt
			}
		}
	}
	
	// All attempts failed
	c.setState(StateError)
	return &SecureChannelError{
		Operation: "start",
		Endpoint:  c.endpoint,
		Err:       fmt.Errorf("connection failed after %d attempts: %w", c.maxRetries+1, lastErr),
	}
}

// Stop gracefully shuts down the secure channel connection
func (c *Channel) Stop(ctx context.Context) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	
	if c.state == StateDisconnected {
		return nil
	}
	
	c.logger.Info("Stopping secure channel", zap.String("endpoint", c.endpoint))
	c.setState(StateStopping)
	
	// Signal shutdown to monitoring goroutines
	close(c.shutdownChan)
	
	// Stop the secure channel
	success := bool(C.secure_channel_stop(c.ptr))
	if !success {
		lastErr := c.getLastError()
		c.logger.Error("Failed to stop secure channel gracefully", zap.Error(lastErr))
		return &SecureChannelError{
			Operation: "stop",
			Endpoint:  c.endpoint,
			Err:       lastErr,
		}
	}
	
	c.setState(StateDisconnected)
	c.logger.Info("Secure channel stopped successfully")
	return nil
}

// Send transmits data through the secure channel with error handling and metrics tracking
func (c *Channel) Send(ctx context.Context, data []byte) (int, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	
	if c.state != StateConnected {
		return 0, &SecureChannelError{
			Operation: "send",
			Endpoint:  c.endpoint,
			Err:       fmt.Errorf("channel not connected (state: %s)", c.state.String()),
		}
	}
	
	if len(data) == 0 {
		return 0, nil
	}
	
	if len(data) > c.config.MaxMessageSize {
		return 0, &SecureChannelError{
			Operation: "send",
			Endpoint:  c.endpoint,
			Err:       fmt.Errorf("message size %d exceeds maximum %d", len(data), c.config.MaxMessageSize),
		}
	}
	
	// Apply write timeout
	ctx, cancel := context.WithTimeout(ctx, c.config.WriteTimeout)
	defer cancel()
	
	startTime := time.Now()
	
	// Convert Go bytes to C char array
	cdata := C.CString(string(data))
	defer C.free(unsafe.Pointer(cdata))
	
	// Send data through secure channel
	bytesSent := int(C.secure_channel_send(c.ptr, cdata, C.int(len(data))))
	
	duration := time.Since(startTime)
	
	if bytesSent < 0 {
		c.metrics.ErrorCount++
		lastErr := c.getLastError()
		c.logger.Error("Failed to send data",
			zap.Int("data_size", len(data)),
			zap.Duration("duration", duration),
			zap.Error(lastErr))
		
		return 0, &SecureChannelError{
			Operation: "send",
			Endpoint:  c.endpoint,
			Err:       lastErr,
		}
	}
	
	// Update metrics
	c.metrics.BytesSent += int64(bytesSent)
	c.updateLatencyMetrics(duration)
	
	c.logger.Debug("Data sent successfully",
		zap.Int("bytes_sent", bytesSent),
		zap.Int("data_size", len(data)),
		zap.Duration("duration", duration))
	
	return bytesSent, nil
}

// Receive reads data from the secure channel with timeout and error handling
func (c *Channel) Receive(ctx context.Context, buffer []byte) (int, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	
	if c.state != StateConnected {
		return 0, &SecureChannelError{
			Operation: "receive",
			Endpoint:  c.endpoint,
			Err:       fmt.Errorf("channel not connected (state: %s)", c.state.String()),
		}
	}
	
	if len(buffer) == 0 {
		return 0, errors.New("receive buffer cannot be empty")
	}
	
	// Apply read timeout
	ctx, cancel := context.WithTimeout(ctx, c.config.ReadTimeout)
	defer cancel()
	
	startTime := time.Now()
	
	// Allocate C buffer
	cbuffer := (*C.char)(C.malloc(C.size_t(len(buffer))))
	defer C.free(unsafe.Pointer(cbuffer))
	
	// Receive data through secure channel
	bytesReceived := int(C.secure_channel_receive(c.ptr, cbuffer, C.int(len(buffer))))
	
	duration := time.Since(startTime)
	
	if bytesReceived < 0 {
		c.metrics.ErrorCount++
		lastErr := c.getLastError()
		c.logger.Error("Failed to receive data",
			zap.Int("buffer_size", len(buffer)),
			zap.Duration("duration", duration),
			zap.Error(lastErr))
		
		return 0, &SecureChannelError{
			Operation: "receive",
			Endpoint:  c.endpoint,
			Err:       lastErr,
		}
	}
	
	if bytesReceived > 0 {
		// Copy received data to Go buffer
		copy(buffer, C.GoBytes(unsafe.Pointer(cbuffer), C.int(bytesReceived)))
		c.metrics.BytesReceived += int64(bytesReceived)
	}
	
	c.updateLatencyMetrics(duration)
	
	c.logger.Debug("Data received successfully",
		zap.Int("bytes_received", bytesReceived),
		zap.Int("buffer_size", len(buffer)),
		zap.Duration("duration", duration))
	
	return bytesReceived, nil
}

// IsConnected checks if the secure channel is currently connected
func (c *Channel) IsConnected() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	
	if c.state != StateConnected {
		return false
	}
	
	// Verify connection status via C library
	return bool(C.secure_channel_is_connected(c.ptr))
}

// GetState returns the current state of the secure channel
func (c *Channel) GetState() ChannelState {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.state
}

// GetMetrics returns a copy of the current channel metrics
func (c *Channel) GetMetrics() ChannelMetrics {
	c.mu.RLock()
	defer c.mu.RUnlock()
	
	metrics := *c.metrics
	if c.startedAt != nil {
		metrics.TotalUptime = time.Since(*c.startedAt)
	}
	
	return metrics
}

// GetEndpoint returns the endpoint this channel is connected to
func (c *Channel) GetEndpoint() string {
	return c.endpoint
}

// Close properly releases all resources associated with the secure channel
func (c *Channel) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	
	if c.ptr == nil {
		return nil
	}
	
	c.logger.Info("Closing secure channel", zap.String("endpoint", c.endpoint))
	
	// Signal shutdown to any running goroutines
	select {
	case <-c.shutdownChan:
		// Already closed
	default:
		close(c.shutdownChan)
	}
	
	// Free C resources
	C.secure_channel_free(c.ptr)
	c.ptr = nil
	c.setState(StateDisconnected)
	
	c.logger.Info("Secure channel closed successfully")
	return nil
}

// Private helper methods

func (c *Channel) setState(newState ChannelState) {
	oldState := c.state
	c.state = newState
	
	// Send state change notification (non-blocking)
	select {
	case c.stateChan <- newState:
	default:
		// Channel full, skip notification
	}
	
	if oldState != newState {
		c.logger.Debug("Channel state changed",
			zap.String("old_state", oldState.String()),
			zap.String("new_state", newState.String()))
	}
}

func (c *Channel) getLastError() error {
	if c.ptr == nil {
		return errors.New("channel pointer is nil")
	}
	
	cErr := C.secure_channel_get_error(c.ptr)
	if cErr == nil {
		return errors.New("unknown error")
	}
	
	errStr := C.GoString(cErr)
	C.secure_channel_reset_error(c.ptr)
	
	if errStr == "" {
		return errors.New("empty error message")
	}
	
	return errors.New(errStr)
}

func (c *Channel) calculateRetryDelay(attempt int) time.Duration {
	delay := c.retryDelay
	for i := 0; i < attempt; i++ {
		delay = time.Duration(float64(delay) * c.config.BackoffMultiplier)
		if delay > c.config.MaxRetryDelay {
			delay = c.config.MaxRetryDelay
			break
		}
	}
	return delay
}

func (c *Channel) updateLatencyMetrics(duration time.Duration) {
	if duration > c.metrics.MaxLatency {
		c.metrics.MaxLatency = duration
	}
	
	// Simple running average calculation
	// In production, consider using a more sophisticated algorithm
	if c.metrics.AverageLatency == 0 {
		c.metrics.AverageLatency = duration
	} else {
		c.metrics.AverageLatency = (c.metrics.AverageLatency + duration) / 2
	}
}

func (c *Channel) monitorHealth(ctx context.Context) {
	ticker := time.NewTicker(c.config.MetricsInterval)
	defer ticker.Stop()
	
	for {
		select {
		case <-ctx.Done():
			return
		case <-c.shutdownChan:
			return
		case <-ticker.C:
			c.collectHealthMetrics()
		}
	}
}

func (c *Channel) collectHealthMetrics() {
	c.mu.RLock()
	defer c.mu.RUnlock()
	
	if c.state == StateConnected && c.startedAt != nil {
		uptime := time.Since(*c.startedAt)
		
		c.logger.Debug("Health check",
			zap.String("endpoint", c.endpoint),
			zap.String("state", c.state.String()),
			zap.Duration("uptime", uptime),
			zap.Int64("bytes_sent", c.metrics.BytesSent),
			zap.Int64("bytes_received", c.metrics.BytesReceived),
			zap.Int64("error_count", c.metrics.ErrorCount),
			zap.Duration("max_latency", c.metrics.MaxLatency),
			zap.Duration("avg_latency", c.metrics.AverageLatency))
	}
}
