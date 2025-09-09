param(
    [int]$DurationSec = 600,
    [switch]$Force,            # allow killing existing instances if you really want
    [int]$PreferredPort = 9000, # default, but we'll auto-pick a free one if taken
    [string]$LogLevel = "info",
    [switch]$UseRealEndpoints, # Use real ethereum/solana endpoints instead of placeholders
    [switch]$Verbose,          # Show more details during test run
    [string]$DeduplicationTier = "ENTERPRISE", # Acceleration layer tier (ENTERPRISE, BUSINESS, FREE)
    [switch]$EnableAcceleration = $true,       # Enable acceleration layer by default
    [switch]$EnableMLOptimization = $true      # Enable ML-based optimization
)

$ErrorActionPreference = 'Stop'

function Write-ColorLog {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$ForegroundColor = "White",
        
        [Parameter(Mandatory=$false)]
        [switch]$NoNewLine
    )
    
    if ($Verbose) {
        Write-Host $Message -ForegroundColor $ForegroundColor -NoNewline:$NoNewLine
    }
}

function Get-FreeTcpPort {
    $maxAttempts = 10
    $attempt = 0
    
    while ($attempt -lt $maxAttempts) {
        try {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $listener.Start()
            $port = ($listener.LocalEndpoint).Port
            $listener.Stop()
            
            # Verify port is actually free
            if (-not (Is-Port-In-Use -Port $port)) {
                return $port
            }
        } catch {
            Write-ColorLog "Port selection error: $_" "Yellow"
        }
        
        $attempt++
        Start-Sleep -Milliseconds 100
    }
    
    # Fallback to a random port in the high range
    return Get-Random -Minimum 49152 -Maximum 65535
}

function Is-Port-In-Use([int]$Port) {
    try {
        $connections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        return ($connections -ne $null -and $connections.Count -gt 0)
    } catch {
        return $false
    }
}

# Determine workspace paths
$scriptPath = $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptPath
$ws = Split-Path -Parent $root
Set-Location $ws

# Setup run timestamp (used throughout script)
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$runId = [guid]::NewGuid().ToString("N").Substring(0, 8)

# Create well-organized directory structure for test results
$logsDir = Join-Path $ws 'logs'
$testRunDir = Join-Path $logsDir "smoke-test-$timestamp-$runId"
if (!(Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir | Out-Null }
if (!(Test-Path $testRunDir)) { New-Item -ItemType Directory -Path $testRunDir | Out-Null }

# Define log files with proper namespacing
$appLogPath = Join-Path $testRunDir "app.log"
$errLogPath = Join-Path $testRunDir "error.log"
$healthLogPath = Join-Path $testRunDir "health.log"
$summaryPath = Join-Path $testRunDir "summary.txt"
$configPath = Join-Path $testRunDir "config.json"
$metricsPath = Join-Path $testRunDir "metrics.csv"

# Detect existing bitcoin-sprint instances and port availability
$existingProcesses = Get-Process -Name "bitcoin-sprint" -ErrorAction SilentlyContinue
$apiPortInUse = Is-Port-In-Use -Port $PreferredPort
$healthPort = $PreferredPort + 1
$healthPortInUse = Is-Port-In-Use -Port $healthPort
$metricsPort = 9090
$metricsPortInUse = Is-Port-In-Use -Port $metricsPort

# Make intelligent port selection decisions
if (($apiPortInUse -or $healthPortInUse) -and -not $Force) {
    Write-Host "Port $PreferredPort or health port $healthPort is in use." -ForegroundColor Yellow
    Write-Host "Finding a free port range for the smoke test..." -ForegroundColor Yellow
    
    # Find a range of free ports
    $TestPort = Get-FreeTcpPort
    $HealthPort = $TestPort + 1
    
    # Verify health port is also free, if not try again
    if (Is-Port-In-Use -Port $HealthPort) {
        $TestPort = Get-FreeTcpPort
        $HealthPort = $TestPort + 1
    }
    
    # Final verification
    if ((Is-Port-In-Use -Port $TestPort) -or (Is-Port-In-Use -Port $HealthPort)) {
        Write-Host "Error: Could not find free port range. Please check system port usage." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Selected API port: $TestPort, Health port: $HealthPort" -ForegroundColor Green
} elseif (($apiPortInUse -or $healthPortInUse) -and $Force) {
    Write-Host "Force enabled: stopping existing processes using ports $PreferredPort and $healthPort..." -ForegroundColor Red
    
    if ($apiPortInUse) {
        $procUsingApiPort = Get-NetTCPConnection -LocalPort $PreferredPort -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($procUsingApiPort) { 
            try { Stop-Process -Id $procUsingApiPort.OwningProcess -Force }
            catch { Write-Host "Warning: Failed to kill process on port $PreferredPort" -ForegroundColor Yellow }
        }
    }
    
    if ($healthPortInUse) {
        $procUsingHealthPort = Get-NetTCPConnection -LocalPort $healthPort -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($procUsingHealthPort) { 
            try { Stop-Process -Id $procUsingHealthPort.OwningProcess -Force }
            catch { Write-Host "Warning: Failed to kill process on port $healthPort" -ForegroundColor Yellow }
        }
    }
    
    Start-Sleep -Seconds 1
    $TestPort = $PreferredPort
    $HealthPort = $healthPort
} else {
    $TestPort = $PreferredPort
    $HealthPort = $healthPort
    
    Write-Host "Using default port: $TestPort, Health port: $HealthPort" -ForegroundColor Green
}

# Write config details to log for troubleshooting
Write-Host "====== SMOKE TEST CONFIGURATION ======" -ForegroundColor Cyan
Write-Host "Test ID: $runId" -ForegroundColor Cyan
Write-Host "Duration: $($DurationSec/60) minutes" -ForegroundColor Cyan
Write-Host "API Port: $TestPort" -ForegroundColor Cyan
Write-Host "Health Port: $HealthPort" -ForegroundColor Cyan
Write-Host "Log level: $LogLevel" -ForegroundColor Cyan
Write-Host "Acceleration: $($EnableAcceleration -eq $true ? 'Enabled' : 'Disabled')" -ForegroundColor Cyan
Write-Host "Dedup Tier: $DeduplicationTier" -ForegroundColor Cyan
Write-Host "ML Optimization: $($EnableMLOptimization -eq $true ? 'Enabled' : 'Disabled')" -ForegroundColor Cyan
Write-Host "Log directory: $testRunDir" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

# Create a well-formed configuration file for this run
$exePath = Join-Path $ws "bitcoin-sprint.exe"
if (!(Test-Path $exePath)) { 
    Write-Host "ERROR: Executable not found: $exePath" -ForegroundColor Red
    exit 1
}

# Prepare environment variables with configuration
$env:RUN_ID = $runId # Use the consistent runId generated earlier
$env:TEST_RUN = "true"

# Create a comprehensive smoke test configuration
$envFilePath = Join-Path $testRunDir "env.smoketest"

# Ethereum and Solana endpoint selection - prioritize non-3rd party providers
$ethHttpEndpoints = if ($UseRealEndpoints) { 
    @(
        # Primary endpoints - professional grade, non-3rd party where possible
        "https://eth-rpc.nethermind.io",               # Nethermind (professional grade)
        "https://gateway.fm/eth/rpc",                  # Gateway.fm (professional grade)
        "https://rpc.flashbots.net",                   # Flashbots RPC (professional)
        
        # Backup endpoints - only used if primary endpoints fail
        "https://ethereum.publicnode.com",             # Public node (decent reliability)
        "https://cloudflare-eth.com",                  # Cloudflare (reliable but rate-limited)
        
        # Last resort - 3rd party providers we're competing against
        "https://rpc.ankr.com/eth"                     # Ankr as final fallback
    ) 
} else { 
    @("http://127.0.0.1:8545") 
}

$ethWsEndpoints = if ($UseRealEndpoints) { 
    @(
        # Primary endpoints - professional grade, non-3rd party where possible
        "wss://eth-ws.nethermind.io",                 # Nethermind WS (professional)
        "wss://gateway.fm/eth/ws",                    # Gateway.fm WS (professional)
        
        # Public endpoints as backup
        "wss://ethereum.publicnode.com",              # Public node WS (decent reliability)
        
        # Last resort - 3rd party providers we're competing against
        "wss://rpc.ankr.com/eth/ws"                   # Ankr as backup
    ) 
} else { 
    @("ws://127.0.0.1:8546") 
}

$solanaRpcEndpoints = if ($UseRealEndpoints) { 
    @("https://api.mainnet-beta.solana.com", "https://rpc.ankr.com/solana") 
} else { 
    @("http://127.0.0.1:8899") 
}

$solanaWsEndpoints = if ($UseRealEndpoints) { 
    @("wss://api.mainnet-beta.solana.com", "wss://rpc.ankr.com/solana/ws") 
} else { 
    @("ws://127.0.0.1:8900") 
}

# Create configuration files
$envContents = @(
    "# Bitcoin Sprint Smoke Test Configuration ($timestamp)",
    "# Test ID: $runId",
    "",
    "# Core configuration",
    "TIER=enterprise",
    "LOG_LEVEL=$LogLevel",
    "RUN_ID=$runId",
    "RUN_MODE=test",
    "TEST_RUN=true",
    "",
    "# API Configuration",
    "API_HOST=127.0.0.1",
    "API_PORT=$TestPort",
    "API_BIND=127.0.0.1:$TestPort",
    "ADMIN_PORT=$($TestPort+1)",
    "HEALTH_PORT=$HealthPort",
    "PROMETHEUS_PORT=$($TestPort+10)",
    "",
    "# Optimization settings",
    "RATE_LIMIT_FACTOR=0.25",
    "MAX_CONCURRENT_REQUESTS=50",
    "CONNECTION_TIMEOUT_SEC=15",
    "",
    "# ETH endpoints",
    "ETH_HTTP_URL=$($ethHttpEndpoints[0])",
    "ETH_WS_URL=$($ethWsEndpoints[0])",
    "ETH_TIMEOUT=15s",
    "ETH_MAX_CONNECTIONS=5",
    "ETH_USE_ACCELERATION=true",
    "ETH_RETRY_ATTEMPTS=3",
    "",
    "# Solana endpoints",
    "SOL_RPC_URL=$($solanaRpcEndpoints[0])",
    "SOLANA_TIMEOUT=15s",
    "SOLANA_MAX_CONNECTIONS=3",
    "SOL_USE_ACCELERATION=true",
    "",
    "# JSON array configurations",
    "ETH_RPC_ENDPOINTS=$(ConvertTo-Json $ethHttpEndpoints -Compress)",
    "ETH_WS_ENDPOINTS=$(ConvertTo-Json $ethWsEndpoints -Compress)",
    "SOLANA_RPC_ENDPOINTS=$(ConvertTo-Json $solanaRpcEndpoints -Compress)",
    "SOLANA_WS_ENDPOINTS=$(ConvertTo-Json $solanaWsEndpoints -Compress)",
    "",
    "# Sprint Acceleration Layer configuration",
    "ACCELERATION_ENABLED=$($EnableAcceleration -eq $true ? 'true' : 'false')",
    "DEDUPLICATION_TIER=$DeduplicationTier",
    "CROSS_NETWORK_DEDUP=$($DeduplicationTier -eq 'ENTERPRISE' ? 'true' : 'false')",
    "INTELLIGENT_EVICTION=$($DeduplicationTier -ne 'FREE' ? 'true' : 'false')",
    "NETWORK_SPECIFIC_TTL=true",
    "DEDUP_CAPACITY=$($DeduplicationTier -eq 'ENTERPRISE' ? 20480 : ($DeduplicationTier -eq 'BUSINESS' ? 8192 : 2048))",
    "ADAPTIVE_OPTIMIZATION=$($EnableMLOptimization -eq $true -and $DeduplicationTier -ne 'FREE' ? 'true' : 'false')",
    "",
    "# Network-specific acceleration optimizations",
    "ETH_ACCELERATION_TTL=300", # 5 minutes for Ethereum
    "ETH_BLOCK_PRIORITY=8",
    "ETH_ENDPOINT_ROTATION_STRATEGY=reliability", # Use most reliable endpoints first
    "ETH_ENDPOINT_MAX_FAILURES=3", # Circuit breaker threshold
    "ETH_ENDPOINT_COOLDOWN_SEC=60", # Time before retry after failure
    "ETH_ENDPOINT_HEALTH_CHECK_INTERVAL=30", # Check endpoint health every 30 seconds
    "ETH_REQUEST_TIMEOUT=15", # Timeout for Ethereum requests
    "SOL_ACCELERATION_TTL=100", # 100 seconds for Solana (faster blocks)
    "SOL_BLOCK_PRIORITY=6",
    "",
    "# Latency flattening configuration",
    "LATENCY_FLATTENING_ENABLED=true",
    "PREDICTIVE_CACHING_ENABLED=$($DeduplicationTier -eq 'ENTERPRISE' ? 'true' : 'false')",
    "ENDPOINT_CIRCUIT_BREAKER=true",
    "MULTI_PEER_REDUNDANCY=$($DeduplicationTier -eq 'ENTERPRISE' ? 'true' : 'false')",
    "PARALLEL_REQUEST_THRESHOLD=200", # For high-priority requests, query multiple endpoints
    "RESPONSE_VERIFICATION_MODE=full", # Verify responses across multiple endpoints
    "SMART_BATCHING_ENABLED=true", # Intelligent request batching for better performance
    "COMPETITIVE_EDGE_MODE=true", # Enable all competitive features against 3rd parties
    "",
    "# Ensure we don't use hardcoded ports",
    "HTTP_PORT=$TestPort",
    "BITCOIN_SPRINT_HTTP_PORT=$TestPort",
    "BITCOIN_SPRINT_API_PORT=$TestPort",
    "BITCOIN_SPRINT_PROFILE=smoke"
)

# Write the configuration file
$envContents | Out-File -FilePath $envFilePath -Encoding utf8

# Also write to the app's expected location
$tempEnvPath = Join-Path $ws ".env.smoketest-$TestPort"
$envContents | Out-File -FilePath $tempEnvPath -Encoding utf8

# Save the configuration as JSON for the summary
$configJson = @{
    test_id = $runId
    timestamp = $timestamp
    api_port = $TestPort
    health_port = $HealthPort
    log_level = $LogLevel
    duration_sec = $DurationSec
    use_real_endpoints = $UseRealEndpoints
    eth_endpoints = $ethHttpEndpoints
    sol_endpoints = $solanaRpcEndpoints
    # Acceleration Layer settings
    acceleration_enabled = $EnableAcceleration
    deduplication_tier = $DeduplicationTier
    ml_optimization = $EnableMLOptimization
    cross_network_dedup = ($DeduplicationTier -eq 'ENTERPRISE')
    intelligent_eviction = ($DeduplicationTier -ne 'FREE')
} | ConvertTo-Json -Depth 3
$configJson | Out-File -FilePath $configPath -Encoding utf8

# No command line arguments needed, will use environment variables
$procArgs = ""

try {
    # Set environment variables to point to our configuration
    $env:BITCOIN_SPRINT_ENV_FILE = $tempEnvPath
    $env:ENV_FILE = $tempEnvPath
    
    # Set important runtime environment variables directly
    $env:API_PORT = "$TestPort"
    $env:HTTP_PORT = "$TestPort"
    $env:API_BIND = "127.0.0.1:$TestPort"
    $env:HEALTH_PORT = "$HealthPort"
    $env:LOG_LEVEL = "$LogLevel"
    $env:RUN_MODE = "test"
    $env:TEST_RUN = "true"
    $env:RUN_ID = "$runId"
    
    # For better diagnostics, show what's being launched
    Write-Host "Starting bitcoin-sprint.exe with configuration:" -ForegroundColor Cyan
    Write-Host "- Port: $TestPort" -ForegroundColor Cyan
    Write-Host "- Health Port: $HealthPort" -ForegroundColor Cyan
    Write-Host "- Config file: $tempEnvPath" -ForegroundColor Cyan
    Write-Host "- Log level: $LogLevel" -ForegroundColor Cyan
    Write-Host "- Run ID: $runId" -ForegroundColor Cyan
    
    # Launch with arguments and environment variables
    $proc = Start-Process -FilePath $exePath -ArgumentList $procArgs -WorkingDirectory $ws -NoNewWindow -PassThru `
        -RedirectStandardOutput $appLogPath -RedirectStandardError $errLogPath
    
    if ($proc -eq $null -or $proc.HasExited) {
        Write-Host "ERROR: Failed to start bitcoin-sprint.exe process" -ForegroundColor Red
        if (Test-Path $errLogPath) {
            Write-Host "Error log content:" -ForegroundColor Red
            Get-Content -Path $errLogPath | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        }
        exit 1
    }
    
    Write-Host "Process started with PID: $($proc.Id)" -ForegroundColor Green
    Write-Host "Using env file: $tempEnvPath" -ForegroundColor Green
    Write-Host "Logs directory: $testRunDir" -ForegroundColor Green
} 
catch {
    Write-Host "ERROR: Exception when starting process: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}

# Wait a short warmup before first probe
Start-Sleep -Seconds 5

$target = [TimeSpan]::FromSeconds($DurationSec)
$interval = [TimeSpan]::FromSeconds(30)
$swatch = [System.Diagnostics.Stopwatch]::StartNew()

# Define health endpoints with fallback options
$mainApiUrl = "http://127.0.0.1:$TestPort"
$healthApiUrl = "http://127.0.0.1:$HealthPort"
$apiHealthPath = "/health"
$adminHealthPath = "/admin/health"
$readinessPath = "/readiness"

# Create list of endpoints to try
$healthEndpoints = @(
    "$healthApiUrl$apiHealthPath",
    "$mainApiUrl$apiHealthPath",
    "$mainApiUrl$adminHealthPath",
    "$healthApiUrl$adminHealthPath",
    "$mainApiUrl$readinessPath",
    "$healthApiUrl$readinessPath"
)

"Start: $(Get-Date -Format o) on API port $TestPort, health port $HealthPort" | Out-File -FilePath $healthLogPath -Encoding utf8

# Wait for initial readiness on the chosen port
$deadline = (Get-Date).AddSeconds(60) # Longer initial wait
$serviceReady = $false
$workingHealthUrl = ""

# Try each health endpoint until we find one that works
Write-Host "Checking for service readiness..." -ForegroundColor Yellow
while ((Get-Date) -lt $deadline -and -not $serviceReady) {
    foreach ($healthUrl in $healthEndpoints) {
        try {
            Write-Host "Trying endpoint: $healthUrl" -ForegroundColor Yellow
            $resp = Invoke-RestMethod -Method GET -Uri $healthUrl -TimeoutSec 3 -ErrorAction SilentlyContinue
            if ($resp) { 
                $status = if ($resp.status) { $resp.status } elseif ($resp.health) { $resp.health } else { "unknown" }
                if ($status -eq "ok" -or $status -eq "ready" -or $status -eq "UP") {
                    $serviceReady = $true
                    $workingHealthUrl = $healthUrl
                    Write-Host "Service is ready on $healthUrl (status: $status)" -ForegroundColor Green
                    "$(Get-Date -Format o) Service ready on $healthUrl (status: $status)" | Out-File -FilePath $healthLogPath -Append -Encoding utf8
                    break
                }
                Write-Host "Service responded but status is: $status" -ForegroundColor Yellow
            }
        } catch { 
            # Quietly continue to next endpoint
        }
    }
    
    if (-not $serviceReady) {
        Write-Host "Waiting for service to be ready..." -ForegroundColor Yellow
        Start-Sleep -Milliseconds 1000
    }
}

if (-not $serviceReady) {
    Write-Host "WARNING: Service did not report ready status within 60 seconds" -ForegroundColor Red
    Write-Host "Proceeding with monitoring anyway using main port $TestPort" -ForegroundColor Yellow
    $workingHealthUrl = "$mainApiUrl$apiHealthPath" # Default to main API port
}

# Health check loop
Write-Host "Starting health check monitoring at $workingHealthUrl" -ForegroundColor Cyan
"$(Get-Date -Format o) Starting health monitoring at $workingHealthUrl" | Out-File -FilePath $healthLogPath -Append -Encoding utf8

$healthCheckInterval = [TimeSpan]::FromSeconds(15)
$lastCheck = [DateTime]::MinValue

while ($swatch.Elapsed -lt $target -and -not ($proc.HasExited)) {
    $now = [DateTime]::Now
    
    # Only check at the specified interval
    if (($now - $lastCheck) -ge $healthCheckInterval) {
        $lastCheck = $now
        
        try {
            $resp = Invoke-WebRequest -Uri $workingHealthUrl -UseBasicParsing -TimeoutSec 5
            $responseSize = if ($resp.RawContentLength) { $resp.RawContentLength } else { $resp.Content.Length }
            "$(Get-Date -Format o) 200 $responseSize" | Out-File -FilePath $healthLogPath -Append -Encoding utf8
            
            # If we're at a 5-minute interval, print status to console
            if (($swatch.Elapsed.TotalMinutes % 5) -lt 0.25) {
                Write-Host "[$([Math]::Floor($swatch.Elapsed.TotalMinutes))m] Service health: OK" -ForegroundColor Green
            }
        } catch {
            $errorMessage = $_.Exception.Message
            "$(Get-Date -Format o) ERROR $errorMessage" | Out-File -FilePath $healthLogPath -Append -Encoding utf8
            
            # Always show errors in the console
            Write-Host "[$([Math]::Floor($swatch.Elapsed.TotalMinutes))m] Health check error: $errorMessage" -ForegroundColor Yellow
        }
    }
    
    # If process has exited unexpectedly, log it
    if ($proc.HasExited) {
        $exitCode = $proc.ExitCode
        $errorMsg = "Process exited unexpectedly with code: $exitCode"
        Write-Host $errorMsg -ForegroundColor Red
        "$(Get-Date -Format o) FATAL $errorMsg" | Out-File -FilePath $healthLogPath -Append -Encoding utf8
        break
    }
    
    # Small sleep to prevent CPU spiking in the loop
    Start-Sleep -Milliseconds 500
}

$swatch.Stop()
$testEndTime = Get-Date

# Try to collect final metrics before shutdown
Write-Host "Test duration completed. Collecting final metrics..." -ForegroundColor Cyan

# Try to collect application metrics
$metricsCollected = $false
$appMetrics = $null
try {
    $metricsUrl = "http://127.0.0.1:$($TestPort+10)/metrics"
    Write-Host "Collecting metrics from $metricsUrl" -ForegroundColor Yellow
    $appMetrics = Invoke-RestMethod -Method GET -Uri $metricsUrl -TimeoutSec 5
    "$(Get-Date -Format o) Collected $(($appMetrics -split "`n").Length) metrics lines" | Out-File -FilePath $healthLogPath -Append -Encoding utf8
    $appMetrics | Out-File -FilePath $metricsPath -Encoding utf8
    $metricsCollected = $true
} catch {
    Write-Host "Failed to collect metrics: $($_.Exception.Message)" -ForegroundColor Yellow
    "$(Get-Date -Format o) Failed to collect metrics: $($_.Exception.Message)" | Out-File -FilePath $healthLogPath -Append -Encoding utf8
}

# Try multiple shutdown endpoints
$shutdownAttempted = $false
$shutdownEndpoints = @(
    "http://127.0.0.1:$TestPort/shutdown",
    "http://127.0.0.1:$TestPort/admin/shutdown",
    "http://127.0.0.1:$HealthPort/shutdown"
)

foreach ($shutdownUrl in $shutdownEndpoints) {
    if (-not $proc.HasExited) {
        try {
            Write-Host "Attempting clean shutdown via $shutdownUrl..." -ForegroundColor Cyan
            Invoke-RestMethod -Method POST -Uri $shutdownUrl -TimeoutSec 3 -ErrorAction SilentlyContinue | Out-Null
            $shutdownAttempted = $true
            Start-Sleep -Seconds 2
            if ($proc.HasExited) {
                Write-Host "Clean shutdown successful via $shutdownUrl" -ForegroundColor Green
                break
            }
        } catch {
            # Continue to next endpoint
        }
    }
}

# Stop the process if still running
if (-not $proc.HasExited) {
    Write-Host "Clean shutdown failed. Stopping process (PID=$($proc.Id))..." -ForegroundColor Yellow
    try { 
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue 
        Start-Sleep -Seconds 1
        if (-not $proc.HasExited) {
            Write-Host "Process didn't exit after Stop-Process. Using more force..." -ForegroundColor Yellow
            taskkill /F /PID $proc.Id 2>$null
        }
    } catch {}
}

# Verify process is actually terminated
if (-not $proc.HasExited) {
    Write-Host "WARNING: Process appears to be still running!" -ForegroundColor Red
}

# Small delay to ensure buffers flushed
Start-Sleep -Seconds 2

# Clean up temporary env file
if (Test-Path $tempEnvPath) {
    Remove-Item -Path $tempEnvPath -Force -ErrorAction SilentlyContinue
}

# Generate detailed summary
Write-Host "Generating test summary..." -ForegroundColor Cyan

# Analyze logs
$btcPeers = 0
$btcHandshakes = 0
$ethConnected = 0
$ethReconnects = 0
$solConnected = 0
$solBadHandshake = 0
$errors = 0
$warnings = 0

if (Test-Path $appLogPath) {
    $btcPeers = (Select-String -Path $appLogPath -Pattern "(?i)peer connection established|connected to peer|new peer:" -AllMatches | Measure-Object).Count
    $btcHandshakes = (Select-String -Path $appLogPath -Pattern "(?i)bitcoin protocol handshake completed|handshake completed" -AllMatches | Measure-Object).Count
    $ethConnected = (Select-String -Path $appLogPath -Pattern "(?i)connected to ethereum endpoint|eth relay connected" -AllMatches | Measure-Object).Count
    $ethReconnects = (Select-String -Path $appLogPath -Pattern "(?i)reconnect|reconnecting to ethereum|re-establishing eth" -AllMatches | Measure-Object).Count
    $solConnected = (Select-String -Path $appLogPath -Pattern "(?i)connected to solana endpoint|sol relay connected" -AllMatches | Measure-Object).Count
    $solBadHandshake = (Select-String -Path $appLogPath -Pattern "(?i)websocket: bad handshake" -AllMatches | Measure-Object).Count
    $errors = (Select-String -Path $appLogPath -Pattern "(?i)\b(error|fatal|panic)\b" -AllMatches | Measure-Object).Count
    $warnings = (Select-String -Path $appLogPath -Pattern "(?i)\b(warning|warn)\b" -AllMatches | Measure-Object).Count
}

if (Test-Path $errLogPath) {
    $errors += (Select-String -Path $errLogPath -Pattern "(?i)\b(error|fatal|panic)\b" -AllMatches | Measure-Object).Count
    $warnings += (Select-String -Path $errLogPath -Pattern "(?i)\b(warning|warn)\b" -AllMatches | Measure-Object).Count
}

$duration = [Math]::Round($swatch.Elapsed.TotalSeconds,2)

# Format endpoint data for summary
$ethHttpEndpointsFormatted = $ethHttpEndpoints | ForEach-Object { ($_ -replace '(https?://[^/]{10}).*(.{5}$)', '$1...$2') }
$solRpcEndpointsFormatted = $solanaRpcEndpoints | ForEach-Object { ($_ -replace '(https?://[^/]{10}).*(.{5}$)', '$1...$2') }

# Get health check stats
$healthOkCount = 0
$healthFailCount = 0
$healthChecks = $null

if (Test-Path $healthLogPath) {
    $healthChecks = Get-Content -Path $healthLogPath
    $healthOkCount = ($healthChecks | Select-String -Pattern "(?i) 200 " -AllMatches | Measure-Object).Count
    $healthFailCount = ($healthChecks | Select-String -Pattern "(?i) ERR " -AllMatches | Measure-Object).Count
}

# Create a more detailed and well-formatted summary
$summaryContent = @"
# Bitcoin Sprint Smoke Test Summary

## Test Information
- **Run ID**: $runId
- **Date**: $($testEndTime.ToString('yyyy-MM-dd HH:mm:ss'))
- **Duration**: $($duration)s ($([Math]::Round($duration/60, 1)) minutes)
- **API Port**: $TestPort
- **Health Port**: $HealthPort

## Test Environment
- **Test Directory**: $testRunDir
- **Log Level**: $LogLevel
- **Real Endpoints**: $($UseRealEndpoints -eq $true ? "Yes" : "No")

## Connection Information
- **Ethereum HTTP**: $(($ethHttpEndpointsFormatted -join ", "))
- **Solana RPC**: $(($solRpcEndpointsFormatted -join ", "))

## Health Check Statistics
- **Total Checks**: $($healthOkCount + $healthFailCount)
- **Successful**: $healthOkCount
- **Failed**: $healthFailCount
- **Success Rate**: $([Math]::Round(100 * $healthOkCount / [Math]::Max(1, ($healthOkCount + $healthFailCount)), 1))%

## Connection Stats
- **Bitcoin**: $btcPeers peers, $btcHandshakes handshakes
- **Ethereum**: $ethConnected connections, $ethReconnects reconnects
- **Solana**: $solConnected connections, $solBadHandshake bad handshakes

## Acceleration Layer Stats
- **Deduplication Tier**: $DeduplicationTier
- **ML Optimization**: $($EnableMLOptimization -eq $true ? "Enabled" : "Disabled")
- **Cross-Network Dedup**: $($DeduplicationTier -eq 'ENTERPRISE' ? "Enabled" : "Disabled")

## Log Analysis
- **Errors**: $errors
- **Warnings**: $warnings
- **Metrics Collected**: $($metricsCollected -eq $true ? "Yes ($([int]($appMetrics.Length / 1024)) KB)" : "No")

## Files
- **Application Log**: $(Split-Path $appLogPath -Leaf)
- **Error Log**: $(Split-Path $errLogPath -Leaf)
- **Health Log**: $(Split-Path $healthLogPath -Leaf)
- **Metrics**: $(if ($metricsCollected) { Split-Path $metricsPath -Leaf } else { "Not available" })

## Test Outcome
**Status**: $(if($errors -eq 0 -and $healthFailCount -lt ($healthOkCount * 0.1)) {'✅ SUCCESS'} else {'⚠️ ISSUES DETECTED'})
"@

$summaryContent | Out-File -FilePath $summaryPath -Encoding utf8

# Display summary to console
Write-Host "" -ForegroundColor White
Write-Host "================ TEST SUMMARY ================" -ForegroundColor Cyan
Write-Host "Run ID: $runId" -ForegroundColor Cyan
Write-Host "Duration: $($duration)s ($([Math]::Round($duration/60, 1)) minutes)" -ForegroundColor Cyan
Write-Host "Health checks: $healthOkCount successful, $healthFailCount failed" -ForegroundColor Cyan
Write-Host "Errors: $errors, Warnings: $warnings" -ForegroundColor Cyan

if ($errors -gt 0 -or $healthFailCount -gt ($healthOkCount * 0.1)) {
    Write-Host "OUTCOME: ⚠️ ISSUES DETECTED" -ForegroundColor Yellow
} else {
    Write-Host "OUTCOME: ✅ SUCCESS" -ForegroundColor Green
}

Write-Host "Test logs path: $testRunDir" -ForegroundColor White
Write-Host "Summary file: $summaryPath" -ForegroundColor White
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "" -ForegroundColor White

# Return the summary path for caller
return $summaryPath
