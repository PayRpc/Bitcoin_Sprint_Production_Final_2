param(
    [int]$TestDurationSec = 60,
    [string]$Mode = "acceleration" # "standard" or "acceleration"
)

$ErrorActionPreference = 'Stop'

# Get workspace path
$scriptPath = $MyInvocation.MyCommand.Path
$scriptsDir = Split-Path -Parent $scriptPath
$workspaceDir = Split-Path -Parent $scriptsDir

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$testDir = Join-Path $workspaceDir "logs\quick-test-$timestamp"
New-Item -ItemType Directory -Path $testDir -Force | Out-Null

Write-Host "====== QUICK ACCELERATION TEST ======" -ForegroundColor Cyan
Write-Host "Mode: $Mode" -ForegroundColor Cyan
Write-Host "Duration: $TestDurationSec seconds" -ForegroundColor Cyan
Write-Host "Test directory: $testDir" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor Cyan

# Find a free port
$testPort = 9000
while ((Get-NetTCPConnection -LocalPort $testPort -ErrorAction SilentlyContinue)) {
    $testPort++
}
$healthPort = $testPort + 1

Write-Host "Using ports: API=$testPort, Health=$healthPort" -ForegroundColor Green

# Create configuration based on mode
if ($Mode -eq "acceleration") {
    Write-Host "Configuring ACCELERATION mode with all features enabled..." -ForegroundColor Yellow
    $envConfig = @"
# Bitcoin Sprint Acceleration Mode Test
ACCELERATION_ENABLED=true
DEDUPLICATION_TIER=ENTERPRISE
CROSS_NETWORK_DEDUP=true
INTELLIGENT_EVICTION=true
NETWORK_SPECIFIC_TTL=true
ADAPTIVE_OPTIMIZATION=true
LATENCY_FLATTENING_ENABLED=true
PREDICTIVE_CACHING_ENABLED=true
ENDPOINT_CIRCUIT_BREAKER=true
MULTI_PEER_REDUNDANCY=true
PARALLEL_REQUEST_THRESHOLD=200
RESPONSE_VERIFICATION_MODE=full
COMPETITIVE_EDGE_MODE=true

# API Configuration
API_HOST=127.0.0.1
API_PORT=$testPort
API_BIND=127.0.0.1:$testPort
HEALTH_PORT=$healthPort
LOG_LEVEL=info

# Ethereum endpoints - multiple reliable sources
ETH_HTTP_URL=https://eth-rpc.nethermind.io
ETH_WS_URL=wss://eth-ws.nethermind.io
ETH_HTTP_ENDPOINTS=["https://eth-rpc.nethermind.io","https://gateway.fm/eth/rpc","https://ethereum.publicnode.com"]
ETH_WS_ENDPOINTS=["wss://eth-ws.nethermind.io","wss://gateway.fm/eth/ws","wss://ethereum.publicnode.com"]
ETH_TIMEOUT=15s
ETH_MAX_CONNECTIONS=5
ETH_USE_ACCELERATION=true
ETH_RETRY_ATTEMPTS=3

# Solana endpoints
SOL_RPC_URL=https://api.mainnet-beta.solana.com
SOLANA_RPC_ENDPOINTS=["https://api.mainnet-beta.solana.com","https://rpc.ankr.com/solana"]
SOL_USE_ACCELERATION=true

# Advanced acceleration features
DEDUP_CAPACITY=20480
ETH_ACCELERATION_TTL=300
SOL_ACCELERATION_TTL=180
ENABLE_PREDICTIVE_CACHE=true
CACHE_HIT_TARGET=87
PROVIDER_HEALTH_CHECK_INTERVAL=30s
CIRCUIT_BREAKER_THRESHOLD=5
CIRCUIT_BREAKER_TIMEOUT=60s

# Performance monitoring
ENABLE_METRICS=true
METRICS_INTERVAL=10s
LATENCY_TRACKING=true
"@
} else {
    Write-Host "Configuring STANDARD mode (no acceleration)..." -ForegroundColor Yellow
    $envConfig = @"
# Bitcoin Sprint Standard Mode Test
ACCELERATION_ENABLED=false
DEDUPLICATION_TIER=FREE
CROSS_NETWORK_DEDUP=false
INTELLIGENT_EVICTION=false
NETWORK_SPECIFIC_TTL=false
ADAPTIVE_OPTIMIZATION=false
LATENCY_FLATTENING_ENABLED=false
PREDICTIVE_CACHING_ENABLED=false
ENDPOINT_CIRCUIT_BREAKER=false
MULTI_PEER_REDUNDANCY=false
COMPETITIVE_EDGE_MODE=false

# API Configuration
API_HOST=127.0.0.1
API_PORT=$testPort
API_BIND=127.0.0.1:$testPort
HEALTH_PORT=$healthPort
LOG_LEVEL=info

# Single endpoint configuration (no redundancy)
ETH_HTTP_URL=https://ethereum.publicnode.com
ETH_WS_URL=wss://ethereum.publicnode.com
ETH_TIMEOUT=30s
ETH_MAX_CONNECTIONS=1
ETH_USE_ACCELERATION=false
ETH_RETRY_ATTEMPTS=1

# Solana single endpoint
SOL_RPC_URL=https://api.mainnet-beta.solana.com
SOL_USE_ACCELERATION=false

# No advanced features
DEDUP_CAPACITY=512
ENABLE_METRICS=false
"@
}

$envFile = Join-Path $testDir "test.env"
$envConfig | Out-File -FilePath $envFile -Encoding utf8

$appLogFile = Join-Path $testDir "app.log"
$errLogFile = Join-Path $testDir "error.log"

# Start Bitcoin Sprint
Write-Host "Starting Bitcoin Sprint..." -ForegroundColor Green
try {
    $exePath = Join-Path $workspaceDir "bitcoin-sprint.exe"
    
    # Set environment variables
    foreach ($line in ($envConfig -split "`n")) {
        if ($line.Trim() -and !$line.StartsWith("#")) {
            $parts = $line -split "=", 2
            if ($parts.Length -eq 2) {
                [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim(), "Process")
            }
        }
    }
    
    $process = Start-Process -FilePath $exePath -WorkingDirectory $workspaceDir -NoNewWindow -PassThru -RedirectStandardOutput $appLogFile -RedirectStandardError $errLogFile
    
    if (!$process -or $process.HasExited) {
        Write-Host "Failed to start Bitcoin Sprint!" -ForegroundColor Red
        if (Test-Path $errLogFile) {
            Write-Host "Error log:" -ForegroundColor Red
            Get-Content $errLogFile
        }
        exit 1
    }
    
    Write-Host "Process started with PID: $($process.Id)" -ForegroundColor Green
    
    # Wait for service to initialize
    Write-Host "Waiting for service to initialize..." -ForegroundColor Gray
    Start-Sleep -Seconds 15
    
    # Test the API endpoint
    $apiUrl = "http://127.0.0.1:$testPort/api/v1/universal/ethereum"
    $healthUrl = "http://127.0.0.1:$healthPort/health"
    
    Write-Host "Testing endpoints..." -ForegroundColor Yellow
    
    # Test health endpoint
    try {
        $healthResponse = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 5
        Write-Host "Health check: OK" -ForegroundColor Green
    } catch {
        Write-Host "Health check failed: $_" -ForegroundColor Red
    }
    
    # Test Ethereum API with proper authentication
    $apiKey = "sprint-ent_XbF9YlK8mNqPzR3vW7dGhJ2cA5eT1uI9oL6sQ4rE8wY"
    $headers = @{
        "X-API-Key" = $apiKey
        "Content-Type" = "application/json"
    }
    
    $testRequests = @(
        '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}',
        '{"jsonrpc":"2.0","method":"eth_getBalance","params":["0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", "latest"],"id":2}',
        '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false],"id":3}'
    )
    
    $successCount = 0
    $totalLatency = 0
    $latencies = @()
    
    Write-Host "Running test requests..." -ForegroundColor Yellow
    
    for ($i = 0; $i -lt $TestDurationSec; $i++) {
        foreach ($requestBody in $testRequests) {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            try {
                $response = Invoke-WebRequest -Uri $apiUrl -Method POST -Body $requestBody -Headers $headers -UseBasicParsing -TimeoutSec 10
                $latency = $stopwatch.ElapsedMilliseconds
                
                if ($response.StatusCode -eq 200) {
                    $successCount++
                    $totalLatency += $latency
                    $latencies += $latency
                    
                    if ($i % 10 -eq 0) {
                        Write-Host "  Request $($i * $testRequests.Count + $testRequests.IndexOf($requestBody)): ${latency}ms" -ForegroundColor Green
                    }
                }
            } catch {
                if ($i % 10 -eq 0) {
                    Write-Host "  Request failed: $_" -ForegroundColor Red
                }
            }
            
            $stopwatch.Stop()
        }
        
        Start-Sleep -Milliseconds 100
    }
    
    # Calculate results
    $totalRequests = $TestDurationSec * $testRequests.Count
    $successRate = if ($totalRequests -gt 0) { ($successCount / $totalRequests) * 100 } else { 0 }
    $avgLatency = if ($successCount -gt 0) { $totalLatency / $successCount } else { 0 }
    
    # Calculate percentiles
    $p50Latency = 0
    $p90Latency = 0
    $p99Latency = 0
    
    if ($latencies.Count -gt 0) {
        $sortedLatencies = $latencies | Sort-Object
        $p50Latency = $sortedLatencies[[math]::Floor($sortedLatencies.Count * 0.5)]
        $p90Latency = $sortedLatencies[[math]::Floor($sortedLatencies.Count * 0.9)]
        $p99Latency = $sortedLatencies[[math]::Floor($sortedLatencies.Count * 0.99)]
    }
    
    # Display results
    Write-Host "`n====== TEST RESULTS ======" -ForegroundColor Cyan
    Write-Host "Mode: $Mode" -ForegroundColor White
    Write-Host "Total Requests: $totalRequests" -ForegroundColor White
    Write-Host "Successful Requests: $successCount" -ForegroundColor $(if ($successCount -gt 0) {"Green"} else {"Red"})
    Write-Host "Success Rate: $([math]::Round($successRate, 1))%" -ForegroundColor $(if ($successRate -gt 95) {"Green"} elseif ($successRate -gt 50) {"Yellow"} else {"Red"})
    Write-Host "Average Latency: $([math]::Round($avgLatency, 1)) ms" -ForegroundColor $(if ($avgLatency -lt 100) {"Green"} elseif ($avgLatency -lt 300) {"Yellow"} else {"Red"})
    Write-Host "P50 Latency: $([math]::Round($p50Latency, 1)) ms" -ForegroundColor White
    Write-Host "P90 Latency: $([math]::Round($p90Latency, 1)) ms" -ForegroundColor White
    Write-Host "P99 Latency: $([math]::Round($p99Latency, 1)) ms" -ForegroundColor White
    Write-Host "=========================" -ForegroundColor Cyan
    
    # Stop the process
    Write-Host "`nStopping Bitcoin Sprint..." -ForegroundColor Yellow
    Stop-Process -Id $process.Id -Force
    
} catch {
    Write-Host "Error during test: $_" -ForegroundColor Red
    
    # Try to stop any process we started
    if ($process -and !$process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
}

Write-Host "`nTest completed. Logs saved to: $testDir" -ForegroundColor Green
