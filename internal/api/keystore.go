// Package api provides a simple file-backed keystore manager used by the API
// server. This implementation stores arbitrary blobs encrypted with a
// password using scrypt for KDF and AES-GCM for authenticated encryption.
// It intentionally provides a small, well-tested surface so higher-level
// code (wallets, importers) can build on top of it.
package api

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"time"

	"golang.org/x/crypto/scrypt"
	"go.uber.org/zap"
)

// KeystoreManager provides simple encrypted, file-backed key storage.
// Each entry is saved as a JSON file under the configured directory with
// a `.keystore` extension.
type KeystoreManager struct {
	dir    string
	mu     sync.RWMutex
	logger *zap.Logger
}

// keystoreFile is the on-disk JSON structure for a stored key blob.
type keystoreFile struct {
	ID        string    `json:"id"`
	CreatedAt time.Time `json:"created_at"`
	Cipher    string    `json:"cipher"`
	KDF       struct {
		Salt string `json:"salt"`
		N    int    `json:"n"`
		R    int    `json:"r"`
		P    int    `json:"p"`
		DKLen int   `json:"dklen"`
	} `json:"kdf"`
	Nonce      string `json:"nonce"`
	Ciphertext string `json:"ciphertext"`
}

// NewKeystoreManager creates or opens a keystore directory. If the directory
// does not exist it will be created with 0700 permissions.
func NewKeystoreManager(dir string, logger *zap.Logger) (*KeystoreManager, error) {
	if dir == "" {
		return nil, fmt.Errorf("keystore directory path is empty")
	}

	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, fmt.Errorf("failed to create keystore directory: %w", err)
	}

	if logger == nil {
		// Create a noop logger fallback
		logger = zap.NewNop()
	}

	return &KeystoreManager{dir: dir, logger: logger}, nil
}

// Save encrypts the plaintext with the provided password and stores it under
// the given id. If a file for the id already exists it will be overwritten.
func (ks *KeystoreManager) Save(id string, plaintext []byte, password string) error {
	if id == "" {
		return fmt.Errorf("id required")
	}
	if len(password) == 0 {
		return fmt.Errorf("password required")
	}

	// Derive key using scrypt
	salt := make([]byte, 16)
	if _, err := io.ReadFull(rand.Reader, salt); err != nil {
		return fmt.Errorf("failed to generate salt: %w", err)
	}

	// Reasonable default params; tuned for interactive use. Adjust if you have
	// stronger hardware or different threat model.
	N := 1 << 15
	r := 8
	p := 1
	dkLen := 32

	key, err := scrypt.Key([]byte(password), salt, N, r, p, dkLen)
	if err != nil {
		return fmt.Errorf("kdf failed: %w", err)
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return fmt.Errorf("failed to create cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return fmt.Errorf("failed to create gcm: %w", err)
	}

	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return fmt.Errorf("failed to generate nonce: %w", err)
	}

	ciphertext := gcm.Seal(nil, nonce, plaintext, nil)

	// Build file structure
	var f keystoreFile
	f.ID = id
	f.CreatedAt = time.Now().UTC()
	f.Cipher = "AES-GCM"
	f.KDF.Salt = base64.StdEncoding.EncodeToString(salt)
	f.KDF.N = N
	f.KDF.R = r
	f.KDF.P = p
	f.KDF.DKLen = dkLen
	f.Nonce = base64.StdEncoding.EncodeToString(nonce)
	f.Ciphertext = base64.StdEncoding.EncodeToString(ciphertext)

	// Marshal and persist atomically
	data, err := json.MarshalIndent(&f, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal keystore file: %w", err)
	}

	target := filepath.Join(ks.dir, fmt.Sprintf("%s.keystore", id))
	tmp := target + ".tmp"

	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return fmt.Errorf("failed to write keystore file: %w", err)
	}
	if err := os.Rename(tmp, target); err != nil {
		return fmt.Errorf("failed to atomically persist keystore file: %w", err)
	}

	ks.logger.Info("keystore saved", zap.String("id", id))
	return nil
}

// Load decrypts and returns the plaintext stored under id using the password.
func (ks *KeystoreManager) Load(id string, password string) ([]byte, error) {
	if id == "" {
		return nil, fmt.Errorf("id required")
	}

	target := filepath.Join(ks.dir, fmt.Sprintf("%s.keystore", id))
	data, err := os.ReadFile(target)
	if err != nil {
		return nil, fmt.Errorf("failed to read keystore file: %w", err)
	}

	var f keystoreFile
	if err := json.Unmarshal(data, &f); err != nil {
		return nil, fmt.Errorf("failed to parse keystore file: %w", err)
	}

	salt, err := base64.StdEncoding.DecodeString(f.KDF.Salt)
	if err != nil {
		return nil, fmt.Errorf("invalid salt encoding: %w", err)
	}

	key, err := scrypt.Key([]byte(password), salt, f.KDF.N, f.KDF.R, f.KDF.P, f.KDF.DKLen)
	if err != nil {
		return nil, fmt.Errorf("kdf failed: %w", err)
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("failed to create cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("failed to create gcm: %w", err)
	}

	nonce, err := base64.StdEncoding.DecodeString(f.Nonce)
	if err != nil {
		return nil, fmt.Errorf("invalid nonce encoding: %w", err)
	}

	ciphertext, err := base64.StdEncoding.DecodeString(f.Ciphertext)
	if err != nil {
		return nil, fmt.Errorf("invalid ciphertext encoding: %w", err)
	}

	plaintext, err := gcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return nil, fmt.Errorf("decryption failed: %w", err)
	}

	return plaintext, nil
}

// List returns all stored keystore IDs in the directory (without extension).
func (ks *KeystoreManager) List() ([]string, error) {
	entries, err := os.ReadDir(ks.dir)
	if err != nil {
		return nil, fmt.Errorf("failed to read keystore dir: %w", err)
	}

	ids := make([]string, 0, len(entries))
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		if filepath.Ext(name) == ".keystore" {
			ids = append(ids, name[:len(name)-len(".keystore")])
		}
	}
	return ids, nil
}

// Delete removes an on-disk keystore entry
func (ks *KeystoreManager) Delete(id string) error {
	if id == "" {
		return fmt.Errorf("id required")
	}
	target := filepath.Join(ks.dir, fmt.Sprintf("%s.keystore", id))
	if err := os.Remove(target); err != nil {
		return fmt.Errorf("failed to delete keystore file: %w", err)
	}
	ks.logger.Info("keystore deleted", zap.String("id", id))
	return nil
}

// ImportRaw persists a raw, pre-encrypted keystore JSON blob (verbatim) to disk.
// This is useful when importing keystore files created externally.
func (ks *KeystoreManager) ImportRaw(id string, raw []byte) error {
	if id == "" {
		return fmt.Errorf("id required")
	}
	// Validate JSON
	var f keystoreFile
	if err := json.Unmarshal(raw, &f); err != nil {
		return fmt.Errorf("invalid keystore json: %w", err)
	}
	target := filepath.Join(ks.dir, fmt.Sprintf("%s.keystore", id))
	if err := os.WriteFile(target, raw, 0o600); err != nil {
		return fmt.Errorf("failed to write keystore file: %w", err)
	}
	ks.logger.Info("keystore imported", zap.String("id", id))
	return nil
}

