param(
    [switch]$Short,
    [switch]$Medium,
    [switch]$Long,
    [switch]$Verbose
)

# Determine paths
$scriptPath = $MyInvocation.MyCommand.Path
$scriptsDir = Split-Path -Parent $scriptPath
$ethSolTestPath = Join-Path $scriptsDir "eth-sol-test.ps1"

# Set default duration
$duration = 300  # Default 5 minutes
if ($Short) { $duration = 120 } # 2 minutes
if ($Medium) { $duration = 600 } # 10 minutes
if ($Long) { $duration = 1800 } # 30 minutes

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  ETHEREUM AND SOLANA FOCUSED TEST" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Duration: $($duration/60) minutes" -ForegroundColor Cyan
Write-Host "Testing will start in 3 seconds..." -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

Start-Sleep -Seconds 3

# Run the test with appropriate parameters
$verboseParam = if ($Verbose) { "-Verbose" } else { "" }
$command = "& '$ethSolTestPath' -DurationSec $duration $verboseParam"

# Execute the command
Invoke-Expression $command
