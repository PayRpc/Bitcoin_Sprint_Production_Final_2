#!/usr/bin/env pwsh
# verify_p99_implementation.ps1 - Quick verification of the p99 implementation

param (
    [switch]$Verbose
)

# Ensure we're in the right directory
Set-Location $PSScriptRoot\..

# Define colors for output
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    else {
        $input | Write-Output
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

function Write-Success($message) {
    Write-ColorOutput Green "✅ $message"
}

function Write-Error($message) {
    Write-ColorOutput Red "❌ $message"
}

function Write-Info($message) {
    Write-ColorOutput Cyan "ℹ️ $message"
}

# Check if the fastpath package exists
if (Test-Path "internal\fastpath\fastpath.go") {
    Write-Success "Found fastpath package"
} else {
    Write-Error "fastpath package not found at internal\fastpath\fastpath.go"
    exit 1
}

# Check if the benchmark server exists
if (Test-Path "benchmark\latency\p99_server.go") {
    Write-Success "Found benchmark server"
} else {
    Write-Error "Benchmark server not found at benchmark\latency\p99_server.go"
    exit 1
}

# Run tests for the fastpath package
Write-Info "Running fastpath tests..."
$testOutput = go test -v ./internal/fastpath
if ($LASTEXITCODE -eq 0) {
    Write-Success "fastpath tests passed"
    if ($Verbose) {
        Write-Output $testOutput
    }
} else {
    Write-Error "fastpath tests failed"
    Write-Output $testOutput
    exit 1
}

# Run benchmarks for the fastpath package
Write-Info "Running fastpath benchmarks..."
$benchOutput = go test -bench=. -benchtime=1s ./internal/fastpath
Write-Output $benchOutput

# Check if the benchmark results meet our expectations
$nsPerOp = $benchOutput | Select-String "BenchmarkLatestHandler.*ns/op" | ForEach-Object { 
    if ($_ -match "(\d+) ns/op") {
        return [int]$matches[1]
    }
    return 0
}

if ($nsPerOp -gt 0) {
    $msPerOp = $nsPerOp / 1000000.0
    Write-Info "LatestHandler benchmark: $msPerOp ms/op"
    
    if ($msPerOp -le 1.0) {
        Write-Success "Benchmark results are excellent (sub-millisecond)"
    } elseif ($msPerOp -le 5.0) {
        Write-Success "Benchmark results meet the 5ms target"
    } else {
        Write-Error "Benchmark results exceed the 5ms target"
    }
} else {
    Write-Error "Could not parse benchmark results"
}

# Check allocations
$allocsPerOp = $benchOutput | Select-String "BenchmarkLatestHandler.*allocs/op" | ForEach-Object { 
    if ($_ -match "(\d+) allocs/op") {
        return [int]$matches[1]
    }
    return -1
}

if ($allocsPerOp -gt -1) {
    Write-Info "LatestHandler benchmark: $allocsPerOp allocs/op"
    
    if ($allocsPerOp -eq 0) {
        Write-Success "Zero allocations per operation - perfect!"
    } elseif ($allocsPerOp -le 2) {
        Write-Success "Very low allocations per operation"
    } else {
        Write-Error "Too many allocations per operation"
    }
} else {
    Write-Error "Could not parse allocation results"
}

# Check parallel benchmark
$parallelNsPerOp = $benchOutput | Select-String "BenchmarkLatestHandler_Parallel.*ns/op" | ForEach-Object { 
    if ($_ -match "(\d+) ns/op") {
        return [int]$matches[1]
    }
    return 0
}

if ($parallelNsPerOp -gt 0) {
    $parallelMsPerOp = $parallelNsPerOp / 1000000.0
    Write-Info "Parallel LatestHandler benchmark: $parallelMsPerOp ms/op"
    
    if ($parallelMsPerOp -le 5.0) {
        Write-Success "Parallel benchmark results meet the 5ms target"
    } else {
        Write-Error "Parallel benchmark results exceed the 5ms target"
    }
} else {
    Write-Error "Could not parse parallel benchmark results"
}

Write-Info "Verification complete. For full benchmarks, run: .\benchmark\latency\run_and_update_report.ps1"
