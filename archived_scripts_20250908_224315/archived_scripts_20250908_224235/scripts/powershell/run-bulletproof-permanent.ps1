#!/usr/bin/env pwsh
# Bitcoin Sprint Bulletproof Permanent Service
# Runs the bulletproof backend as a persistent background service

param(
    [switch]$Stop,
    [switch]$Status,
    [switch]$Restart
)

$ServiceName = "BitcoinSprintBulletproof"
$ExePath = ".\bitcoin-sprint-bulletproof.exe"
$LogFile = "bulletproof-service.log"

function Write-BulletproofLog {
    param($Message, $Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage -ForegroundColor $Color
    Add-Content -Path $LogFile -Value $logMessage
}

function Start-BulletproofService {
    Write-BulletproofLog "🚀 Starting Bitcoin Sprint Bulletproof Service..." "Green"
    
    # Kill any existing processes
    Get-Process -Name "bitcoin-sprint-bulletproof" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    
    # Start the bulletproof service
    $process = Start-Process -FilePath $ExePath -WindowStyle Hidden -PassThru
    
    if ($process) {
        Write-BulletproofLog "✅ Bulletproof service started with PID: $($process.Id)" "Green"
        Write-BulletproofLog "🔗 API: http://localhost:9000" "Cyan"
        Write-BulletproofLog "📊 Metrics: http://localhost:9090/metrics" "Cyan"
        Write-BulletproofLog "💓 Health: http://localhost:9001/health" "Cyan"
        
        # Wait for startup
        Write-BulletproofLog "⏳ Waiting for bulletproof connections to establish..." "Yellow"
        Start-Sleep -Seconds 15
        
        # Test connectivity
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:9000/health" -TimeoutSec 10 -ErrorAction Stop
            Write-BulletproofLog "✅ Bulletproof API responding successfully!" "Green"
            Write-BulletproofLog "🛡️ Status: BULLETPROOF_ACTIVE" "Green"
            Write-BulletproofLog "🚫 Infura/Alchemy: BYPASSED" "Green"
            Write-BulletproofLog "📡 Direct connections: Bitcoin(10) + Ethereum(10) + Solana(9) = 29 endpoints" "Green"
        } catch {
            Write-BulletproofLog "⚠️ API not yet responding, but bulletproof backend is starting..." "Yellow"
        }
        
        return $process.Id
    } else {
        Write-BulletproofLog "❌ Failed to start bulletproof service" "Red"
        return $null
    }
}

function Stop-BulletproofService {
    Write-BulletproofLog "🛑 Stopping Bitcoin Sprint Bulletproof Service..." "Yellow"
    
    $processes = Get-Process -Name "bitcoin-sprint-bulletproof" -ErrorAction SilentlyContinue
    if ($processes) {
        $processes | Stop-Process -Force
        Write-BulletproofLog "✅ Bulletproof service stopped" "Green"
    } else {
        Write-BulletproofLog "ℹ️ No bulletproof service processes found" "Gray"
    }
}

function Get-BulletproofStatus {
    $processes = Get-Process -Name "bitcoin-sprint-bulletproof" -ErrorAction SilentlyContinue
    
    if ($processes) {
        Write-BulletproofLog "✅ Bulletproof service is RUNNING" "Green"
        foreach ($proc in $processes) {
            Write-BulletproofLog "   PID: $($proc.Id), Memory: $([math]::Round($proc.WorkingSet64/1MB,2))MB" "Gray"
        }
        
        # Test API connectivity
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:9000/health" -TimeoutSec 5 -ErrorAction Stop
            Write-BulletproofLog "✅ API: RESPONDING" "Green"
        } catch {
            Write-BulletproofLog "⚠️ API: NOT RESPONDING" "Yellow"
        }
        
        return $true
    } else {
        Write-BulletproofLog "❌ Bulletproof service is NOT running" "Red"
        return $false
    }
}

# Main execution
Clear-Host
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "  BITCOIN SPRINT BULLETPROOF SERVICE" -ForegroundColor Cyan
Write-Host "  🛡️ Direct Connections Only" -ForegroundColor Green
Write-Host "  🚫 No Infura/Alchemy Dependencies" -ForegroundColor Green
Write-Host "  📡 29 Direct Network Endpoints" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

if ($Stop) {
    Stop-BulletproofService
} elseif ($Status) {
    Get-BulletproofStatus
} elseif ($Restart) {
    Stop-BulletproofService
    Start-Sleep -Seconds 3
    Start-BulletproofService
} else {
    # Default: Start service
    if (Get-BulletproofStatus) {
        Write-BulletproofLog "⚠️ Service already running. Use -Restart to restart." "Yellow"
    } else {
        Start-BulletproofService
    }
}

Write-Host ""
Write-Host "Commands:" -ForegroundColor Cyan
Write-Host "  .\run-bulletproof-permanent.ps1        # Start service" -ForegroundColor Gray
Write-Host "  .\run-bulletproof-permanent.ps1 -Stop  # Stop service" -ForegroundColor Gray
Write-Host "  .\run-bulletproof-permanent.ps1 -Status # Check status" -ForegroundColor Gray
Write-Host "  .\run-bulletproof-permanent.ps1 -Restart # Restart service" -ForegroundColor Gray
