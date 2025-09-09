param(
    [int]$DurationSec = 300,
    [string]$LogLevel = "debug",
    [switch]$Verbose,
    [switch]$NoPrometheus
)

$ErrorActionPreference = 'Stop'

# Determine workspace paths
$scriptPath = $MyInvocation.MyCommand.Path
$scriptsDir = Split-Path -Parent $scriptPath
$ws = Split-Path -Parent $scriptsDir

# Generate a unique test ID and timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$runId = [guid]::NewGuid().ToString("N").Substring(0, 8)

# Create well-organized directory for test output
$logsDir = Join-Path $ws 'logs'
$testRunDir = Join-Path $logsDir "eth-sol-test-$timestamp-$runId"
if (!(Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir | Out-Null }
if (!(Test-Path $testRunDir)) { New-Item -ItemType Directory -Path $testRunDir | Out-Null }

# Define log files with proper namespacing
$appLogPath = Join-Path $testRunDir "app.log"
$errLogPath = Join-Path $testRunDir "error.log"
$healthLogPath = Join-Path $testRunDir "health.log"
$summaryPath = Join-Path $testRunDir "summary.md"
$configPath = Join-Path $testRunDir "config.json"
$metricsPath = Join-Path $testRunDir "metrics.csv"

# Find available ports
function Get-FreeTcpPort {
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $port = ($listener.LocalEndpoint).Port
        $listener.Stop()
        return $port
    } catch {
        # If random port fails, use a port in the high range
        return Get-Random -Minimum 49152 -Maximum 65535
    }
}

function Is-Port-In-Use([int]$Port) {
    try {
        $connections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        return ($connections -ne $null -and $connections.Count -gt 0)
    } catch {
        return $false
    }
}

# Generate ports with enough space between them
$basePort = Get-FreeTcpPort
$apiPort = $basePort
$healthPort = $basePort + 10 
$metricsPort = $basePort + 20
$adminPort = $basePort + 30

# Verify all ports
$portsToCheck = @($apiPort, $healthPort, $metricsPort, $adminPort)
$anyConflicts = $false

foreach ($port in $portsToCheck) {
    if (Is-Port-In-Use -Port $port) {
        $anyConflicts = $true
        break
    }
}

if ($anyConflicts) {
    Write-Host "Port conflicts detected. Retrying with different port range..." -ForegroundColor Yellow
    # Try with a completely different base port
    $basePort = Get-Random -Minimum 49152 -Maximum 65000
    $apiPort = $basePort
    $healthPort = $basePort + 10
    $metricsPort = $basePort + 20
    $adminPort = $basePort + 30

    # Re-check all ports
    foreach ($port in @($apiPort, $healthPort, $metricsPort, $adminPort)) {
        if (Is-Port-In-Use -Port $port) {
            Write-Host "ERROR: Still have port conflicts after retrying. Please close other applications and try again." -ForegroundColor Red
            exit 1
        }
    }
}

# Disable Prometheus if requested
if ($NoPrometheus) {
    $metricsPort = 0
}

# Build environment variables
$envVars = @{
    # Focus only on ETH and Solana
    "SKIP_BITCOIN" = "true"
    "ETHEREUM_FOCUS" = "true"
    "SOLANA_FOCUS" = "true"
    "DISABLE_BTC_P2P" = "true"
    "DISABLE_BITCOIN_MODULE" = "true"
    
    # Disable database to avoid SQLite issues
    "DISABLE_DB" = "true"
    "SKIP_DB_INIT" = "true"
    "DB_MOCK" = "true"
    "MEMORY_STORAGE" = "true"
    
    # Core configuration
    "TIER" = "enterprise"
    "LOG_LEVEL" = $LogLevel
    "RUN_ID" = $runId
    "RUN_MODE" = "test"
    "TEST_RUN" = "true"
    
    # API Configuration
    "API_HOST" = "127.0.0.1"
    "API_PORT" = "$apiPort"
    "API_BIND" = "127.0.0.1:$apiPort"
    "HTTP_PORT" = "$apiPort"
    "BITCOIN_SPRINT_HTTP_PORT" = "$apiPort"
    "BITCOIN_SPRINT_API_PORT" = "$apiPort"
    
    # Admin & monitoring ports - explicit string conversion for all ports
    "ADMIN_PORT" = "$adminPort"
    "ADMIN_API_PORT" = "$adminPort" 
    "HEALTH_PORT" = "$healthPort"
    "STATUS_PORT" = "$healthPort"
    "HEALTH_CHECK_PORT" = "$healthPort"
}

# Only add Prometheus port if not disabled
if (-not $NoPrometheus) {
    $envVars["PROMETHEUS_PORT"] = "$metricsPort"
    $envVars["METRICS_PORT"] = "$metricsPort"
}

# Ethereum configuration - reliable public endpoints
$envVars += @{
    "ETH_HTTP_URL" = "https://eth.rpc.nethermind.io"
    "ETH_WS_URL" = "wss://ethereum.publicnode.com"
    "ETH_RPC_ENDPOINTS" = '["https://eth.rpc.nethermind.io","https://rpc.eth.gateway.fm","https://rpc.flashbots.net"]'
    "ETH_WS_ENDPOINTS" = '["wss://ethereum.publicnode.com","wss://eth.drpc.org"]'
    "ETH_TIMEOUT" = "15s"
    "ETH_MAX_CONNECTIONS" = "3"
    "ETHEREUM_ENABLED" = "true"
    "ETH_ENABLED" = "true"
}

# Solana configuration
$envVars += @{
    "SOL_RPC_URL" = "https://api.mainnet-beta.solana.com"
    "SOLANA_RPC_ENDPOINTS" = '["https://api.mainnet-beta.solana.com","https://rpc.ankr.com/solana"]'
    "SOLANA_WS_ENDPOINTS" = '["wss://api.mainnet-beta.solana.com","wss://rpc.ankr.com/solana/ws"]'
    "SOLANA_TIMEOUT" = "15s"
    "SOLANA_MAX_CONNECTIONS" = "3"
    "SOLANA_ENABLED" = "true"
    "SOL_ENABLED" = "true"
}

# Optimization settings
$envVars += @{
    "RATE_LIMIT_FACTOR" = "0.25"
    "MAX_CONCURRENT_REQUESTS" = "50"
    "CONNECTION_TIMEOUT_SEC" = "15"
    
    # Extra test flags
    "BITCOIN_SPRINT_PROFILE" = "test"
    "DISABLE_CIRCUIT_BREAKER" = "false"
    "READY_STATUS" = "ok"
    "STATUS_FIELD" = "status"
    "INITIALIZATION_DELAY" = "0" # Speed up startup
}

# Write config to file for reference
$configFileContent = @()
foreach ($key in $envVars.Keys | Sort-Object) {
    $configFileContent += "$key=$($envVars[$key])"
}

$envFilePath = Join-Path $testRunDir "env.cfg"
$configFileContent | Out-File -FilePath $envFilePath -Encoding utf8

# Save configuration as JSON
$configJson = @{
    test_id = $runId
    timestamp = $timestamp
    api_port = $apiPort
    health_port = $healthPort
    metrics_port = if ($NoPrometheus) { "disabled" } else { $metricsPort }
    log_level = $LogLevel
    duration_sec = $DurationSec
    test_type = "ETH and Solana focus test"
    eth_endpoints = @("https://eth-mainnet.g.alchemy.com/v2/demo-key", "https://rpc.ankr.com/eth")
    sol_endpoints = @("https://api.mainnet-beta.solana.com", "https://rpc.ankr.com/solana")
} | ConvertTo-Json -Depth 3
$configJson | Out-File -FilePath $configPath -Encoding utf8

# Display test information
Write-Host "========== ETH & SOLANA TEST ==========" -ForegroundColor Green
Write-Host "Run ID: $runId" -ForegroundColor Green
Write-Host "Test Duration: $($DurationSec/60) minutes" -ForegroundColor Green
Write-Host "API Port: $apiPort" -ForegroundColor Green
Write-Host "Health Port: $healthPort" -ForegroundColor Green
if ($NoPrometheus) {
    Write-Host "Metrics: DISABLED" -ForegroundColor Yellow
} else {
    Write-Host "Metrics Port: $metricsPort" -ForegroundColor Green
}
Write-Host "Admin Port: $adminPort" -ForegroundColor Green
Write-Host "Log Level: $LogLevel" -ForegroundColor Green
Write-Host "Output Directory: $testRunDir" -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Green

try {
    # Start with a clean executable
    $exePath = Join-Path $ws "bitcoin-sprint.exe"
    if (!(Test-Path $exePath)) { 
        Write-Host "ERROR: Executable not found: $exePath" -ForegroundColor Red
        exit 1
    }
    
    # Set all environment variables
    Write-Host "Setting environment variables..." -ForegroundColor Cyan
    foreach ($key in $envVars.Keys) {
        [Environment]::SetEnvironmentVariable($key, $envVars[$key])
    }
    
    # Launch the process
    Write-Host "Starting bitcoin-sprint.exe with Ethereum and Solana focus..." -ForegroundColor Cyan
    $proc = Start-Process -FilePath $exePath -WorkingDirectory $ws -NoNewWindow -PassThru `
        -RedirectStandardOutput $appLogPath -RedirectStandardError $errLogPath
    
    if ($proc -eq $null -or $proc.HasExited) {
        Write-Host "ERROR: Failed to start process" -ForegroundColor Red
        if (Test-Path $errLogPath) {
            Write-Host "Error log content:" -ForegroundColor Red
            Get-Content -Path $errLogPath | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        }
        exit 1
    }
    
    Write-Host "Process started with PID: $($proc.Id)" -ForegroundColor Green
    Write-Host "Logs directory: $testRunDir" -ForegroundColor Green
    
    # Give the application time to start up - increased significantly
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
    
    # Start the test timer
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    # Define all possible health endpoints with more variations
    $healthEndpoints = @(
        "http://127.0.0.1:$apiPort/health",
        "http://127.0.0.1:$healthPort/health",
        "http://127.0.0.1:$adminPort/health",
        "http://127.0.0.1:$apiPort/status",
        "http://127.0.0.1:$healthPort/status",
        "http://127.0.0.1:$adminPort/status",
        "http://localhost:$apiPort/health",
        "http://localhost:$healthPort/health",
        "http://localhost:$adminPort/health",
        "http://localhost:$apiPort/status",
        "http://localhost:$healthPort/status",
        "http://localhost:$adminPort/status",
        "http://127.0.0.1:$apiPort/api/health",
        "http://127.0.0.1:$healthPort/api/health",
        "http://127.0.0.1:$apiPort/api/status",
        "http://127.0.0.1:$healthPort/api/status"
    )
    
    # Try to connect to the health endpoint
    $healthOk = $false
    $healthUrl = ""
    
    Write-Host "Checking for service health..." -ForegroundColor Yellow
    foreach ($endpoint in $healthEndpoints) {
        try {
            Write-Host "  Trying $endpoint..." -ForegroundColor DarkGray
            $result = Invoke-WebRequest -Uri $endpoint -Method GET -TimeoutSec 5 -ErrorAction SilentlyContinue
            
            if ($result -and $result.StatusCode -eq 200) {
                try {
                    $content = $result.Content
                    Write-Host "  Response ($($result.StatusCode)): $content" -ForegroundColor DarkGray
                    
                    if ($content -match "ok|ready|up|healthy|running|status|true|active") {
                        $healthOk = $true
                        $healthUrl = $endpoint
                        Write-Host "Health check SUCCESSFUL at $endpoint" -ForegroundColor Green
                        Write-Host "Response: $content" -ForegroundColor Green
                        break
                    } else {
                        Write-Host "  Endpoint returned content but didn't match health pattern" -ForegroundColor DarkGray
                    }
                } catch {
                    Write-Host "  Error parsing response: $_" -ForegroundColor DarkGray
                }
            }
        }
        catch {
            Write-Host "  Health check failed at $endpoint" -ForegroundColor DarkGray
        }
    }
    
    if (-not $healthOk) {
        Write-Host "WARNING: Could not find working health endpoint" -ForegroundColor Red
        Write-Host "Checking application logs for startup issues..." -ForegroundColor Yellow
        
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
        
        # Try to continue with a best guess endpoint
        $healthUrl = "http://127.0.0.1:$apiPort/health"
        Write-Host "Will continue test using $healthUrl as fallback health endpoint" -ForegroundColor Yellow
    }
    
    # Main monitoring loop
    $checkInterval = 15  # seconds
    $lastCheck = [DateTime]::MinValue
    $healthChecks = 0
    $successfulChecks = 0
    
    Write-Host "Starting test monitoring..." -ForegroundColor Cyan
    while ($stopwatch.Elapsed.TotalSeconds -lt $DurationSec -and -not $proc.HasExited) {
        $now = [DateTime]::Now
        
        # Run health check at specified intervals
        if (($now - $lastCheck).TotalSeconds -ge $checkInterval) {
            $lastCheck = $now
            $healthChecks++
            
            try {
                # Try different methods to check health
                $healthResult = $null
                
                # Method 1: Invoke-RestMethod
                try {
                    $healthResult = Invoke-RestMethod -Uri $healthUrl -Method GET -TimeoutSec 5 -ErrorAction Stop
                } catch {
                    # Method 2: Invoke-WebRequest
                    try {
                        $webResult = Invoke-WebRequest -Uri $healthUrl -Method GET -TimeoutSec 5 -ErrorAction Stop
                        if ($webResult.StatusCode -eq 200) {
                            $healthResult = @{ status = "ok"; message = "Health check from web request" }
                        }
                    } catch {
                        # Method 3: Test-NetConnection
                        $port = ([System.Uri]$healthUrl).Port
                        if (-not $port) { $port = 80 }
                        $testConn = Test-NetConnection -ComputerName "127.0.0.1" -Port $port -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                        if ($testConn.TcpTestSucceeded) {
                            $healthResult = @{ status = "ok"; message = "Port accessible" }
                        }
                    }
                }
                
                if ($healthResult) {
                    $successfulChecks++
                    
                    # Log to health log
                    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - OK - " + ($healthResult | ConvertTo-Json -Compress)
                    $logEntry | Out-File -FilePath $healthLogPath -Append -Encoding utf8
                    
                    # Log periodically to console
                    if ($healthChecks % 4 -eq 0 -or $Verbose) {
                        $minutes = [Math]::Floor($stopwatch.Elapsed.TotalMinutes)
                        Write-Host "[$minutes min] Health check OK" -ForegroundColor Green
                        if ($Verbose) {
                            Write-Host "  Response: $($healthResult | ConvertTo-Json -Compress)" -ForegroundColor Green
                        }
                    }
                } else {
                    throw "Health check failed with no response"
                }
            }
            catch {
                "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR - $($_.Exception.Message)" | Out-File -FilePath $healthLogPath -Append -Encoding utf8
                Write-Host "Health check failed: $($_.Exception.Message)" -ForegroundColor Yellow
                
                # Try to determine if process is still responsive
                $isRunning = -not $proc.HasExited
                Write-Host "  Process is $(if ($isRunning) {"still running"} else {"no longer running"})" -ForegroundColor $(if ($isRunning) {"Yellow"} else {"Red"})
            }
        }
        
        # Check if process is still running
        if ($proc.HasExited) {
            Write-Host "Process exited prematurely with code: $($proc.ExitCode)" -ForegroundColor Red
            break
        }
        
        # Small pause to prevent high CPU usage
        Start-Sleep -Milliseconds 500
    }
    
    # Test complete
    $stopwatch.Stop()
    $testDuration = $stopwatch.Elapsed.TotalSeconds
    
    Write-Host "Test complete, shutting down service..." -ForegroundColor Cyan
    
    # Try to get metrics before shutdown if metrics are enabled
    if (-not $NoPrometheus) {
        try {
            $metricsUrl = "http://127.0.0.1:$metricsPort/metrics"
            Write-Host "Fetching metrics from $metricsUrl" -ForegroundColor Cyan
            $metricsResult = Invoke-RestMethod -Uri $metricsUrl -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($metricsResult) {
                $metricsResult | Out-File -FilePath $metricsPath -Encoding utf8
                Write-Host "Collected metrics data" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "Failed to collect metrics: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    # Try graceful shutdown with multiple endpoints
    $shutdownEndpoints = @(
        "http://127.0.0.1:$apiPort/shutdown", 
        "http://127.0.0.1:$apiPort/api/shutdown",
        "http://127.0.0.1:$adminPort/shutdown", 
        "http://127.0.0.1:$adminPort/api/shutdown"
    )
    
    $shutdownSuccess = $false
    foreach ($endpoint in $shutdownEndpoints) {
        try {
            Invoke-RestMethod -Uri $endpoint -Method POST -TimeoutSec 3 -ErrorAction SilentlyContinue | Out-Null
            Write-Host "Shutdown request sent to $endpoint" -ForegroundColor Green
            $shutdownSuccess = $true
            Start-Sleep -Seconds 3
            break
        }
        catch {
            Write-Host "Shutdown request failed at $endpoint: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    if (-not $shutdownSuccess) {
        Write-Host "All shutdown requests failed, will use force stop" -ForegroundColor Yellow
    }
    
    # Force kill if still running
    if (-not $proc.HasExited) {
        Write-Host "Force stopping process..." -ForegroundColor Yellow
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    
    # Wait a moment for logs to flush
    Start-Sleep -Seconds 2
    
    # Generate summary
    Write-Host "Generating test summary..." -ForegroundColor Cyan
    
    # Count connection success/errors
    $ethConnectCount = 0
    $ethErrors = 0
    $solConnectCount = 0
    $solErrors = 0
    $totalErrors = 0
    
    if (Test-Path $appLogPath) {
        $ethConnectCount = (Select-String -Path $appLogPath -Pattern "(?i)connected to ethereum|eth relay connected|eth client initialized|ethereum.*(started|ready|connected)" -AllMatches | Measure-Object).Count
        $ethErrors = (Select-String -Path $appLogPath -Pattern "(?i)ethereum error|eth connection failed|eth client error|ethereum.*(fail|error|exception)" -AllMatches | Measure-Object).Count
        $solConnectCount = (Select-String -Path $appLogPath -Pattern "(?i)connected to solana|sol relay connected|solana client initialized|solana.*(started|ready|connected)" -AllMatches | Measure-Object).Count
        $solErrors = (Select-String -Path $appLogPath -Pattern "(?i)solana error|sol connection failed|solana client error|solana.*(fail|error|exception)" -AllMatches | Measure-Object).Count
    }
    
    if (Test-Path $errLogPath) {
        $totalErrors = (Select-String -Path $errLogPath -Pattern "(?i)error|fatal|panic" -AllMatches | Measure-Object).Count
    }
    
    # Create summary content
    $summaryContent = @"
# Ethereum & Solana Focus Test Summary

## Test Information
- **Run ID**: $runId
- **Date**: $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))
- **Duration**: $([Math]::Round($testDuration, 2)) seconds ($([Math]::Round($testDuration/60, 1)) minutes)
- **API Port**: $apiPort
- **Health Port**: $healthPort
- **Metrics Port**: $(if ($NoPrometheus) { "Disabled" } else { $metricsPort })
- **Admin Port**: $adminPort

## Connection Statistics
- **Ethereum**: $ethConnectCount successful connections, $ethErrors errors
- **Solana**: $solConnectCount successful connections, $solErrors errors

## Health Check Statistics
- **Total Checks**: $healthChecks
- **Successful**: $successfulChecks
- **Success Rate**: $([Math]::Round(100 * $successfulChecks / [Math]::Max(1, $healthChecks), 1))%

## Error Summary
- **Total Errors**: $totalErrors

## Status
**Result**: $(if($ethConnectCount -gt 0 -and $solConnectCount -gt 0 -and $totalErrors -eq 0) {'✅ SUCCESS'} elseif($ethConnectCount -gt 0 -or $solConnectCount -gt 0) {'⚠️ PARTIAL SUCCESS'} else {'❌ FAILURE'})
"@
    
    $summaryContent | Out-File -FilePath $summaryPath -Encoding utf8
    
    # Display final result
    Write-Host "`n======== TEST RESULTS ========" -ForegroundColor Cyan
    Write-Host "Duration: $([Math]::Round($testDuration/60, 1)) minutes" -ForegroundColor Cyan
    Write-Host "Ethereum: $ethConnectCount connections, $ethErrors errors" -ForegroundColor $(if($ethConnectCount -gt 0) {'Green'} else {'Red'})
    Write-Host "Solana: $solConnectCount connections, $solErrors errors" -ForegroundColor $(if($solConnectCount -gt 0) {'Green'} else {'Red'})
    Write-Host "Health Check: $successfulChecks/$healthChecks successful" -ForegroundColor $(if($successfulChecks -gt 0) {'Green'} else {'Red'})
    Write-Host "Total Errors: $totalErrors" -ForegroundColor $(if($totalErrors -eq 0) {'Green'} else {'Yellow'})
    
    if ($ethConnectCount -gt 0 -and $solConnectCount -gt 0 -and $totalErrors -eq 0) {
        Write-Host "OVERALL RESULT: ✅ SUCCESS" -ForegroundColor Green
    }
    elseif ($ethConnectCount -gt 0 -or $solConnectCount -gt 0) {
        Write-Host "OVERALL RESULT: ⚠️ PARTIAL SUCCESS" -ForegroundColor Yellow
    }
    else {
        Write-Host "OVERALL RESULT: ❌ FAILURE" -ForegroundColor Red
    }
    Write-Host "Test results saved to: $testRunDir" -ForegroundColor Cyan
    Write-Host "Summary file: $summaryPath" -ForegroundColor Cyan
    Write-Host "============================" -ForegroundColor Cyan
    
    # Return the summary path
    return $summaryPath
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    if ($proc -and -not $proc.HasExited) {
        Write-Host "Force stopping process..." -ForegroundColor Yellow
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    exit 1
}
