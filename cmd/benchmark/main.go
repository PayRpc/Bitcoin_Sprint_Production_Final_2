package main

import (
    "context"
    "encoding/json"
    "flag"
    "fmt"
    "math/rand"
    "os"
    "path/filepath"
    "runtime"
    "runtime/pprof"
    "sync"
    "sync/atomic"
    "time"

    "github.com/PayRpc/Bitcoin-Sprint/internal/cache"
    "github.com/PayRpc/Bitcoin-Sprint/internal/blocks"
    "go.uber.org/zap"
)

func main() {
    var durationSec int
    var tps int
    var workers int
    var profileDir string
    var useZipf bool
    var zipfS float64
    var zipfV float64

    flag.IntVar(&durationSec, "duration", 300, "duration in seconds (5-15 minutes recommended)")
    flag.IntVar(&tps, "tps", 2000, "target total operations per second")
    flag.IntVar(&workers, "workers", 50, "worker goroutines")
    flag.StringVar(&profileDir, "profileDir", "profiles", "directory to write pprof files")
    flag.BoolVar(&useZipf, "zipf", false, "use Zipfian key distribution (hot keys)")
    flag.Float64Var(&zipfS, "zipf_s", 1.07, "Zipf s parameter (skew)")
    flag.Float64Var(&zipfV, "zipf_v", 1.0, "Zipf v parameter")
    flag.Parse()

    if durationSec <= 0 {
        fmt.Println("invalid duration")
        return
    }

    if err := os.MkdirAll(profileDir, 0o755); err != nil {
        fmt.Println("failed to create profile dir:", err)
        return
    }

    logger, _ := zap.NewProduction()
    defer logger.Sync()

    cfg := cache.DefaultCacheConfig()
    ec, err := cache.NewEnterpriseCache(cfg, logger)
    if err != nil {
        fmt.Println("failed to init cache:", err)
        return
    }
    defer ec.Shutdown(context.Background())

    // Start CPU profile
    cpuFile := filepath.Join(profileDir, "cpu.pprof")
    f, err := os.Create(cpuFile)
    if err != nil {
        fmt.Println("failed to create cpu profile:", err)
        return
    }
    if err := pprof.StartCPUProfile(f); err != nil {
        fmt.Println("failed to start cpu profile:", err)
        f.Close()
        return
    }
    defer func() {
        pprof.StopCPUProfile()
        f.Close()
    }()

    // Heap profile path
    heapFile := filepath.Join(profileDir, "heap.pprof")

    // Metrics collection
    var ops uint64
    var setOps uint64
    var getOps uint64
    var cbOpenCount uint64

    rng := rand.New(rand.NewSource(time.Now().UnixNano()))

    keySpace := 10000
    var zipf *rand.Zipf
    if useZipf {
        // create Zipf generator over keySpace
        zipf = rand.NewZipf(rng, zipfS, zipfV, uint64(keySpace-1))
    }
    perWorker := tps / workers
    if perWorker < 1 {
        perWorker = 1
    }

    ctx, cancel := context.WithTimeout(context.Background(), time.Duration(durationSec)*time.Second)
    defer cancel()

    var wg sync.WaitGroup

    // Workers performing Set/Get
    for w := 0; w < workers; w++ {
        wg.Add(1)
        go func(id int) {
            defer wg.Done()
            localR := rand.New(rand.NewSource(time.Now().UnixNano() + int64(id)))
            ticker := time.NewTicker(time.Second / time.Duration(perWorker))
            defer ticker.Stop()
            for {
                select {
                case <-ctx.Done():
                    return
                case <-ticker.C:
                    // Randomly choose set or get (30% set, 70% get)
                    var keyIdx int
                    if useZipf {
                        keyIdx = int(zipf.Uint64())
                    } else {
                        keyIdx = localR.Intn(keySpace)
                    }
                    k := fmt.Sprintf("k_%d", keyIdx)
                    if localR.Float64() < 0.3 {
                        // set: payload size 512-4096 bytes
                        size := 512 + localR.Intn(3584)
                        b := make([]byte, size)
                        for i := range b {
                            b[i] = byte(localR.Intn(256))
                        }
                        _ = ec.Set(k, b, cfg.DefaultTTL)
                        atomic.AddUint64(&setOps, 1)
                        atomic.AddUint64(&ops, 1)
                    } else {
                        _, _ = ec.Get(k)
                        atomic.AddUint64(&getOps, 1)
                        atomic.AddUint64(&ops, 1)
                    }
                }
            }
        }(w)
    }

    // Background: periodically set latest block and exercise CB
    wg.Add(1)
    go func() {
        defer wg.Done()
        ticker := time.NewTicker(5 * time.Second)
        defer ticker.Stop()
        cb := &struct{ open bool }{open: false}
        for {
            select {
            case <-ctx.Done():
                return
            case <-ticker.C:
                b := blocks.BlockEvent{Height: uint32(rng.Intn(1000000)), Chain: blocks.ChainBitcoin, Source: "benchmark"}
                _ = ec.SetLatestBlock(b)
                // Simulate occasional failures to flip circuit breaker behavior
                // We'll detect open by checking error returned from a tight call pattern
                // Use a simple heuristic: if many errors happen, count as open event
                // (We cannot inspect internal CB state easily)
                // No-op here; just a placeholder to indicate CB traffic.
                _ = cb
            }
        }
    }()

    // Periodic reporter
    reportTicker := time.NewTicker(10 * time.Second)
    defer reportTicker.Stop()

    start := time.Now()
    lastOps := uint64(0)
    for {
        select {
        case <-ctx.Done():
            wg.Wait()
            // write heap profile
            hf, err := os.Create(heapFile)
            if err == nil {
                _ = pprof.WriteHeapProfile(hf)
                hf.Close()
            }
            // final metrics
            dur := time.Since(start)
            total := atomic.LoadUint64(&ops)
            fmt.Printf("benchmark complete: duration=%v total_ops=%d ops/sec=%.2f set=%d get=%d cb_open=%d\n",
                dur, total, float64(total)/dur.Seconds(), atomic.LoadUint64(&setOps), atomic.LoadUint64(&getOps), atomic.LoadUint64(&cbOpenCount))
            // print cache metrics
            m := ec.GetMetrics()
            jm, _ := json.MarshalIndent(m, "", "  ")
            fmt.Println("cache metrics:", string(jm))
            return
        case <-reportTicker.C:
            now := time.Now()
            total := atomic.LoadUint64(&ops)
            intervalOps := total - lastOps
            lastOps = total
            var ms runtime.MemStats
            runtime.ReadMemStats(&ms)
            m := ec.GetMetrics()
            fmt.Printf("report @ %s ops_in_10s=%d ops/sec=%.2f mem_alloc=%.2fMB num_gc=%d evictions=%d hits=%d misses=%d\n",
                now.Format(time.RFC3339), intervalOps, float64(intervalOps)/10.0, float64(ms.Alloc)/1024.0/1024.0, ms.NumGC, m.Evictions, m.CacheHits, m.CacheMisses)
        }
    }
}
