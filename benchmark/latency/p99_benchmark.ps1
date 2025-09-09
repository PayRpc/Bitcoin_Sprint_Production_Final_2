#!/usr/bin/env pwsh
# p99_benchmark.ps1 - Script to validate p99 latency for Bitcoin Sprint

# Ensure we're in the right directory
Set-Location $PSScriptRoot\..

# Check if wrk.exe is available
$wrkPath = "tools\wrk.exe"
if (-not (Test-Path $wrkPath)) {
    Write-Host "wrk.exe not found. Downloading..."
    
    # Create tools directory if it doesn't exist
    if (-not (Test-Path "tools")) {
        New-Item -ItemType Directory -Path "tools" -Force | Out-Null
    }
    
    # Download wrk from a reliable source (adjust URL as needed)
    $wrkUrl = "https://github.com/wg/wrk/releases/download/4.2.0/wrk-4.2.0-windows-x64.zip"
    $zipPath = "tools\wrk.zip"
    
    try {
        Invoke-WebRequest -Uri $wrkUrl -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath "tools" -Force
        Remove-Item $zipPath -Force
        
        # Rename if needed
        if (Test-Path "tools\wrk.exe") {
            Write-Host "wrk.exe downloaded successfully."
        } else {
            Write-Host "wrk.exe not found after extraction. Please download manually."
            exit 1
        }
    } catch {
        Write-Host "Failed to download wrk: $_"
        Write-Host "Please download wrk manually from https://github.com/wg/wrk/releases"
        exit 1
    }
}

# Build the benchmark server
Write-Host "Building benchmark server..."
go build -o bin/p99_server.exe .\benchmark\latency\p99_server.go

if (-not $?) {
    Write-Host "Failed to build benchmark server"
    exit 1
}

# Start the server
$serverPort = 8765
$serverProcess = Start-Process -FilePath "bin\p99_server.exe" -ArgumentList "-port", $serverPort -PassThru -NoNewWindow

try {
    # Wait for the server to start
    Write-Host "Waiting for server to start..."
    Start-Sleep -Seconds 2
    
    # Warm up
    Write-Host "Warming up server..."
    & $wrkPath -t4 -c100 -d5s http://localhost:${serverPort}/v1/latest | Out-Null
    
    # Run the benchmark
    Write-Host "Running benchmark for /v1/latest endpoint..."
    Write-Host "======================================"
    & $wrkPath -t8 -c512 -d30s --latency http://localhost:${serverPort}/v1/latest
    Write-Host "======================================"
    
    Write-Host "Running benchmark for /v1/status endpoint..."
    Write-Host "======================================"
    & $wrkPath -t8 -c512 -d30s --latency http://localhost:${serverPort}/v1/status
    Write-Host "======================================"
    
    # Get metrics
    Write-Host "Server metrics:"
    $metrics = Invoke-WebRequest -Uri "http://localhost:${serverPort}/metrics" -UseBasicParsing
    Write-Host $metrics.Content
    
} finally {
    # Stop the server
    if (-not $serverProcess.HasExited) {
        Write-Host "Stopping server..."
        Stop-Process -Id $serverProcess.Id -Force
    }
}

Write-Host "`nBenchmark complete!"
Write-Host "Target: p99 ≤ 5 ms for in-region clients on cache-hit endpoints"
