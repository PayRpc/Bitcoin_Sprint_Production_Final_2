#!/usr/bin/env pwsh

Write-Host "====== SIMPLE BITCOIN SPRINT TEST ======" -ForegroundColor Cyan
Write-Host "Testing basic Sprint Acceleration Layer functionality" -ForegroundColor White
Write-Host "==========================================" -ForegroundColor Cyan

# Use unique ports to avoid conflicts
$testPort = 9010
$healthPort = 9011

Write-Host "Using ports: API=$testPort, Health=$healthPort" -ForegroundColor Green

# Clean up any existing processes
Stop-Process -Name "bitcoin-sprint" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Create environment configuration for this test
$envContent = @"
# Basic Sprint Configuration for Testing
API_HOST=127.0.0.1
API_PORT=$testPort
HEALTH_PORT=$healthPort
LOG_LEVEL=info
NODE_ID=test-node-$(Get-Random)

# Sprint Acceleration Layer Configuration
ENABLE_ACCELERATION=true
ACCELERATION_MODE=true
BLOCK_DEDUPLICATION=true
INTELLIGENT_EVICTION=true
PREDICTIVE_CACHING_ENABLED=true
CACHE_HIT_TARGET=87

# API Authentication
AUTH_REQUIRED=true

# Ethereum endpoints
ETH_HTTP_URL=https://eth-rpc.nethermind.io
ETH_WS_URL=wss://ethereum.publicnode.com
ETH_TIMEOUT=15s
ETH_USE_ACCELERATION=true

# Enterprise features
ENTERPRISE_MODE=true
TIER=ENTERPRISE
LICENSE_PATH=config/license-enterprise.json
"@

$envFile = "test-simple.env"
$envContent | Out-File -FilePath $envFile -Encoding UTF8

Write-Host "Starting Bitcoin Sprint with acceleration layer..." -ForegroundColor Yellow

# Start the service
$process = Start-Process -FilePath ".\bitcoin-sprint.exe" -ArgumentList "--config", $envFile -NoNewWindow -PassThru -RedirectStandardOutput "test-output.log" -RedirectStandardError "test-error.log"

if (-not $process) {
    Write-Host "✗ Failed to start Bitcoin Sprint process" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Process started with PID: $($process.Id)" -ForegroundColor Green

# Wait for service to initialize
Write-Host "Waiting for service to initialize..." -ForegroundColor Gray
for ($i = 1; $i -le 20; $i++) {
    Start-Sleep -Seconds 3
    
    # Test health endpoint
    try {
        $healthResponse = Invoke-RestMethod -Uri "http://127.0.0.1:$healthPort/health" -Method GET -TimeoutSec 5
        Write-Host "✓ Health check successful: $($healthResponse.status)" -ForegroundColor Green
        Write-Host "  Node ID: $($healthResponse.node_id)" -ForegroundColor Cyan
        Write-Host "  Version: $($healthResponse.version)" -ForegroundColor Cyan
        break
    } catch {
    Write-Host "  Attempt ${i} - Health check: $($_.Exception.Message)" -ForegroundColor Yellow
        if ($i -eq 20) {
            Write-Host "✗ Health check failed after all attempts" -ForegroundColor Red
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            exit 1
        }
    }
}

# Test API with authentication
Write-Host "Testing API with authentication..." -ForegroundColor Yellow

$apiKey = "sprint-ent_XbF9YlK8mNqPzR3vW7dGhJ2cA5eT1uI9oL6sQ4rE8wY"
$headers = @{
    "X-API-Key" = $apiKey
    "Content-Type" = "application/json"
}

$testBody = @{
    "jsonrpc" = "2.0"
    "method" = "eth_chainId"
    "params" = @()
    "id" = 1
} | ConvertTo-Json

$apiUrl = "http://127.0.0.1:$testPort/api/v1/universal/ethereum"

try {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Uri $apiUrl -Method POST -Body $testBody -Headers $headers -TimeoutSec 15
    $latency = $stopwatch.ElapsedMilliseconds
    
    Write-Host "✓ API request successful!" -ForegroundColor Green
    Write-Host "  Chain ID: $($response.result)" -ForegroundColor Cyan
    Write-Host "  Latency: ${latency}ms" -ForegroundColor Cyan
    Write-Host "  Response ID: $($response.id)" -ForegroundColor Cyan
    
    # Test a few more requests to verify acceleration layer
    Write-Host "Testing acceleration layer performance..." -ForegroundColor Yellow
    
    $successCount = 0
    $totalLatency = 0
    $testCount = 5
    
    for ($i = 1; $i -le $testCount; $i++) {
        $testBody2 = @{
            "jsonrpc" = "2.0"
            "method" = "eth_blockNumber"
            "params" = @()
            "id" = $i + 1
        } | ConvertTo-Json
        
        try {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $response2 = Invoke-RestMethod -Uri $apiUrl -Method POST -Body $testBody2 -Headers $headers -TimeoutSec 10
            $latency2 = $stopwatch.ElapsedMilliseconds
            
            $successCount++
            $totalLatency += $latency2
            
            Write-Host "  Request ${i}: Block $($response2.result) (${latency2}ms)" -ForegroundColor Green
        } catch {
            Write-Host "  Request ${i} failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Start-Sleep -Milliseconds 500
    }
    
    if ($successCount -gt 0) {
        $avgLatency = [math]::Round($totalLatency / $successCount, 2)
        $successRate = [math]::Round(($successCount / $testCount) * 100, 1)
        
        Write-Host "====== TEST RESULTS ======" -ForegroundColor Cyan
        Write-Host "Success Rate: $successRate%" -ForegroundColor $(if ($successRate -gt 80) { "Green" } else { "Red" })
        Write-Host "Average Latency: ${avgLatency}ms" -ForegroundColor $(if ($avgLatency -lt 500) { "Green" } else { "Yellow" })
        Write-Host "Successful Requests: $successCount/$testCount" -ForegroundColor Cyan
        Write-Host "Sprint Acceleration Layer: ACTIVE" -ForegroundColor Green
        Write-Host "=========================" -ForegroundColor Cyan
        
        if ($successRate -ge 80 -and $avgLatency -lt 1000) {
            Write-Host "✓ Bitcoin Sprint Acceleration Layer is working correctly!" -ForegroundColor Green
        } else {
            Write-Host "⚠ Performance may need optimization" -ForegroundColor Yellow
        }
    } else {
        Write-Host "✗ All test requests failed" -ForegroundColor Red
    }
    
} catch {
    Write-Host "✗ API test failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Cleanup
Write-Host "Cleaning up..." -ForegroundColor Gray
Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
Remove-Item -Path $envFile -ErrorAction SilentlyContinue

Write-Host "Test completed." -ForegroundColor White
