#!/bin/pwsh
# Bitcoin Connection Test Script
# This script launches Bitcoin Sprint with only Bitcoin connections enabled
# and verifies that connections are established successfully

param (
    [int]$Duration = 300,  # Default: 5 minutes
    [switch]$Debug = $false,
    [int]$PortBase = 8400,
    [int]$InstanceCount = 1,
    [int]$PortSpacing = 10
)

function Write-ColorText {
    param (
        [string]$Text,
        [string]$Color = "White"
    )
    Write-Host $Text -ForegroundColor $Color
}

function Format-ElapsedTime {
    param (
        [System.TimeSpan]$TimeSpan
    )
    return "{0:D2}:{1:D2}:{2:D2}" -f $TimeSpan.Hours, $TimeSpan.Minutes, $TimeSpan.Seconds
}

# Display test parameters
Write-ColorText "Bitcoin Connection Test" "Cyan"
Write-ColorText "======================" "Cyan"
Write-ColorText "Duration: $Duration seconds" "Yellow"
Write-ColorText "Instances: $InstanceCount" "Yellow"
Write-ColorText "Port Base: $PortBase" "Yellow"
Write-ColorText "Port Spacing: $PortSpacing" "Yellow"
Write-ColorText "Debug Mode: $Debug" "Yellow"
Write-ColorText "======================" "Cyan"

# Initialize arrays for process tracking
$processes = @()
$startTimes = @()
$apiPorts = @()
$healthEndpoints = @()

# Start instances
for ($i = 0; $i -lt $InstanceCount; $i++) {
    $instanceId = $i + 1
    $apiPort = $PortBase + ($i * $PortSpacing)
    $healthEndpoint = "http://localhost:$apiPort/api/v1/health"
    
    $apiPorts += $apiPort
    $healthEndpoints += $healthEndpoint
    
    # Build environment variables
    $env:API_PORT = $apiPort
    $env:DISABLE_ETH = "true"
    $env:DISABLE_SOLANA = "true"
    $env:LOG_LEVEL = if ($Debug) { "debug" } else { "info" }
    
    # Start the process
    Write-ColorText "Starting instance $instanceId (API Port: $apiPort)..." "Cyan"
    $process = Start-Process -FilePath ".\bitcoin-sprint.exe" -ArgumentList "--api-port=$apiPort", "--enable-bitcoin" -PassThru -WindowStyle Minimized
    $processes += $process
    $startTimes += (Get-Date)
    
    Write-ColorText "Instance $instanceId started with PID $($process.Id)" "Green"
    Start-Sleep -Seconds 2
}

# Monitor health endpoints
$startTime = Get-Date
$endTime = $startTime.AddSeconds($Duration)
$healthCheckInterval = 10 # seconds
$nextHealthCheck = $startTime

Write-ColorText "Test running until $endTime (Ctrl+C to stop early)" "Cyan"
Write-ColorText "Waiting for services to initialize..." "Yellow"
Start-Sleep -Seconds 15 # Initial wait for services to start

while ((Get-Date) -lt $endTime) {
    $currentTime = Get-Date
    $elapsed = $currentTime - $startTime
    $remaining = $endTime - $currentTime
    
    if ($currentTime -ge $nextHealthCheck) {
        $nextHealthCheck = $currentTime.AddSeconds($healthCheckInterval)
        
        Write-ColorText "`n[$(Format-ElapsedTime -TimeSpan $elapsed)] Checking service health..." "Yellow"
        
        for ($i = 0; $i -lt $InstanceCount; $i++) {
            $instanceId = $i + 1
            $healthEndpoint = $healthEndpoints[$i]
            $process = $processes[$i]
            
            # Skip if process has already exited
            if ($process.HasExited) {
                Write-ColorText "Instance $instanceId (PID $($process.Id)) has exited with code $($process.ExitCode)" "Red"
                continue
            }
            
            try {
                # Try to get health status with 5 second timeout
                $healthResponse = Invoke-WebRequest -Uri $healthEndpoint -TimeoutSec 5 -UseBasicParsing
                $healthData = $healthResponse.Content | ConvertFrom-Json
                
                # Extract connection status
                $bitcoinStatus = if ($healthData.connections.bitcoin) { "✅" } else { "❌" }
                
                # Display status
                $statusColor = if ($bitcoinStatus -eq "✅") { "Green" } else { "Yellow" }
                Write-ColorText "Instance $instanceId - Bitcoin: $bitcoinStatus" $statusColor
                
                # Show more details in debug mode
                if ($Debug) {
                    Write-Host ($healthData | ConvertTo-Json -Depth 1)
                }
            }
            catch {
                Write-ColorText "Instance $instanceId - Health check failed: $_" "Red"
            }
        }
        
        # Show time remaining
        Write-ColorText "[$(Format-ElapsedTime -TimeSpan $elapsed)] Test running - $(Format-ElapsedTime -TimeSpan $remaining) remaining" "Cyan"
    }
    
    # Short sleep between checks to reduce CPU usage
    Start-Sleep -Seconds 1
}

# Test complete, stop all processes
Write-ColorText "`nTest complete after $(Format-ElapsedTime -TimeSpan $elapsed)" "Green"
Write-ColorText "Stopping all instances..." "Yellow"

foreach ($process in $processes) {
    if (!$process.HasExited) {
        $process.CloseMainWindow() | Out-Null
        Start-Sleep -Seconds 1
        
        if (!$process.HasExited) {
            Write-ColorText "Forcing process $($process.Id) to stop..." "Yellow"
            Stop-Process -Id $process.Id -Force
        }
    }
}

# Final status report
Write-ColorText "`n===== Bitcoin Connection Test Results =====" "Cyan"

for ($i = 0; $i -lt $InstanceCount; $i++) {
    $instanceId = $i + 1
    $process = $processes[$i]
    $runTime = (Get-Date) - $startTimes[$i]
    
    Write-ColorText "Instance $instanceId (PID $($process.Id)):" "Yellow"
    Write-ColorText "  Runtime: $(Format-ElapsedTime -TimeSpan $runTime)" "White"
    Write-ColorText "  Exit Code: $($process.ExitCode)" "White"
}

Write-ColorText "============= Test Complete =============" "Green"
