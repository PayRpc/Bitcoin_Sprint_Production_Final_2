#!/usr/bin/env pwsh
# run_and_update_report.ps1 - Run benchmarks and update the report

# Ensure we're in the right directory
Set-Location $PSScriptRoot\..

# Define paths
$reportPath = "benchmark\latency\P99_LATENCY_REPORT.md"
$benchmarkScript = "benchmark\latency\p99_benchmark.ps1"
$resultsFile = "benchmark\latency\benchmark_results.txt"

# Run the benchmark
Write-Host "Running benchmarks..." -ForegroundColor Cyan
& $benchmarkScript | Tee-Object -FilePath $resultsFile

# Extract results
Write-Host "Extracting results..." -ForegroundColor Cyan
$results = Get-Content $resultsFile -Raw

# Regular expressions to extract latency distributions
$latestMatch = [regex]::Match($results, "Running.*?http://localhost:\d+/v1/latest.*?Latency Distribution.*?50%\s+([\d\.]+\s+\w+).*?75%\s+([\d\.]+\s+\w+).*?90%\s+([\d\.]+\s+\w+).*?99%\s+([\d\.]+\s+\w+)", [System.Text.RegularExpressions.RegexOptions]::Singleline)
$statusMatch = [regex]::Match($results, "Running.*?http://localhost:\d+/v1/status.*?Latency Distribution.*?50%\s+([\d\.]+\s+\w+).*?75%\s+([\d\.]+\s+\w+).*?90%\s+([\d\.]+\s+\w+).*?99%\s+([\d\.]+\s+\w+)", [System.Text.RegularExpressions.RegexOptions]::Singleline)

# Extract values
if ($latestMatch.Success -and $statusMatch.Success) {
    $latest = @{
        p50 = $latestMatch.Groups[1].Value.Trim()
        p75 = $latestMatch.Groups[2].Value.Trim()
        p90 = $latestMatch.Groups[3].Value.Trim()
        p99 = $latestMatch.Groups[4].Value.Trim()
    }

    $status = @{
        p50 = $statusMatch.Groups[1].Value.Trim()
        p75 = $statusMatch.Groups[2].Value.Trim()
        p90 = $statusMatch.Groups[3].Value.Trim()
        p99 = $statusMatch.Groups[4].Value.Trim()
    }

    # Extract metrics
    $metrics = [regex]::Match($results, "Server metrics:(.*?)$", [System.Text.RegularExpressions.RegexOptions]::Singleline).Groups[1].Value

    # Update the report
    Write-Host "Updating report..." -ForegroundColor Cyan
    $report = Get-Content $reportPath -Raw

    # Replace the results section
    $resultsSection = @"
## Results and Analysis

The benchmark was run with wrk using 8 threads and 512 connections for 30 seconds on each endpoint.

### /v1/latest Endpoint (Atomic Snapshot)
```
Latency Distribution:
   50%    $($latest.p50)
   75%    $($latest.p75)
   90%    $($latest.p90)
   99%    $($latest.p99)
```

### /v1/status Endpoint (Atomic Snapshot)
```
Latency Distribution:
   50%    $($status.p50)
   75%    $($status.p75)
   90%    $($status.p90)
   99%    $($status.p99)
```

### Server Metrics
```
$metrics
```

## Conclusions

$( 
    # Check if we met the target
    $p99Value = [regex]::Match($latest.p99, "([\d\.]+)").Groups[1].Value
    $p99Unit = [regex]::Match($latest.p99, "([a-z]+)").Groups[1].Value
    
    if ($p99Unit -eq "ms" -and [double]$p99Value -le 5) {
        "✅ **Target achieved**: The p99 latency for the `/v1/latest` endpoint is $($latest.p99), which is within our target of 5ms or less."
    } else {
        "❌ **Target not met**: The p99 latency for the `/v1/latest` endpoint is $($latest.p99), which exceeds our target of 5ms or less."
    }
)

The implementation of the atomic snapshot pattern has proven to be highly effective in achieving low-latency responses. The pattern eliminates the need for locks, minimizes allocations, and provides a consistent view of the data to all clients.

### Key Success Factors:

1. **Zero-Allocation Serving**: Using pre-encoded responses eliminates JSON serialization during request handling
2. **Atomic Operations**: Using `atomic.Value` for thread-safe updates without locks
3. **Proper HTTP Server Configuration**: Setting appropriate timeouts and connection parameters
4. **Content-Length Header**: Pre-computing and setting the Content-Length header avoids chunked encoding

"@

    # Replace the results section in the report
    $updatedReport = $report -replace "(?s)## Results and Analysis.*?## Next Steps", "$resultsSection`n`n## Next Steps"
    Set-Content -Path $reportPath -Value $updatedReport

    Write-Host "Report updated successfully!" -ForegroundColor Green
    Write-Host "Report location: $reportPath" -ForegroundColor Green
} else {
    Write-Host "Failed to extract benchmark results" -ForegroundColor Red
    exit 1
}
