param(
    [int]$DurationSec = 300,
    [string]$LogLevel = "debug",
    [switch]$Verbose
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

# Get available ports
$apiPort = Get-FreeTcpPort
$healthPort = $apiPort + 1
$metricsPort = $apiPort + 2
$adminPort = $apiPort + 10

# Make sure all ports are available
if ((Is-Port-In-Use -Port $apiPort) -or (Is-Port-In-Use -Port $healthPort) -or 
    (Is-Port-In-Use -Port $metricsPort) -or (Is-Port-In-Use -Port $adminPort)) {
    Write-Host "Port conflicts detected. Retrying with different ports..." -ForegroundColor Yellow
    $apiPort = Get-FreeTcpPort
    $healthPort = Get-FreeTcpPort
    $metricsPort = Get-FreeTcpPort
    $adminPort = Get-FreeTcpPort
}

# Build environment variables
$envVars = @{
    # Focus only on ETH and Solana
    "SKIP_BITCOIN" = "true"
    "ETHEREUM_FOCUS" = "true"
    "SOLANA_FOCUS" = "true"
    "DISABLE_BTC_P2P" = "true"
    
    # Disable database to avoid SQLite issues
    "DISABLE_DB" = "true"
    "SKIP_DB_INIT" = "true"
    "DB_MOCK" = "true"
    
    # Core configuration
    "TIER" = "enterprise"
    "LOG_LEVEL" = $LogLevel
    "RUN_ID" = $runId
    "RUN_MODE" = "test"
    "TEST_RUN" = "true"
    
    # API Configuration
    "API_HOST" = "127.0.0.1"
    "API_PORT" = $apiPort
    "API_BIND" = "127.0.0.1:$apiPort"
    "HTTP_PORT" = $apiPort
    "BITCOIN_SPRINT_HTTP_PORT" = $apiPort
    "BITCOIN_SPRINT_API_PORT" = $apiPort
    
    # Admin & monitoring ports
    "ADMIN_PORT" = $adminPort
    "HEALTH_PORT" = $healthPort
    "PROMETHEUS_PORT" = $metricsPort
    
    # Ethereum configuration - reliable public endpoints
    "ETH_HTTP_URL" = "https://eth.rpc.nethermind.io"
    "ETH_WS_URL" = "wss://ethereum.publicnode.com"
    "ETH_RPC_ENDPOINTS" = '["https://eth.rpc.nethermind.io","https://rpc.eth.gateway.fm","https://rpc.flashbots.net"]'
    "ETH_WS_ENDPOINTS" = '["wss://ethereum.publicnode.com","wss://eth.drpc.org"]'
    "ETH_TIMEOUT" = "15s"
    "ETH_MAX_CONNECTIONS" = "3"
    
    # Solana configuration
    "SOL_RPC_URL" = "https://api.mainnet-beta.solana.com"
    "SOLANA_RPC_ENDPOINTS" = '["https://api.mainnet-beta.solana.com","https://rpc.ankr.com/solana"]'
    "SOLANA_WS_ENDPOINTS" = '["wss://api.mainnet-beta.solana.com","wss://rpc.ankr.com/solana/ws"]'
    "SOLANA_TIMEOUT" = "15s"
    "SOLANA_MAX_CONNECTIONS" = "3"
    
    # Optimization settings
    "RATE_LIMIT_FACTOR" = "0.25"
    "MAX_CONCURRENT_REQUESTS" = "50"
    "CONNECTION_TIMEOUT_SEC" = "15"
    
    # Extra test flags
    "BITCOIN_SPRINT_PROFILE" = "test"
    "DISABLE_CIRCUIT_BREAKER" = "false"
    "READY_STATUS" = "ok"
    "STATUS_FIELD" = "status"
}

# Write config to file for reference
$configFileContent = @()
foreach ($key in $envVars.Keys) {
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
    metrics_port = $metricsPort
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
Write-Host "Metrics Port: $metricsPort" -ForegroundColor Green
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
    
    # Give the application some time to start
    Write-Host "Waiting for application to initialize (10 seconds)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    
    # Start the test timer
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    # Define all possible health endpoints
    $healthEndpoints = @(
        "http://127.0.0.1:$apiPort/health",
        "http://127.0.0.1:$healthPort/health",
        "http://127.0.0.1:$adminPort/health",
        "http://127.0.0.1:$apiPort/status",
        "http://127.0.0.1:$healthPort/status",
        "http://127.0.0.1:$adminPort/status"
    )
    
    # Try to connect to the health endpoint
    $healthOk = $false
    $healthUrl = ""
    
    Write-Host "Checking for service health..." -ForegroundColor Yellow
    foreach ($endpoint in $healthEndpoints) {
        try {
            $result = Invoke-RestMethod -Uri $endpoint -Method GET -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($result) {
                $healthOk = $true
                $healthUrl = $endpoint
                Write-Host "Health check successful at $endpoint" -ForegroundColor Green
                Write-Host "Response: $($result | ConvertTo-Json -Compress)" -ForegroundColor Green
                break
            }
        }
        catch {
            Write-Host "Health check failed at $endpoint" -ForegroundColor Yellow
        }
    }
    
    if (-not $healthOk) {
        Write-Host "WARNING: Could not find working health endpoint" -ForegroundColor Red
        $healthUrl = "http://127.0.0.1:$apiPort/health"
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
                $response = Invoke-RestMethod -Uri $healthUrl -Method GET -TimeoutSec 5 -ErrorAction SilentlyContinue
                $successfulChecks++
                
                # Log to health log
                "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - OK - $($response | ConvertTo-Json -Compress)" | Out-File -FilePath $healthLogPath -Append -Encoding utf8
                
                # Log periodically to console
                if ($healthChecks % 4 -eq 0) {
                    $minutes = [Math]::Floor($stopwatch.Elapsed.TotalMinutes)
                    Write-Host "[$minutes min] Health check OK - $($response | ConvertTo-Json -Compress)" -ForegroundColor Green
                }
            }
            catch {
                "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR - $($_.Exception.Message)" | Out-File -FilePath $healthLogPath -Append -Encoding utf8
                Write-Host "Health check failed: $($_.Exception.Message)" -ForegroundColor Yellow
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
    
    # Try to get metrics before shutdown
    try {
        $metricsResult = Invoke-RestMethod -Uri "http://127.0.0.1:$metricsPort/metrics" -TimeoutSec 5 -ErrorAction SilentlyContinue
        if ($metricsResult) {
            $metricsResult | Out-File -FilePath $metricsPath -Encoding utf8
            Write-Host "Collected metrics data" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Failed to collect metrics: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Try graceful shutdown
    try {
        Invoke-RestMethod -Uri "http://127.0.0.1:$apiPort/shutdown" -Method POST -TimeoutSec 3 -ErrorAction SilentlyContinue | Out-Null
        Write-Host "Shutdown request sent" -ForegroundColor Green
        Start-Sleep -Seconds 3
    }
    catch {
        Write-Host "Shutdown request failed: $($_.Exception.Message)" -ForegroundColor Yellow
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
        $ethConnectCount = (Select-String -Path $appLogPath -Pattern "(?i)connected to ethereum|eth relay connected|eth client initialized" -AllMatches | Measure-Object).Count
        $ethErrors = (Select-String -Path $appLogPath -Pattern "(?i)ethereum error|eth connection failed|eth client error" -AllMatches | Measure-Object).Count
        $solConnectCount = (Select-String -Path $appLogPath -Pattern "(?i)connected to solana|sol relay connected|solana client initialized" -AllMatches | Measure-Object).Count
        $solErrors = (Select-String -Path $appLogPath -Pattern "(?i)solana error|sol connection failed|solana client error" -AllMatches | Measure-Object).Count
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
- **Metrics Port**: $metricsPort

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
