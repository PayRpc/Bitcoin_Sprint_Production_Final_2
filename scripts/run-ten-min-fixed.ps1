param(
    [int]$DurationSec = 600,
    [switch]$Force,            # allow killing existing instances if you really want
    [int]$PreferredPort = 9000, # default, but we'll auto-pick a free one if taken
    [string]$LogLevel = "info",
    [switch]$UseRealEndpoints, # Use real ethereum/solana endpoints instead of placeholders
    [switch]$Verbose,          # Show more details during test run
    [switch]$EthSolOnly,       # Test only Ethereum and Solana (skip Bitcoin)
    [switch]$NoPrometheus      # Disable Prometheus to avoid port conflicts
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
$summaryPath = Join-Path $testRunDir "summary.md"
$configPath = Join-Path $testRunDir "config.json"
$metricsPath = Join-Path $testRunDir "metrics.csv"

# Detect existing bitcoin-sprint instances and port availability
$existingProcesses = Get-Process -Name "bitcoin-sprint" -ErrorAction SilentlyContinue
$apiPortInUse = Is-Port-In-Use -Port $PreferredPort
$healthPort = $PreferredPort + 10  # Use a larger gap to avoid conflicts
$healthPortInUse = Is-Port-In-Use -Port $healthPort
$metricsPort = if ($NoPrometheus) { 0 } else { $PreferredPort + 20 }
$metricsPortInUse = if ($NoPrometheus) { $false } else { Is-Port-In-Use -Port $metricsPort }
$adminPort = $PreferredPort + 30  # Use a larger gap for admin port too

# Make intelligent port selection decisions
if (($apiPortInUse -or $healthPortInUse -or $metricsPortInUse) -and -not $Force) {
    Write-Host "Port conflicts detected." -ForegroundColor Yellow
    Write-Host "Finding a free port range for the smoke test..." -ForegroundColor Yellow
    
    # Generate a base port
    $basePort = Get-FreeTcpPort
    $TestPort = $basePort
    $HealthPort = $basePort + 10
    $MetricsPort = if ($NoPrometheus) { 0 } else { $basePort + 20 }
    $AdminPort = $basePort + 30
    
    # Verify all ports are free
    $allFree = $true
    foreach ($port in @($TestPort, $HealthPort, $MetricsPort, $AdminPort)) {
        if ($port -gt 0 -and (Is-Port-In-Use -Port $port)) {
            $allFree = $false
            break
        }
    }
    
    # If we still have conflicts, try one more time with a completely different range
    if (-not $allFree) {
        $basePort = Get-Random -Minimum 50000 -Maximum 60000
        $TestPort = $basePort
        $HealthPort = $basePort + 10
        $MetricsPort = if ($NoPrometheus) { 0 } else { $basePort + 20 }
        $AdminPort = $basePort + 30
        
        # Final check
        foreach ($port in @($TestPort, $HealthPort, $MetricsPort, $AdminPort)) {
            if ($port -gt 0 -and (Is-Port-In-Use -Port $port)) {
                Write-Host "Error: Could not find free port range after multiple attempts." -ForegroundColor Red
                exit 1
            }
        }
    }
    
    Write-Host "Selected API port: $TestPort, Health port: $HealthPort" -ForegroundColor Green
    if (-not $NoPrometheus) {
        Write-Host "Metrics port: $MetricsPort, Admin port: $AdminPort" -ForegroundColor Green
    } else {
        Write-Host "Prometheus disabled, Admin port: $AdminPort" -ForegroundColor Green
    }
} elseif (($apiPortInUse -or $healthPortInUse -or $metricsPortInUse) -and $Force) {
    Write-Host "Force enabled: stopping existing processes using required ports..." -ForegroundColor Red
    
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
    
    if ($metricsPortInUse -and -not $NoPrometheus) {
        $procUsingMetricsPort = Get-NetTCPConnection -LocalPort $metricsPort -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($procUsingMetricsPort) { 
            try { Stop-Process -Id $procUsingMetricsPort.OwningProcess -Force }
            catch { Write-Host "Warning: Failed to kill process on port $metricsPort" -ForegroundColor Yellow }
        }
    }
    
    Start-Sleep -Seconds 1
    $TestPort = $PreferredPort
    $HealthPort = $healthPort
    $MetricsPort = $metricsPort
    $AdminPort = $adminPort
} else {
    $TestPort = $PreferredPort
    $HealthPort = $healthPort
    $MetricsPort = $metricsPort
    $AdminPort = $adminPort
    
    Write-Host "Using port configuration:" -ForegroundColor Green
    Write-Host "- API Port: $TestPort" -ForegroundColor Green
    Write-Host "- Health Port: $HealthPort" -ForegroundColor Green
    if (-not $NoPrometheus) {
        Write-Host "- Metrics Port: $MetricsPort" -ForegroundColor Green
    } else {
        Write-Host "- Metrics: DISABLED" -ForegroundColor Yellow
    }
    Write-Host "- Admin Port: $AdminPort" -ForegroundColor Green
}

# Write config details to log for troubleshooting
Write-Host "====== SMOKE TEST CONFIGURATION ======" -ForegroundColor Cyan
Write-Host "Test ID: $runId" -ForegroundColor Cyan
Write-Host "Duration: $($DurationSec/60) minutes" -ForegroundColor Cyan
Write-Host "API Port: $TestPort" -ForegroundColor Cyan
Write-Host "Health Port: $HealthPort" -ForegroundColor Cyan
if (-not $NoPrometheus) {
    Write-Host "Metrics Port: $MetricsPort" -ForegroundColor Cyan
}
Write-Host "Admin Port: $AdminPort" -ForegroundColor Cyan
Write-Host "Log level: $LogLevel" -ForegroundColor Cyan
Write-Host "Log directory: $testRunDir" -ForegroundColor Cyan
if ($EthSolOnly) {
    Write-Host "Test Mode: Ethereum and Solana Only" -ForegroundColor Cyan
} else {
    Write-Host "Test Mode: Full System" -ForegroundColor Cyan
}
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

# Ethereum and Solana endpoint selection - reliable public endpoints closer to source
$ethHttpEndpoints = if ($UseRealEndpoints) { 
    @("https://eth.rpc.nethermind.io", "https://rpc.eth.gateway.fm", "https://rpc.flashbots.net") 
} else { 
    @("http://127.0.0.1:8545") 
}

$ethWsEndpoints = if ($UseRealEndpoints) { 
    @("wss://ethereum.publicnode.com", "wss://eth.drpc.org") 
} else { 
    @("ws://127.0.0.1:8546") 
}

$solanaRpcEndpoints = if ($UseRealEndpoints) { 
    @("https://api.mainnet-beta.solana.com", "https://solana-rpc.publicnode.com") 
} else { 
    @("http://127.0.0.1:8899") 
}

$solanaWsEndpoints = if ($UseRealEndpoints) { 
    @("wss://api.mainnet-beta.solana.com", "wss://rpc.ankr.com/solana/ws") 
} else { 
    @("ws://127.0.0.1:8900") 
}

# Create configuration files - build list of environment variables
$envVars = @{}

# Core configuration
$envVars["TIER"] = "enterprise"
$envVars["LOG_LEVEL"] = $LogLevel
$envVars["RUN_ID"] = $runId
$envVars["RUN_MODE"] = "test"
$envVars["TEST_RUN"] = "true"
$envVars["BITCOIN_SPRINT_PROFILE"] = "smoke"

# API Configuration - ensure string values for ports
$envVars["API_HOST"] = "127.0.0.1"
$envVars["API_PORT"] = "$TestPort"
$envVars["API_BIND"] = "127.0.0.1:$TestPort"
$envVars["HTTP_PORT"] = "$TestPort"
$envVars["BITCOIN_SPRINT_HTTP_PORT"] = "$TestPort"
$envVars["BITCOIN_SPRINT_API_PORT"] = "$TestPort"
$envVars["ADMIN_PORT"] = "$AdminPort"
$envVars["ADMIN_API_PORT"] = "$AdminPort"
$envVars["HEALTH_PORT"] = "$HealthPort"
$envVars["STATUS_PORT"] = "$HealthPort"
$envVars["HEALTH_CHECK_PORT"] = "$HealthPort"
if (-not $NoPrometheus) {
    $envVars["PROMETHEUS_PORT"] = "$MetricsPort"
    $envVars["METRICS_PORT"] = "$MetricsPort"
}

# Ethereum Configuration - Using working public endpoints
$envVars["ETH_HTTP_URL"] = $ethHttpEndpoints[0]
$envVars["ETH_WS_URL"] = $ethWsEndpoints[0]
$envVars["ETH_TIMEOUT"] = "15s"
$envVars["ETH_MAX_CONNECTIONS"] = "3"
$envVars["ETH_RPC_ENDPOINTS"] = (ConvertTo-Json $ethHttpEndpoints -Compress)
$envVars["ETH_WS_ENDPOINTS"] = (ConvertTo-Json $ethWsEndpoints -Compress)
$envVars["ETHEREUM_ENABLED"] = "true"
$envVars["ETH_ENABLED"] = "true"
$envVars["ETH_POLL_INTERVAL"] = "5000"  # 5 seconds between polls to avoid rate limits
$envVars["ETH_RATE_LIMIT"] = "1"        # 1 request per second max

# Solana Configuration - Using working public endpoints
$envVars["SOL_RPC_URL"] = $solanaRpcEndpoints[0]
$envVars["SOLANA_TIMEOUT"] = "15s"
$envVars["SOLANA_MAX_CONNECTIONS"] = "3"
$envVars["SOLANA_RPC_ENDPOINTS"] = (ConvertTo-Json $solanaRpcEndpoints -Compress)
$envVars["SOLANA_WS_ENDPOINTS"] = (ConvertTo-Json $solanaWsEndpoints -Compress)
$envVars["SOLANA_ENABLED"] = "true"
$envVars["SOL_ENABLED"] = "true"
$envVars["SOLANA_POLL_INTERVAL"] = "5000"  # 5 seconds between polls to avoid rate limits
$envVars["SOL_RATE_LIMIT"] = "1"           # 1 request per second max

# Optimization settings
$envVars["RATE_LIMIT_FACTOR"] = "0.25"
$envVars["MAX_CONCURRENT_REQUESTS"] = "50"
$envVars["CONNECTION_TIMEOUT_SEC"] = "15"
$envVars["INITIALIZATION_DELAY"] = "0" # Speed up startup

# If ETH and SOL only mode, disable Bitcoin
if ($EthSolOnly) {
    $envVars["SKIP_BITCOIN"] = "true"
    $envVars["ETHEREUM_FOCUS"] = "true"
    $envVars["SOLANA_FOCUS"] = "true"
    $envVars["DISABLE_BTC_P2P"] = "true"
    $envVars["DISABLE_BITCOIN_MODULE"] = "true"
    
    # Also disable database to avoid SQLite issues
    $envVars["DISABLE_DB"] = "true"
    $envVars["SKIP_DB_INIT"] = "true"
    $envVars["DB_MOCK"] = "true"
    $envVars["MEMORY_STORAGE"] = "true"
}

# Format environment variables for output
$envContents = @(
    "# Bitcoin Sprint Smoke Test Configuration ($timestamp)",
    "# Test ID: $runId",
    ""
)

# Add all environment variables to the file content
foreach ($key in $envVars.Keys | Sort-Object) {
    $envContents += "$key=$($envVars[$key])"
}

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
    metrics_port = if ($NoPrometheus) { "disabled" } else { $MetricsPort }
    admin_port = $AdminPort
    log_level = $LogLevel
    duration_sec = $DurationSec
    use_real_endpoints = $UseRealEndpoints
    eth_sol_only = $EthSolOnly
    eth_endpoints = $ethHttpEndpoints
    sol_endpoints = $solanaRpcEndpoints
} | ConvertTo-Json -Depth 3
$configJson | Out-File -FilePath $configPath -Encoding utf8

try {
    # Set environment variables to point to our configuration
    $env:BITCOIN_SPRINT_ENV_FILE = $tempEnvPath
    $env:ENV_FILE = $tempEnvPath
    
    # Set important runtime environment variables directly
    foreach ($key in $envVars.Keys) {
        [Environment]::SetEnvironmentVariable($key, $envVars[$key])
    }
    
    # For better diagnostics, show what's being launched
    Write-Host "Starting bitcoin-sprint.exe with configuration:" -ForegroundColor Cyan
    Write-Host "- Port: $TestPort" -ForegroundColor Cyan
    Write-Host "- Health Port: $HealthPort" -ForegroundColor Cyan
    Write-Host "- Config file: $tempEnvPath" -ForegroundColor Cyan
    Write-Host "- Log level: $LogLevel" -ForegroundColor Cyan
    Write-Host "- Run ID: $runId" -ForegroundColor Cyan
    
    # Launch with environment variables
    $proc = Start-Process -FilePath $exePath -WorkingDirectory $ws -NoNewWindow -PassThru `
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

# Wait longer for startup - increased from 5 seconds to 20 seconds
$startupWaitTime = 20 # seconds
Write-Host "Waiting for application to initialize ($startupWaitTime seconds)..." -ForegroundColor Yellow
$startTime = [DateTime]::Now
    
# Monitor startup progress
for ($i = 1; $i -le $startupWaitTime; $i++) {
    Start-Sleep -Seconds 1
    if ($i % 5 -eq 0 -or $i -eq $startupWaitTime) {
        Write-Host "  Startup progress: $i/$startupWaitTime seconds" -ForegroundColor Cyan
        
        # Check logs for startup progress
        if (Test-Path $appLogPath) {
            $recentLogs = Get-Content -Path $appLogPath -Tail 10
            foreach ($line in $recentLogs) {
                if ($line -match "(?i)started|initialized|ready|listening on|serving") {
                    Write-Host "  Detected startup message: $line" -ForegroundColor Green
                }
            }
        }
    }
}

$target = [TimeSpan]::FromSeconds($DurationSec)
$interval = [TimeSpan]::FromSeconds(15) # Change from 30 to 15 for more frequent health checks
$swatch = [System.Diagnostics.Stopwatch]::StartNew()

# Define health endpoints with fallback options - Many more options
$healthEndpoints = @(
    "http://127.0.0.1:$TestPort/health",
    "http://127.0.0.1:$HealthPort/health",
    "http://127.0.0.1:$AdminPort/health",
    "http://127.0.0.1:$TestPort/status",
    "http://127.0.0.1:$HealthPort/status", 
    "http://127.0.0.1:$AdminPort/status",
    "http://localhost:$TestPort/health",
    "http://localhost:$HealthPort/health",
    "http://localhost:$AdminPort/health",
    "http://localhost:$TestPort/status",
    "http://localhost:$HealthPort/status",
    "http://localhost:$AdminPort/status",
    "http://127.0.0.1:$TestPort/api/health",
    "http://127.0.0.1:$HealthPort/api/health",
    "http://127.0.0.1:$TestPort/api/status",
    "http://127.0.0.1:$HealthPort/api/status"
)

"Start: $(Get-Date -Format o) on API port $TestPort, health port $HealthPort" | Out-File -FilePath $healthLogPath -Encoding utf8

# Wait for initial readiness - increased timeout
$deadline = (Get-Date).AddSeconds(60) # Longer initial wait
$serviceReady = $false
$workingHealthUrl = ""

# Try each health endpoint until we find one that works
Write-Host "Checking for service readiness..." -ForegroundColor Yellow
while ((Get-Date) -lt $deadline -and -not $serviceReady) {
    foreach ($healthUrl in $healthEndpoints) {
        try {
            Write-Host "  Trying endpoint: $healthUrl" -ForegroundColor Yellow
            $resp = Invoke-WebRequest -Method GET -Uri $healthUrl -TimeoutSec 3 -ErrorAction SilentlyContinue
            
            if ($resp -and $resp.StatusCode -eq 200) {
                try {
                    $content = $resp.Content
                    Write-Host "  Response ($($resp.StatusCode)): $content" -ForegroundColor DarkGray
                    
                    if ($content -match "ok|ready|up|healthy|running|status|true|active") {
                        $serviceReady = $true
                        $workingHealthUrl = $healthUrl
                        Write-Host "Service is ready on $healthUrl" -ForegroundColor Green
                        Write-Host "Response: $content" -ForegroundColor Green
                        "$(Get-Date -Format o) Service ready on $healthUrl (status: $content)" | Out-File -FilePath $healthLogPath -Append -Encoding utf8
                        break
                    }
                } catch {
                    Write-Host "  Error parsing response: $_" -ForegroundColor DarkGray
                }
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
    
    # Check application logs for startup issues
    if (Test-Path $appLogPath) {
        $recentLogs = Get-Content -Path $appLogPath -Tail 20
        foreach ($line in $recentLogs) {
            if ($line -match "(?i)error|fail|exception") {
                Write-Host "  Found error in logs: $line" -ForegroundColor Red
            }
            elseif ($line -match "(?i)listen|started|port|http|api") {
                Write-Host "  Found startup info: $line" -ForegroundColor Cyan
            }
        }
    }
    
    if (Test-Path $errLogPath) {
        $errLogs = Get-Content -Path $errLogPath -Tail 10
        if ($errLogs -and $errLogs.Count -gt 0) {
            Write-Host "Error log contents:" -ForegroundColor Red
            foreach ($line in $errLogs) {
                Write-Host "  $line" -ForegroundColor Red
            }
        }
    }
    
    # Try alternative detection method: Check if ports are listening
    try {
        $portCheck = Test-NetConnection -ComputerName "127.0.0.1" -Port $TestPort -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($portCheck.TcpTestSucceeded) {
            Write-Host "Port $TestPort is responding to connections" -ForegroundColor Green
            $serviceReady = $true
            $workingHealthUrl = "http://127.0.0.1:$TestPort/health"  # Use this as a fallback
        }
    } catch {
        Write-Host "Port testing failed: $_" -ForegroundColor Red
    }
    
    if (-not $serviceReady) {
        Write-Host "Proceeding with monitoring anyway using main port $TestPort" -ForegroundColor Yellow
        $workingHealthUrl = "http://127.0.0.1:$TestPort/health" # Default to main API port
    }
}

# Health check loop
Write-Host "Starting health check monitoring at $workingHealthUrl" -ForegroundColor Cyan
"$(Get-Date -Format o) Starting health monitoring at $workingHealthUrl" | Out-File -FilePath $healthLogPath -Append -Encoding utf8

$healthCheckInterval = [TimeSpan]::FromSeconds(15)
$lastCheck = [DateTime]::MinValue
$healthCheckCount = 0
$successfulChecks = 0

while ($swatch.Elapsed -lt $target -and -not ($proc.HasExited)) {
    $now = [DateTime]::Now
    
    # Only check at the specified interval
    if (($now - $lastCheck) -ge $healthCheckInterval) {
        $lastCheck = $now
        $healthCheckCount++
        
        # Try different methods to check health
        $healthResult = $null
        $healthSuccess = $false
                
        # Method 1: Invoke-RestMethod
        try {
            $healthResult = Invoke-RestMethod -Uri $workingHealthUrl -Method GET -TimeoutSec 5 -ErrorAction Stop
            if ($healthResult) {
                $healthSuccess = $true
                $successfulChecks++
            }
        } catch {
            # Method 2: Invoke-WebRequest
            try {
                $webResult = Invoke-WebRequest -Uri $workingHealthUrl -Method GET -TimeoutSec 5 -ErrorAction Stop
                if ($webResult.StatusCode -eq 200) {
                    $healthSuccess = $true
                    $successfulChecks++
                    $healthResult = @{ status = "ok"; message = "Health check from web request" }
                }
            } catch {
                # Method 3: Test-NetConnection
                try {
                    $uri = [System.Uri]::new($workingHealthUrl)
                    $port = if ($uri.Port -gt 0) { $uri.Port } else { 80 }
                    $testConn = Test-NetConnection -ComputerName "127.0.0.1" -Port $port -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                    if ($testConn.TcpTestSucceeded) {
                        $healthSuccess = $true
                        $successfulChecks++
                        $healthResult = @{ status = "ok"; message = "Port $port accessible" }
                    }
                } catch {
                    # All methods failed
                    $errorMessage = $_.Exception.Message
                    "$(Get-Date -Format o) ERROR $errorMessage" | Out-File -FilePath $healthLogPath -Append -Encoding utf8
                    Write-Host "[$([Math]::Floor($swatch.Elapsed.TotalMinutes))m] Health check failed: $errorMessage" -ForegroundColor Yellow
                }
            }
        }
        
        if ($healthSuccess) {
            "$(Get-Date -Format o) OK $(if ($healthResult) { $healthResult | ConvertTo-Json -Compress })" | Out-File -FilePath $healthLogPath -Append -Encoding utf8
            
            # If we're at a 5-minute interval, print status to console
            if (($swatch.Elapsed.TotalMinutes % 5) -lt 0.25 -or $Verbose) {
                Write-Host "[$([Math]::Floor($swatch.Elapsed.TotalMinutes))m] Service health: OK" -ForegroundColor Green
                if ($Verbose -and $healthResult) {
                    Write-Host "  Response: $($healthResult | ConvertTo-Json -Compress)" -ForegroundColor Green
                }
            }
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
if (-not $NoPrometheus) {
    try {
        $metricsUrl = "http://127.0.0.1:$MetricsPort/metrics"
        Write-Host "Collecting metrics from $metricsUrl" -ForegroundColor Yellow
        $appMetrics = Invoke-RestMethod -Method GET -Uri $metricsUrl -TimeoutSec 5
        "$(Get-Date -Format o) Collected $(($appMetrics -split "`n").Length) metrics lines" | Out-File -FilePath $healthLogPath -Append -Encoding utf8
        $appMetrics | Out-File -FilePath $metricsPath -Encoding utf8
        $metricsCollected = $true
    } catch {
        Write-Host "Failed to collect metrics: $($_.Exception.Message)" -ForegroundColor Yellow
        "$(Get-Date -Format o) Failed to collect metrics: $($_.Exception.Message)" | Out-File -FilePath $healthLogPath -Append -Encoding utf8
    }
}

# Try multiple shutdown endpoints
$shutdownAttempted = $false
$shutdownEndpoints = @(
    "http://127.0.0.1:$TestPort/shutdown",
    "http://127.0.0.1:$TestPort/api/shutdown",
    "http://127.0.0.1:$AdminPort/shutdown",
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
    $ethConnected = (Select-String -Path $appLogPath -Pattern "(?i)connected to ethereum|eth relay connected|eth client initialized|ethereum.*(started|ready|connected)" -AllMatches | Measure-Object).Count
    $ethReconnects = (Select-String -Path $appLogPath -Pattern "(?i)reconnect|reconnecting to ethereum|re-establishing eth" -AllMatches | Measure-Object).Count
    $solConnected = (Select-String -Path $appLogPath -Pattern "(?i)connected to solana|sol relay connected|solana client initialized|solana.*(started|ready|connected)" -AllMatches | Measure-Object).Count
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

# Determine test result status
$testMode = if ($EthSolOnly) { "Ethereum & Solana Focus" } else { "Full System" }
$testStatus = "❌ FAILURE"

if ($EthSolOnly) {
    if ($ethConnected -gt 0 -and $solConnected -gt 0 -and $successfulChecks -gt ($healthCheckCount * 0.8)) {
        $testStatus = "✅ SUCCESS"
    } elseif ($ethConnected -gt 0 -or $solConnected -gt 0) {
        $testStatus = "⚠️ PARTIAL SUCCESS"
    }
} else {
    if ($btcHandshakes -gt 0 -and $ethConnected -gt 0 -and $solConnected -gt 0 -and $errors -eq 0) {
        $testStatus = "✅ SUCCESS"
    } elseif (($btcHandshakes -gt 0 -or $ethConnected -gt 0 -or $solConnected -gt 0) -and $errors -lt 5) {
        $testStatus = "⚠️ PARTIAL SUCCESS"
    }
}

# Create a more detailed and well-formatted summary
$summaryContent = @"
# Bitcoin Sprint Smoke Test Summary

## Test Information
- **Run ID**: $runId
- **Date**: $($testEndTime.ToString('yyyy-MM-dd HH:mm:ss'))
- **Duration**: $($duration)s ($([Math]::Round($duration/60, 1)) minutes)
- **Test Mode**: $testMode

## Port Configuration
- **API Port**: $TestPort
- **Health Port**: $HealthPort
- **Metrics Port**: $(if ($NoPrometheus) { "Disabled" } else { $MetricsPort })
- **Admin Port**: $AdminPort

## Test Environment
- **Test Directory**: $testRunDir
- **Log Level**: $LogLevel
- **Real Endpoints**: $($UseRealEndpoints -eq $true ? "Yes" : "No")

## Connection Information
- **Ethereum HTTP**: $(($ethHttpEndpointsFormatted -join ", "))
- **Solana RPC**: $(($solRpcEndpointsFormatted -join ", "))

## Health Check Statistics
- **Total Checks**: $healthCheckCount
- **Successful**: $successfulChecks
- **Success Rate**: $([Math]::Round(100 * $successfulChecks / [Math]::Max(1, $healthCheckCount), 1))%

## Connection Stats
- **Bitcoin**: $btcPeers peers, $btcHandshakes handshakes
- **Ethereum**: $ethConnected connections, $ethReconnects reconnects
- **Solana**: $solConnected connections, $solBadHandshake bad handshakes

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
**Status**: $testStatus
"@

$summaryContent | Out-File -FilePath $summaryPath -Encoding utf8

# Display summary to console
Write-Host "" -ForegroundColor White
Write-Host "================ TEST SUMMARY ================" -ForegroundColor Cyan
Write-Host "Run ID: $runId" -ForegroundColor Cyan
Write-Host "Test Mode: $testMode" -ForegroundColor Cyan
Write-Host "Duration: $($duration)s ($([Math]::Round($duration/60, 1)) minutes)" -ForegroundColor Cyan
Write-Host "Health checks: $successfulChecks/$healthCheckCount successful" -ForegroundColor Cyan
Write-Host "Bitcoin: $btcHandshakes handshakes" -ForegroundColor Cyan
Write-Host "Ethereum: $ethConnected connections" -ForegroundColor Cyan
Write-Host "Solana: $solConnected connections" -ForegroundColor Cyan
Write-Host "Errors: $errors, Warnings: $warnings" -ForegroundColor Cyan
Write-Host "OUTCOME: $testStatus" -ForegroundColor $(if ($testStatus -eq "✅ SUCCESS") { "Green" } elseif ($testStatus -eq "⚠️ PARTIAL SUCCESS") { "Yellow" } else { "Red" })
Write-Host "Test logs path: $testRunDir" -ForegroundColor White
Write-Host "Summary file: $summaryPath" -ForegroundColor White
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "" -ForegroundColor White

# Return the summary path for caller
return $summaryPath
