package main

import (
    "context"
    "fmt"
    "time"

    "github.com/PayRpc/Bitcoin-Sprint/internal/cache"
    "github.com/PayRpc/Bitcoin-Sprint/internal/blocks"
    "github.com/PayRpc/Bitcoin-Sprint/internal/p2p"
    "go.uber.org/zap"
)

func main() {
    logger, _ := zap.NewProduction()
    defer logger.Sync()

    // Create cache with defaults
    cfg := cache.DefaultCacheConfig()
    ec, err := cache.NewEnterpriseCache(cfg, logger)
    if err != nil {
        fmt.Println("cache init failed:", err)
        return
    }
    defer ec.Shutdown(context.Background())

    // Basic Set/Get
    key := "smoke_test_key"
    if err := ec.Set(key, "hello-smoke", cfg.DefaultTTL); err != nil {
        fmt.Println("cache set failed:", err)
        return
    }

    if v, ok := ec.Get(key); ok {
        fmt.Println("cache.get ->", v)
    } else {
        fmt.Println("cache.get miss")
    }

    // Test latest block setter/getter
    b := blocks.BlockEvent{Height: 12345, Chain: "bitcoin", Source: "smoke"}
    if err := ec.SetLatestBlock(b); err != nil {
        fmt.Println("SetLatestBlock failed:", err)
        return
    }

    if lb, ok := ec.GetLatestBlock(); ok {
        fmt.Println("GetLatestBlock -> height", lb.Height, "chain", lb.Chain)
    } else {
        fmt.Println("GetLatestBlock miss")
    }

    // Exercise P2P circuit breaker path via a minimal BlockProcessor invocation
    cb := p2p.NewCircuitBreaker(1, 1*time.Second)
    // Call a function that errors to trigger breaker
    err = cb.Call(func() error {
        return fmt.Errorf("simulated error")
    })
    if err != nil {
        fmt.Println("first call expected error ->", err)
    }

    // Second call should see circuit open (or half-open depending on timing)
    err = cb.Call(func() error { return nil })
    fmt.Println("second call result ->", err)

    fmt.Println("smoke test complete")
}
