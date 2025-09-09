package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"sync/atomic"
	"time"

	"github.com/PayRpc/Bitcoin-Sprint/internal/fastpath"
)

var (
	port     = flag.Int("port", 8080, "HTTP server port")
	duration = flag.Duration("duration", 5*time.Minute, "Server runtime duration")
)

func main() {
	flag.Parse()
	
	// Initialize with realistic data
	fastpath.RefreshLatest(789123, "000000000000000000023842e7b5a45aa85704aefd93733a7cb57188f2e5bc50c")
	fastpath.RefreshStatus("ok", 128, 3600)
	
	// Set up background refresh
	go func() {
		var height int64 = 789123
		startTime := time.Now()
		
		for {
			time.Sleep(1 * time.Second)
			height++
			
			// Simulate fetching a new block
			hash := fmt.Sprintf("%064x", height)
			fastpath.RefreshLatest(height, hash)
			
			uptimeSeconds := int64(time.Since(startTime).Seconds())
			connections := 128 + (uptimeSeconds % 10) // Simulate small connection changes
			fastpath.RefreshStatus("ok", int(connections), uptimeSeconds)
		}
	}()
	
	// Set up HTTP server with tuned timeouts
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/latest", fastpath.LatestHandler)
	mux.HandleFunc("/v1/status", fastpath.StatusHandler)
	
	// Add a metrics endpoint for easy monitoring
	var requestCount uint64
	mux.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "# HELP bitcoin_sprint_requests_total Total number of requests\n")
		fmt.Fprintf(w, "# TYPE bitcoin_sprint_requests_total counter\n")
		fmt.Fprintf(w, "bitcoin_sprint_requests_total %d\n", atomic.LoadUint64(&requestCount))
		
		fmt.Fprintf(w, "# HELP bitcoin_sprint_latest_hits_total Total number of /latest endpoint hits\n")
		fmt.Fprintf(w, "# TYPE bitcoin_sprint_latest_hits_total counter\n")
		fmt.Fprintf(w, "bitcoin_sprint_latest_hits_total %d\n", fastpath.GetLatestHits())
		
		fmt.Fprintf(w, "# HELP bitcoin_sprint_status_hits_total Total number of /status endpoint hits\n")
		fmt.Fprintf(w, "# TYPE bitcoin_sprint_status_hits_total counter\n")
		fmt.Fprintf(w, "bitcoin_sprint_status_hits_total %d\n", fastpath.GetStatusHits())
		
		// Add runtime metrics
		var mem runtime.MemStats
		runtime.ReadMemStats(&mem)
		fmt.Fprintf(w, "# HELP go_memstats_alloc_bytes Current memory allocation\n")
		fmt.Fprintf(w, "# TYPE go_memstats_alloc_bytes gauge\n")
		fmt.Fprintf(w, "go_memstats_alloc_bytes %d\n", mem.Alloc)
		
		fmt.Fprintf(w, "# HELP go_goroutines Number of goroutines\n")
		fmt.Fprintf(w, "# TYPE go_goroutines gauge\n")
		fmt.Fprintf(w, "go_goroutines %d\n", runtime.NumGoroutine())
	})
	
	// Create a middleware that counts requests
	countingMiddleware := func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			atomic.AddUint64(&requestCount, 1)
			next.ServeHTTP(w, r)
		})
	}
	
	server := &http.Server{
		Addr:              fmt.Sprintf(":%d", *port),
		Handler:           countingMiddleware(mux),
		ReadHeaderTimeout: 250 * time.Millisecond, // As per playbook recommendation
		WriteTimeout:      1 * time.Second,        // As per playbook recommendation
		IdleTimeout:       60 * time.Second,       // As per playbook recommendation
		MaxHeaderBytes:    8 << 10,                // 8KB
	}
	
	// Set up graceful shutdown
	ctx, cancel := context.WithTimeout(context.Background(), *duration)
	defer cancel()
	
	go func() {
		<-ctx.Done()
		if ctx.Err() == context.DeadlineExceeded {
			log.Println("Shutting down after specified duration")
		}
		
		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer shutdownCancel()
		
		if err := server.Shutdown(shutdownCtx); err != nil {
			log.Printf("Error during server shutdown: %v", err)
		}
	}()
	
	// Handle CTRL+C
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt)
	
	go func() {
		<-c
		log.Println("Received interrupt, shutting down...")
		cancel()
	}()
	
	log.Printf("Starting low-latency server on port %d (timeout: %s)", *port, *duration)
	log.Printf("Try: curl http://localhost:%d/v1/latest", *port)
	log.Printf("     curl http://localhost:%d/v1/status", *port)
	log.Printf("     curl http://localhost:%d/metrics", *port)
	log.Printf("For load testing: wrk -t8 -c512 -d30s --latency http://localhost:%d/v1/latest", *port)
	
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Error starting server: %v", err)
	}
	
	log.Println("Server shutdown complete")
}
