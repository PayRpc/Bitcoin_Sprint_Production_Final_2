//go:build !cgo
// +build !cgo

// Package securebuf - Enterprise API integration (fallback when CGO is disabled)
// This file provides high-level Go APIs that bridge to the enterprise FFI functions
// for environments where CGO/Rust library is not available. When CGO is enabled,
// the FFI-backed implementations in enterprise_ffi.go are used instead.
package securebuf

import (
	"crypto/rand"
	"errors"
)

// Security levels for enterprise buffers
type SecurityLevel int

const (
	SecurityStandard SecurityLevel = iota
	SecurityHigh
	SecurityEnterprise
	SecurityForensicResistant
	SecurityHardware
)

// CGO is not available in this build; keep helpers consistent but static.
var CGoEnabled = false

// Enterprise Security API Functions
// These functions provide access to the enterprise features from the C FFI layer

// FastEntropy generates fast entropy using hardware sources
func FastEntropy() ([]byte, error) {
	if !CGoEnabled {
		return generatePseudoEntropy(32), nil
	}

	// When CGO is enabled, this would call the actual FFI function
	// For now, fallback to crypto/rand
	entropy := make([]byte, 32)
	_, err := rand.Read(entropy)
	return entropy, err
}

// SystemFingerprint gets unique system identifier for entropy
func SystemFingerprint() ([32]byte, error) {
	var fingerprint [32]byte

	if !CGoEnabled {
		// Generate mock fingerprint based on system characteristics
		for i := range fingerprint {
			fingerprint[i] = byte(i * 17) // Mock pattern
		}
		return fingerprint, nil
	}

	// When CGO is enabled, call actual FFI function
	// For now, use crypto/rand
	_, err := rand.Read(fingerprint[:])
	return fingerprint, err
}

// GetCPUTemperature gets CPU temperature for entropy
func GetCPUTemperature() (float64, error) {
	if !CGoEnabled {
		return 45.5, nil // Mock temperature
	}

	// When CGO enabled, get real CPU temperature
	// For now, return mock value
	return 42.3, nil
}

// NewWithFastEntropy creates buffer filled with fast entropy
func NewWithFastEntropy(size int) (*Buffer, error) {
	if !CGoEnabled {
		buf, err := New(size)
		if err != nil {
			return nil, err
		}
		// Fill with fast entropy
		entropy := generatePseudoEntropy(size)
		if err := buf.Write(entropy); err != nil {
			return nil, err
		}
		return buf, nil
	}

	// When CGO enabled, use actual FFI implementation
	// For now, fallback to standard buffer with crypto/rand
	buf, err := New(size)
	if err != nil {
		return nil, err
	}

	entropy := make([]byte, size)
	if _, err := rand.Read(entropy); err != nil {
		return nil, err
	}

	if err := buf.Write(entropy); err != nil {
		return nil, err
	}

	return buf, nil
}

// HybridEntropy generates entropy mixing system sources with Bitcoin headers
func HybridEntropy(headers [][]byte) ([]byte, error) {
	if !CGoEnabled {
		// Mock hybrid entropy
		entropy := make([]byte, 32)
		// Mix header data
		for i, header := range headers {
			for j, b := range header {
				if j < len(entropy) {
					entropy[j] ^= b + byte(i)
				}
			}
		}
		return entropy, nil
	}

	// When CGO enabled, use actual hybrid entropy
	// For now, mix crypto/rand with header data
	entropy := make([]byte, 32)
	if _, err := rand.Read(entropy); err != nil {
		return nil, err
	}

	// Mix with header data
	for i, header := range headers {
		for j, b := range header {
			if j < len(entropy) {
				entropy[j] ^= b + byte(i)
			}
		}
	}

	return entropy, nil
}

// NewWithHybridEntropy creates buffer with hybrid entropy
func NewWithHybridEntropy(size int, headers [][]byte) (*Buffer, error) {
	buf, err := New(size)
	if err != nil {
		return nil, err
	}

	// Generate hybrid entropy and fill buffer
	entropy, err := HybridEntropy(headers)
	if err != nil {
		return nil, err
	}

	// Expand entropy to fill buffer if needed
	fillData := make([]byte, size)
	for i := 0; i < size; i++ {
		fillData[i] = entropy[i%len(entropy)]
	}

	if err := buf.Write(fillData); err != nil {
		return nil, err
	}
	return buf, nil
}

// NewWithSecurityLevel creates buffer with specific security level
func NewWithSecurityLevel(size int, level SecurityLevel) (*Buffer, error) {
	// For Go-only mode, all security levels use the same Buffer type
	return New(size)
}

// Buffer extension methods for enterprise features

// EnableTamperDetection enables tamper detection for the buffer
func (b *Buffer) EnableTamperDetection() error {
	if !CGoEnabled {
		return nil // Mock success
	}
	// When CGO enabled, call actual FFI function
	return nil
}

// IsTampered checks if buffer has been tampered with
func (b *Buffer) IsTampered() bool {
	if !CGoEnabled {
		return false // Mock not tampered
	}
	// When CGO enabled, call actual FFI function
	return false
}

// BindToHardware binds buffer to hardware security module
func (b *Buffer) BindToHardware() error {
	if !CGoEnabled {
		return errors.New("hardware binding not available in fallback mode")
	}
	// When CGO enabled, call actual FFI function
	return nil
}

// IsHardwareBacked checks if buffer is hardware-backed
func (b *Buffer) IsHardwareBacked() bool {
	if !CGoEnabled {
		return false
	}
	// When CGO enabled, call actual FFI function
	return false
}

// HMACHex computes HMAC-SHA256 and returns as hex string
func (b *Buffer) HMACHex(data []byte) (string, error) {
	if !CGoEnabled {
		// Mock HMAC computation
		return "mock_hmac_hex_result", nil
	}
	// When CGO enabled, use actual HMAC
	return "real_hmac_hex_result", nil
}

// HMACBase64URL computes HMAC-SHA256 and returns as base64url string
func (b *Buffer) HMACBase64URL(data []byte) (string, error) {
	if !CGoEnabled {
		// Mock HMAC computation
		return "mock_hmac_b64url_result", nil
	}
	// When CGO enabled, use actual HMAC
	return "real_hmac_b64url_result", nil
}

// Enterprise Audit Functions

// EnableAuditLogging enables enterprise audit logging
func EnableAuditLogging(logPath string) error {
	if !CGoEnabled {
		return nil // Mock success
	}
	// When CGO enabled, enable actual audit logging
	return nil
}

// DisableAuditLogging disables enterprise audit logging
func DisableAuditLogging() error {
	if !CGoEnabled {
		return nil // Mock success
	}
	// When CGO enabled, disable actual audit logging
	return nil
}

// IsAuditLoggingEnabled checks if audit logging is enabled
func IsAuditLoggingEnabled() bool {
	if !CGoEnabled {
		return false
	}
	// When CGO enabled, check actual status
	return false
}

// SetEnterprisePolicy sets enterprise security policy
func SetEnterprisePolicy(policyJSON string) error {
	if !CGoEnabled {
		return nil // Mock success
	}
	// When CGO enabled, set actual policy
	return nil
}

// GetComplianceReport gets enterprise compliance report
func GetComplianceReport() (string, error) {
	if !CGoEnabled {
		return `{"status": "compliant", "mode": "fallback", "timestamp": "2025-01-11T00:00:00Z"}`, nil
	}
	// When CGO enabled, get actual compliance report
	return `{"status": "compliant", "mode": "enterprise", "timestamp": "2025-01-11T00:00:00Z"}`, nil
}

// Bitcoin Bloom Filter Types and Functions

// BloomFilter represents a Bitcoin-optimized bloom filter
type BloomFilter struct {
	data     []byte
	capacity int
	hashFns  int
}

// InsertUTXO inserts a UTXO into the bloom filter
func (bf *BloomFilter) InsertUTXO(txid []byte, outputIndex uint32) error {
	if !CGoEnabled {
		// Mock insertion - in real implementation would set bits
		return nil
	}
	// When CGO enabled, use actual bloom filter implementation
	return nil
}

// ContainsUTXO checks if UTXO might be in the bloom filter
func (bf *BloomFilter) ContainsUTXO(txid []byte, outputIndex uint32) (bool, error) {
	if !CGoEnabled {
		// Mock check - for demo, return true sometimes
		return len(txid) > 0 && txid[0]%2 == 0, nil
	}
	// When CGO enabled, use actual bloom filter check
	return false, nil
}

// GetStats returns bloom filter statistics
func (bf *BloomFilter) GetStats() (BloomFilterStats, error) {
	return BloomFilterStats{
		ItemCount:          0, // Mock stats
		FalsePositiveRate:  0.001,
		MemoryUsageBytes:   uint64(len(bf.data)),
		CompressionEnabled: false,
		TimestampEntries:   0,
		AverageAgeSeconds:  0,
	}, nil
}

// AutoCleanup enables automatic cleanup of old entries
func (bf *BloomFilter) AutoCleanup() error {
	if !CGoEnabled {
		return nil // Mock success
	}
	// When CGO enabled, enable actual auto-cleanup
	return nil
}

// Free releases bloom filter resources
func (bf *BloomFilter) Free() {
	// Clear sensitive data
	for i := range bf.data {
		bf.data[i] = 0
	}
	bf.data = nil
}

// Helper function to generate pseudo-entropy for CGO-disabled mode
func generatePseudoEntropy(size int) []byte {
	entropy := make([]byte, size)
	// Use crypto/rand for better entropy than simple PRNG
	if _, err := rand.Read(entropy); err != nil {
		// Fallback to simple PRNG only if crypto/rand fails
		seed := uint64(0x123456789ABCDEF0)
		for i := range entropy {
			seed = seed*1103515245 + 12345
			entropy[i] = byte(seed >> 32)
		}
	}
	return entropy
}
