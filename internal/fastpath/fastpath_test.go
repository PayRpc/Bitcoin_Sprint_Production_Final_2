package fastpath_test

import (
	"net/http"
	"net/http/httptest"
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
