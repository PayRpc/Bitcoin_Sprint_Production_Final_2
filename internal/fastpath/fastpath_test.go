package fastpath_test

import (
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/PayRpc/Bitcoin-Sprint/internal/fastpath"
)

func BenchmarkLatestHandler(b *testing.B) {
	// Initialize with realistic data
	fastpath.RefreshLatest(789123, "000000000000000000023842e7b5a45aa85704aefd93733a7cb57188f2e5bc50c")
	
	req, err := http.NewRequest("GET", "/v1/latest", nil)
	if err != nil {
		b.Fatal(err)
	}

	b.ResetTimer()
	b.ReportAllocs()
	
	for i := 0; i < b.N; i++ {
		rr := httptest.NewRecorder()
		handler := http.HandlerFunc(fastpath.LatestHandler)
		handler.ServeHTTP(rr, req)
		
		if status := rr.Code; status != http.StatusOK {
			b.Fatalf("handler returned wrong status code: got %v want %v", status, http.StatusOK)
		}
	}
}

func BenchmarkStatusHandler(b *testing.B) {
	// Initialize with realistic data
	fastpath.RefreshStatus("ok", 128, 3600)
	
	req, err := http.NewRequest("GET", "/v1/status", nil)
	if err != nil {
		b.Fatal(err)
	}

	b.ResetTimer()
	b.ReportAllocs()
	
	for i := 0; i < b.N; i++ {
		rr := httptest.NewRecorder()
		handler := http.HandlerFunc(fastpath.StatusHandler)
		handler.ServeHTTP(rr, req)
		
		if status := rr.Code; status != http.StatusOK {
			b.Fatalf("handler returned wrong status code: got %v want %v", status, http.StatusOK)
		}
	}
}

// ParallelBenchmarkLatestHandler simulates high concurrent load
func BenchmarkLatestHandler_Parallel(b *testing.B) {
	// Initialize with realistic data
	fastpath.RefreshLatest(789123, "000000000000000000023842e7b5a45aa85704aefd93733a7cb57188f2e5bc50c")
	
	// Background refresh
	go func() {
		height := int64(789123)
		for {
			time.Sleep(200 * time.Millisecond)
			height++
			fastpath.RefreshLatest(height, "hash"+string(height))
		}
	}()
	
	b.ResetTimer()
	b.ReportAllocs()
	
	b.RunParallel(func(pb *testing.PB) {
		req, _ := http.NewRequest("GET", "/v1/latest", nil)
		for pb.Next() {
			rr := httptest.NewRecorder()
			handler := http.HandlerFunc(fastpath.LatestHandler)
			handler.ServeHTTP(rr, req)
		}
	})
}

// SimulatedHighLoad tests a mix of reads and writes
func BenchmarkHighLoad(b *testing.B) {
	// Initialize
	fastpath.RefreshLatest(789123, "000000000000000000023842e7b5a45aa85704aefd93733a7cb57188f2e5bc50c")
	fastpath.RefreshStatus("ok", 128, 3600)
	
	var wg sync.WaitGroup
	stopChan := make(chan struct{})
	
	// Start updater goroutines
	wg.Add(1)
	go func() {
		defer wg.Done()
		height := int64(789123)
		
		ticker := time.NewTicker(10 * time.Millisecond) // Fast updates
		defer ticker.Stop()
		
		for {
			select {
			case <-ticker.C:
				height++
				fastpath.RefreshLatest(height, "hash"+string(height))
			case <-stopChan:
				return
			}
		}
	}()
	
	wg.Add(1)
	go func() {
		defer wg.Done()
		connections := 128
		uptime := int64(3600)
		
		ticker := time.NewTicker(15 * time.Millisecond) // Fast updates
		defer ticker.Stop()
		
		for {
			select {
			case <-ticker.C:
				connections += 1
				uptime += 1
				fastpath.RefreshStatus("ok", connections, uptime)
			case <-stopChan:
				return
			}
		}
	}()
	
	// Prepare requests
	latestReq, _ := http.NewRequest("GET", "/v1/latest", nil)
	statusReq, _ := http.NewRequest("GET", "/v1/status", nil)
	
	b.ResetTimer()
	b.ReportAllocs()
	
	b.RunParallel(func(pb *testing.PB) {
		i := 0
		for pb.Next() {
			rr := httptest.NewRecorder()
			if i%3 == 0 { // Mix of latest and status requests
				fastpath.StatusHandler(rr, statusReq)
			} else {
				fastpath.LatestHandler(rr, latestReq)
			}
			i++
		}
	})
	
	b.StopTimer()
	close(stopChan)
	wg.Wait()
}

// Test actual latency under load
func TestLatencyUnderLoad(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping latency test in short mode")
	}
	
	// Initialize with realistic data
	fastpath.RefreshLatest(789123, "000000000000000000023842e7b5a45aa85704aefd93733a7cb57188f2e5bc50c")
	fastpath.RefreshStatus("ok", 128, 3600)
	
	var wg sync.WaitGroup
	stopChan := make(chan struct{})
	
	// Start update goroutine
	wg.Add(1)
	go func() {
		defer wg.Done()
		height := int64(789123)
		
		ticker := time.NewTicker(50 * time.Millisecond)
		defer ticker.Stop()
		
		for {
			select {
			case <-ticker.C:
				height++
				fastpath.RefreshLatest(height, "hash"+string(height))
			case <-stopChan:
				return
			}
		}
	}()
	
	// Start load generation goroutines
	const numLoaders = 8
	const requestsPerLoader = 5000
	
	latencies := make([]time.Duration, numLoaders*requestsPerLoader)
	var latencyLock sync.Mutex
	var latencyIndex int64
	
	for i := 0; i < numLoaders; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			
			req, _ := http.NewRequest("GET", "/v1/latest", nil)
			
			for j := 0; j < requestsPerLoader; j++ {
				start := time.Now()
				rr := httptest.NewRecorder()
				fastpath.LatestHandler(rr, req)
				dur := time.Since(start)
				
				latencyLock.Lock()
				idx := latencyIndex
				latencyIndex++
				latencies[idx] = dur
				latencyLock.Unlock()
				
				// Small sleep to simulate real-world conditions
				time.Sleep(time.Microsecond)
			}
		}(i)
	}
	
	wg.Wait()
	close(stopChan)
	
	// Calculate percentiles
	sortDurations(latencies)
	p50 := latencies[len(latencies)/2]
	p90 := latencies[len(latencies)*90/100]
	p99 := latencies[len(latencies)*99/100]
	p999 := latencies[len(latencies)*999/1000]
	
	t.Logf("Latency under load (n=%d):", len(latencies))
	t.Logf("  p50: %v", p50)
	t.Logf("  p90: %v", p90)
	t.Logf("  p99: %v", p99)
	t.Logf("  p999: %v", p999)
	
	// Check against target
	if p99 > 5*time.Millisecond {
		t.Errorf("p99 latency exceeds 5ms target: %v", p99)
	}
}

// Helper to sort durations
func sortDurations(durations []time.Duration) {
	for i := 0; i < len(durations)-1; i++ {
		for j := i + 1; j < len(durations); j++ {
			if durations[i] > durations[j] {
				durations[i], durations[j] = durations[j], durations[i]
			}
		}
	}
}
