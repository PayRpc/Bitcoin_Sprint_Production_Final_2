//go:build cgo

package entropy

// Enhanced entropy integration with SecureBuffer FFI
// This connects the entropy package to the full Rust SecureBuffer API

import (
	"github.com/PayRpc/Bitcoin-Sprint/internal/securebuf"
)

// FastEntropyRust returns fast entropy using the full Rust implementation
// func FastEntropyRust() ([]byte, error) {
// 	return securebuf.FastEntropy()
// }

// HybridEntropyRustWithHeaders returns entropy using Bitcoin headers via Rust
func HybridEntropyRustWithHeaders(headers [][]byte) ([]byte, error) {
	return securebuf.HybridEntropy(headers)
}

// SystemFingerprintRust returns hardware fingerprint via Rust
// func SystemFingerprintRust() ([]byte, error) {
// 	return securebuf.SystemFingerprint()
// }

// GetCPUTemperatureRust returns CPU temperature via Rust
// func GetCPUTemperatureRust() (float32, error) {
// 	return securebuf.GetCPUTemperature()
// }

// CreateEntropyBuffer creates a SecureBuffer pre-filled with entropy
func CreateEntropyBuffer(capacity int) (*securebuf.Buffer, error) {
	return securebuf.NewWithFastEntropy(capacity)
}

// CreateSecureBufferWithHeaders creates a SecureBuffer with Bitcoin header entropy
func CreateSecureBufferWithHeaders(capacity int, headers [][]byte) (*securebuf.Buffer, error) {
	return securebuf.NewWithHybridEntropy(capacity, headers)
}

// CreateSecureEnterpriseEntropyBuffer creates an enterprise-grade entropy buffer
func CreateSecureEnterpriseEntropyBuffer(capacity int, level securebuf.SecurityLevel) (*securebuf.EnterpriseBuffer, error) {
	return securebuf.NewWithSecurityLevel(capacity, level)
}

// MixEntropyIntoSecureBuffer mixes new entropy into existing buffer content
func MixEntropyIntoSecureBuffer(buffer *securebuf.Buffer, headers [][]byte) error {
	return buffer.FillWithHybridEntropy(headers)
}
