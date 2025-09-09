package cache

import (
	"context"
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// fakeClock for deterministic test timing
type fakeClock struct {
	mu sync.Mutex
	t  time.Time
}

func (f *fakeClock) Now() time.Time          { f.mu.Lock(); defer f.mu.Unlock(); return f.t }
func (f *fakeClock) Advance(d time.Duration) { f.mu.Lock(); f.t = f.t.Add(d); f.mu.Unlock() }

// Minimal Config helper to create small caches for tests
func smallConfig() *CacheConfig {
	c := DefaultCacheConfig()
	c.MaxEntries = 16
	c.ShardCount = 1
	c.EnableBloomFilter = false
	return c
}

func TestSingleflightCollapse(t *testing.T) {
	c, _ := NewEnterpriseCache(smallConfig(), nil)
	fc := &fakeClock{t: time.Now()}
	c.SetClock(fc)
	var calls int32
	loader := func(ctx context.Context) (any, error) {
		atomic.AddInt32(&calls, 1)
		time.Sleep(10 * time.Millisecond)
		return "ok", nil
	}
	const N = 64
	var wg sync.WaitGroup
	var testErr error
	var testErrMu sync.Mutex
	wg.Add(N)
	for i := 0; i < N; i++ {
		go func() {
			defer wg.Done()
			v, _, err := c.GetOrLoad(context.Background(), "k", time.Minute, loader)
			if err != nil || v.(string) != "ok" {
				testErrMu.Lock()
				testErr = fmt.Errorf("bad: %v %v", v, err)
				testErrMu.Unlock()
			}
		}()
	}
	wg.Wait()
	if testErr != nil {
		t.Fatal(testErr)
	}
	if got := atomic.LoadInt32(&calls); got != 1 {
		t.Fatalf("loader called %d times; want 1", got)
	}
}

func TestSWRReturnsStaleThenRefreshes(t *testing.T) {
	c, _ := NewEnterpriseCache(smallConfig(), nil)
	fc := &fakeClock{t: time.Now()}
	c.SetClock(fc)
	var val atomic.Value
	val.Store("v1")
	loader := func(ctx context.Context) (any, error) { return val.Load().(string), nil }

	// Seed fresh
	v, _, err := c.GetSWR(context.Background(), "s", loader, 20*time.Millisecond, 200*time.Millisecond)
	if err != nil || v.(string) != "v1" {
		t.Fatalf("seed: %v %v", v, err)
	}

	// Let hard TTL pass, but stay within soft TTL (stale allowed, async refresh)
	fc.Advance(30 * time.Millisecond)
	got, hit, err := c.GetSWR(context.Background(), "s", loader, 50*time.Millisecond, 400*time.Millisecond)
	if err != nil || !hit || got.(string) != "v1" {
		t.Fatalf("stale: %v %v %v", got, hit, err)
	}

	// Change upstream and allow background refresh to land
	val.Store("v2")
	fc.Advance(80 * time.Millisecond)
	// Wait deterministically for refresh via refreshNotify channel
	ch := c.RefreshNotify()
	select {
	case k := <-ch:
		if k != "s" {
			t.Fatalf("unexpected refresh key: %s", k)
		}
	case <-time.After(200 * time.Millisecond):
		t.Fatalf("refresh did not complete in time")
	}
	// Verify new value is present
	v2, _, _ := c.GetOrLoad(context.Background(), "s", time.Minute, func(context.Context) (any, error) { return nil, nil })
	if v2 == nil || v2.(string) != "v2" {
		t.Fatalf("want refreshed v2, got %v", v2)
	}

}

func TestTinyLFUProtectsHotVictim(t *testing.T) {
	c, _ := NewEnterpriseCache(smallConfig(), nil)
	fc := &fakeClock{t: time.Now()}
	c.SetClock(fc)
	// Prime a hot key that will be chosen as a potential victim
	_ = c.levels[L1Memory].Set("hot", &CacheEntry{Key: "hot", Value: 1, ExpiresAt: fc.Now().Add(time.Hour)})
	for i := 0; i < 1000; i++ {
		c.touchKey("hot")
	}

	// Cold key should lose admission against hot victim
	c.touchKey("cold")
	// Use internal concrete backend path
	if mb, ok := c.levels[L1Memory].(*MemoryBackend); ok {
		mb.setWithAdmission(c, "cold", CacheEntry{Key: "cold", Value: 2, ExpiresAt: fc.Now().Add(time.Hour)})
	}

	if entry, _ := c.levels[L1Memory].Get("hot"); entry == nil {
		t.Fatal("hot key evicted by cold candidate; TinyLFU admission broken")
	}
}
