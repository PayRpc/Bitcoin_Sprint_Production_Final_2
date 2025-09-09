# PowerShell p99 latency benchmark - Multi-endpoint Version

function Test-Endpoint {
    param(
        [string]$EndpointName,
        [string]$Uri,
        [int]$Iterations = 1000,
        [int]$WarmupIterations = 100
    )

    Write-Host "`n===== Testing $EndpointName Endpoint ====="
    Write-Host "URL: $Uri"
    Write-Host "Warming up with $warmupIterations requests..."
    
    for ($i = 0; $i -lt $warmupIterations; $i++) {
        try {
            Invoke-RestMethod -Uri $Uri -Method Get | Out-Null
        } catch {
            # Ignore warmup errors
        }
    }

    Write-Host "Starting benchmark: $iterations sequential requests..."

$latencies = @()
$errors = 0
    $latencies = @()
    $errors = 0
    $totalSw = [System.Diagnostics.Stopwatch]::StartNew()

    for ($i = 0; $i -lt $iterations; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $null = Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec 5
            $sw.Stop()
            $latencies += $sw.Elapsed.TotalMilliseconds
        } catch {
            $sw.Stop()
            $errors++
        }
        
        if (($i + 1) % 100 -eq 0) {
            Write-Host "Completed $($i + 1) requests..."
        }
    }

    $totalSw.Stop()
    $totalTime = $totalSw.ElapsedMilliseconds

    # Calculate statistics
    $count = $latencies.Count
    $rps = [math]::Round($count * 1000 / $totalTime, 2)

$sortedLatencies = $validLatencies | Sort-Object
$min = if ($sortedLatencies.Count -gt 0) { $sortedLatencies[0] } else { 0 }
$max = if ($sortedLatencies.Count -gt 0) { $sortedLatencies[-1] } else { 0 }
$avg = if ($sortedLatencies.Count -gt 0) { ($sortedLatencies | Measure-Object -Average).Average } else { 0 }
$p50 = if ($sortedLatencies.Count -gt 0) { $sortedLatencies[[math]::Floor($count * 0.5)] } else { 0 }
$p90 = if ($sortedLatencies.Count -gt 0) { $sortedLatencies[[math]::Floor($count * 0.9)] } else { 0 }
$p99 = if ($sortedLatencies.Count -gt 0) { $sortedLatencies[[math]::Floor($count * 0.99)] } else { 0 }

Write-Host "`nBenchmark Results:"
Write-Host "=================="
Write-Host "Total Requests:    $count (Errors: $errorCount)"
Write-Host "Total Time:        $totalTime ms"
Write-Host "Requests/second:   $rps"
Write-Host "`nLatency (ms):"
Write-Host "  min:             $min"
Write-Host "  avg:             $([math]::Round($avg, 2))"
Write-Host "  max:             $max"
Write-Host "  p50 (median):    $p50"
Write-Host "  p90:             $p90"
Write-Host "  p99:             $p99"

Write-Host "`nTarget Validation:"
if ($p99 -le 5) {
    Write-Host "✅ SUCCESS: p99 latency ($p99 ms) is within the 5ms target!" -ForegroundColor Green
} else {
    Write-Host "❌ FAILED: p99 latency ($p99 ms) exceeds the 5ms target." -ForegroundColor Red
}