package main

import (
"encoding/json"
"fmt"
"log"
"net/http"
"os"
"time"

"github.com/google/uuid"
)

type SecretRequest struct {
Key   string `json:"key"`
Value string `json:"value"`
}

type ServiceKeyRequest struct {
ServiceName string `json:"service_name"`
}

type ServiceKeyResponse struct {
ServiceKey string `json:"service_key"`
ExpiresAt  string `json:"expires_at"`
}

type SecretResponse struct {
Value     string `json:"value"`
Retrieved bool   `json:"retrieved"`
}

func main() {
port := os.Getenv("SECURE_BUFFER_PORT")
if port == "" {
port = "8081"
}

http.HandleFunc("/v1/secrets", handleSecrets)
http.HandleFunc("/v1/service-keys", handleServiceKeys)
http.HandleFunc("/health", handleHealth)

fmt.Printf("SecureBuffer service starting on port %s...\n", port)
log.Printf("SecureBuffer service listening on :%s", port)

if err := http.ListenAndServe(":"+port, nil); err != nil {
log.Fatal("SecureBuffer service failed to start:", err)
}
}

func handleSecrets(w http.ResponseWriter, r *http.Request) {
w.Header().Set("Content-Type", "application/json")

switch r.Method {
case "POST":
handleStoreSecret(w, r)
case "GET":
handleRetrieveSecret(w, r)
default:
http.Error(w, `{"error":"Method not allowed"}`, http.StatusMethodNotAllowed)
}
}

func handleStoreSecret(w http.ResponseWriter, r *http.Request) {
var req SecretRequest
if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
http.Error(w, `{"error":"Invalid JSON"}`, http.StatusBadRequest)
return
}

log.Printf("Storing secret for key: %s", req.Key)

response := map[string]string{
"status": "stored",
"key":    req.Key,
}
json.NewEncoder(w).Encode(response)
}

func handleRetrieveSecret(w http.ResponseWriter, r *http.Request) {
key := r.URL.Query().Get("key")
if key == "" {
http.Error(w, `{"error":"Missing key parameter"}`, http.StatusBadRequest)
return
}

response := SecretResponse{
Value:     "FjRGhy7rHUzANAuLTvoEkkST5sJ2f9xNgZ49LLZFVHY=",
Retrieved: true,
}
json.NewEncoder(w).Encode(response)
}

func handleServiceKeys(w http.ResponseWriter, r *http.Request) {
if r.Method != "POST" {
http.Error(w, `{"error":"Method not allowed"}`, http.StatusMethodNotAllowed)
return
}

var req ServiceKeyRequest
if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
http.Error(w, `{"error":"Invalid JSON"}`, http.StatusBadRequest)
return
}

serviceKey := uuid.New().String()
expiresAt := time.Now().Add(24 * time.Hour).Format(time.RFC3339)

response := ServiceKeyResponse{
ServiceKey: serviceKey,
ExpiresAt:  expiresAt,
}

log.Printf("Generated service key for %s: %s", req.ServiceName, serviceKey)
json.NewEncoder(w).Encode(response)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
w.Header().Set("Content-Type", "application/json")
response := map[string]string{
"status": "healthy",
"service": "SecureBuffer",
"time": time.Now().Format(time.RFC3339),
}
json.NewEncoder(w).Encode(response)
}
