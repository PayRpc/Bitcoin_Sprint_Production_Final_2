param(
    [switch]$Bitcoin,      # Run full test with Bitcoin
    [switch]$EthSolOnly,   # Test only ETH and SOL
    [switch]$Short,        # 2 minutes
    [switch]$Medium,       # 10 minutes (default)
    [switch]$Long,         # 30 minutes
    [switch]$Verbose,      # Show more detailed output
    [switch]$NoPrometheus, # Disable Prometheus to avoid port conflicts
    [switch]$Force         # Force kill existing processes if needed
)

# Determine paths
$scriptPath = $MyInvocation.MyCommand.Path
$scriptsDir = Split-Path -Parent $scriptPath
$runScript = Join-Path $scriptsDir "run-ten-min-fixed.ps1"

# Set default duration
$duration = 600  # Default 10 minutes
if ($Short) { $duration = 120 }  # 2 minutes
if ($Long) { $duration = 1800 }  # 30 minutes

# Set mode
$testMode = if ($EthSolOnly) { "ETH & SOL Only" } else { "Full System" }

# Clear host and show welcome banner
Clear-Host
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  BITCOIN SPRINT SMOKE TEST LAUNCHER" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Test Mode: $testMode" -ForegroundColor Cyan
Write-Host "Duration: $($duration/60) minutes" -ForegroundColor Cyan
Write-Host "Prometheus: $(if ($NoPrometheus) { "DISABLED" } else { "ENABLED" })" -ForegroundColor Cyan
Write-Host "Testing will start in 3 seconds..." -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

Start-Sleep -Seconds 3

# Build parameter string
$params = @(
    "-DurationSec $duration"
)
if ($EthSolOnly) { $params += "-EthSolOnly" }
if ($Verbose) { $params += "-Verbose" }
if ($NoPrometheus) { $params += "-NoPrometheus" }
if ($Force) { $params += "-Force" }

# Run the script with parameters
$command = "& '$runScript' $($params -join ' ')"
Write-Host "Executing: $command" -ForegroundColor DarkGray
Invoke-Expression $command
