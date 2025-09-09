# Bitcoin Sprint Smoke Test Launcher
# This script provides an easy way to launch smoke tests with different configurations

# Helper function to display menu
function Show-Menu {
    param(
        [string]$Title = 'Bitcoin Sprint Smoke Test Menu'
    )
    Clear-Host
    Write-Host "================ $Title ================"
    Write-Host ""
    Write-Host "1: Run Single Instance (10 minutes)"
    Write-Host "2: Run Single Instance with Real Endpoints (10 minutes)"
    Write-Host "3: Run Multiple Instances (3 instances, 10 minutes each)"
    Write-Host "4: Run Multiple Instances with Real Endpoints (3 instances, 10 minutes each)"
    Write-Host "5: Run Extended Test (30 minutes)"
    Write-Host "6: Run Full Stress Test (5 instances, 30 minutes with real endpoints)"
    Write-Host ""
    Write-Host "C: Clean up old test logs"
    Write-Host "Q: Quit"
    Write-Host ""
}

# Get the scripts directory
$scriptPath = $MyInvocation.MyCommand.Path
$scriptsDir = Split-Path -Parent $scriptPath
$ws = Split-Path -Parent $scriptsDir

function Run-SingleInstance {
    param (
        [int]$Duration = 600,
        [switch]$UseRealEndpoints
    )
    
    $params = @{
        DurationSec = $Duration
        LogLevel = "info"
    }
    
    if ($UseRealEndpoints) {
        $params.Add("UseRealEndpoints", $true)
    }
    
    & "$scriptsDir\run-ten-min.ps1" @params
}

function Run-MultipleInstances {
    param (
        [int]$Count = 3,
        [int]$Duration = 600,
        [switch]$UseRealEndpoints
    )
    
    $params = @{
        InstanceCount = $Count
        DurationSec = $Duration
    }
    
    if ($UseRealEndpoints) {
        $params.Add("UseRealEndpoints", $true)
    }
    
    & "$scriptsDir\run-multi-instance.ps1" @params
}

function Clean-OldLogs {
    $logsDir = Join-Path $ws "logs"
    
    if (!(Test-Path $logsDir)) {
        Write-Host "No logs directory found." -ForegroundColor Yellow
        return
    }
    
    # Get log directories older than 7 days
    $oldLogs = Get-ChildItem -Path $logsDir -Directory | Where-Object {
        $_.LastWriteTime -lt (Get-Date).AddDays(-7)
    }
    
    if ($oldLogs.Count -eq 0) {
        Write-Host "No log directories older than 7 days found." -ForegroundColor Green
        return
    }
    
    Write-Host "Found $($oldLogs.Count) log directories older than 7 days:" -ForegroundColor Yellow
    $oldLogs | ForEach-Object { Write-Host "- $($_.Name)" -ForegroundColor Gray }
    
    $confirmation = Read-Host "Do you want to delete these directories? (y/n)"
    if ($confirmation -eq 'y') {
        $oldLogs | ForEach-Object {
            Remove-Item -Path $_.FullName -Recurse -Force
            Write-Host "Deleted $($_.Name)" -ForegroundColor Green
        }
        Write-Host "Clean-up complete." -ForegroundColor Green
    }
    else {
        Write-Host "Clean-up cancelled." -ForegroundColor Yellow
    }
}

# Main loop
do {
    Show-Menu
    $selection = Read-Host "Please make a selection"
    
    switch ($selection) {
        '1' {
            Write-Host "Running single instance smoke test (10 minutes)..." -ForegroundColor Cyan
            Run-SingleInstance -Duration 600
            Write-Host "Press any key to continue..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        '2' {
            Write-Host "Running single instance smoke test with real endpoints (10 minutes)..." -ForegroundColor Cyan
            Run-SingleInstance -Duration 600 -UseRealEndpoints
            Write-Host "Press any key to continue..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        '3' {
            Write-Host "Running 3 instances of smoke test (10 minutes each)..." -ForegroundColor Cyan
            Run-MultipleInstances -Count 3 -Duration 600
            Write-Host "Press any key to continue..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        '4' {
            Write-Host "Running 3 instances of smoke test with real endpoints (10 minutes each)..." -ForegroundColor Cyan
            Run-MultipleInstances -Count 3 -Duration 600 -UseRealEndpoints
            Write-Host "Press any key to continue..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        '5' {
            Write-Host "Running extended smoke test (30 minutes)..." -ForegroundColor Cyan
            Run-SingleInstance -Duration 1800 -UseRealEndpoints
            Write-Host "Press any key to continue..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        '6' {
            Write-Host "Running full stress test (5 instances, 30 minutes with real endpoints)..." -ForegroundColor Cyan
            Run-MultipleInstances -Count 5 -Duration 1800 -UseRealEndpoints
            Write-Host "Press any key to continue..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        'C' {
            Clean-OldLogs
            Write-Host "Press any key to continue..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        'Q' {
            return
        }
    }
} until ($selection -eq 'q')
