# 5ms P99 Latency Playbook Implementation

This document outlines the implementation of the "5ms P99 Latency Playbook" for Bitcoin Sprint. The goal is to achieve sub-5ms p99 latency for critical API endpoints.

## Key Implementation Details

### 1. Atomic Snapshot Pattern

The core of the implementation is the `fastpath` package that uses the atomic snapshot pattern:

```go
// Snapshot holds an immutable []byte that can be atomically loaded and stored
type Snapshot struct {
    b atomic.Value // holds []byte
}

// Store atomically replaces the snapshot with a new value
func (s *Snapshot) Store(p []byte) {
    s.b.Store(append([]byte(nil), p...)) // ensure immutable copy
}

// Load returns the current snapshot bytes
func (s *Snapshot) Load() []byte {
    if v := s.b.Load(); v != nil {
        return v.([]byte)
    }
    return nil
}
```

### 2. Zero-Allocation Request Handlers

Request handlers are designed to minimize allocations:

```go
func LatestHandler(w http.ResponseWriter, r *http.Request) {
    b := latestSnap.Load()
    w.Header().Set("Content-Type", "application/json")
    w.Header().Set("Content-Length", strconv.Itoa(len(b)))
    _, _ = w.Write(b) // ~sub-ms on hit
}
```

### 3. Pre-encoded JSON

JSON is pre-encoded using zero-allocation string concatenation:

```go
func RefreshLatest(height int64, hash string) {
    b := make([]byte, 0, 96)
    b = append(b, `{"height":`...)
    b = strconv.AppendInt(b, height, 10)
    b = append(b, `,"hash":"`...)
    b = append(b, hash...)
    b = append(b, `"}`...)
    latestSnap.Store(b) // atomic swap
}
```

### 4. Optimized HTTP Server Configuration

```go
server := &http.Server{
    Addr:              fmt.Sprintf(":%d", *port),
    Handler:           countingMiddleware(mux),
    ReadHeaderTimeout: 250 * time.Millisecond, // As per playbook recommendation
    WriteTimeout:      1 * time.Second,        // As per playbook recommendation
    IdleTimeout:       60 * time.Second,       // As per playbook recommendation
    MaxHeaderBytes:    8 << 10,                // 8KB
}
```

## Benchmark Results

The implementation has been benchmarked using:
- Dedicated benchmark server (`benchmark/latency/p99_server.go`)
- wrk HTTP benchmarking tool
- Various concurrency levels (up to 512 connections)

For detailed benchmark results, see [P99_LATENCY_REPORT.md](benchmark/latency/P99_LATENCY_REPORT.md).

## Testing Suite

We've implemented comprehensive testing:
1. Microbenchmarks for individual handlers
2. Parallel benchmarks to simulate high concurrency
3. In-process latency measurements
4. Full HTTP server load tests

## Usage in Production

To use this pattern in production code:

1. Import the `fastpath` package
2. Set up background refreshers with appropriate data sources
3. Use the provided handlers or create custom ones using the same pattern

Example:
```go
import "github.com/PayRpc/Bitcoin-Sprint/internal/fastpath"

// Set up initial data
fastpath.RefreshLatest(currentHeight, currentHash)

// Register handlers
mux.HandleFunc("/v1/latest", fastpath.LatestHandler)

// Set up background refresh
go func() {
    for {
        // Update when new data is available
        fastpath.RefreshLatest(newHeight, newHash)
        time.Sleep(time.Second)
    }
}()
```
