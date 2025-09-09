# Bitcoin Sprint P99 Latency Benchmarks

This directory contains tools for validating and testing the 5ms p99 latency goal for Bitcoin Sprint.

## Overview

The Bitcoin Sprint "5 ms p99 Latency Playbook" describes techniques for achieving extremely low latency responses for critical API endpoints. This benchmark suite provides tools to measure and validate these techniques.

## Key Files

- `p99_server.go` - HTTP server implementing the atomic snapshot pattern
- `p99_benchmark.ps1` - PowerShell script to run benchmarks with wrk
- `run_and_update_report.ps1` - Script to run benchmarks and update the report
- `p99_load_test.lua` - Advanced wrk script for detailed load testing
- `P99_LATENCY_REPORT.md` - Report documenting findings and results
- `Makefile` - Makefile for building and running benchmarks

## Prerequisites

1. Go installed and configured
2. PowerShell
3. wrk HTTP benchmarking tool (automatically downloaded by the scripts)

## Running Benchmarks

### Quick Start

```powershell
# Run benchmarks and update report
.\run_and_update_report.ps1
```

### Manual Steps

```powershell
# Build the benchmark server
go build -o ../../bin/p99_server.exe ./p99_server.go

# Run the benchmarks
.\p99_benchmark.ps1

# Advanced load testing (using the Lua script)
wrk -t8 -c512 -d30s --latency --script p99_load_test.lua http://localhost:8765/
```

### Using the Makefile

```bash
# Build and run benchmarks
make

# Just build the server
make build

# Run the server for manual testing
make server

# Clean up build artifacts
make clean
```

## Understanding the Results

The benchmark results are presented in the P99_LATENCY_REPORT.md file. Key metrics to look for:

- p99 latency for `/v1/latest` endpoint should be ≤ 5ms
- RPS (requests per second) should be high (typically 10,000+)
- Minimal allocations per request

## Implementation Details

The low-latency implementation uses these key techniques:

1. **Atomic Snapshot Pattern**: Using `atomic.Value` to store pre-computed responses
2. **Zero-Allocation Handlers**: Minimizing memory allocations during request handling
3. **Pre-encoded JSON**: Avoiding serialization during request handling
4. **Optimized HTTP Server**: Tuned timeouts and connection parameters

For more details, see the implementation in `internal/fastpath/fastpath.go`.
