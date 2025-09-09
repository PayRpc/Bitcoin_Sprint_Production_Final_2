# Bitcoin Sprint Secure Service Management Script
# Handles building, installing, starting, stopping the secure service

param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("build", "install", "uninstall", "start", "stop", "status", "run-local", "test-api")]
    [string]$Action,
    
    [Parameter(Mandatory=$false)]
    [switch]$Api,
    
    [Parameter(Mandatory=$false)]
    [string]$Token = "devtoken"
)

$ErrorActionPreference = "Stop"
$ServiceName = "SecureBufferService"
$CargoDir = "c:\Projects 2\Bitcoin_Sprint_Production_2\secure\rust"
$BinaryPath = "c:\Projects 2\Bitcoin_Sprint_Production_2\target\release\securebuffer-service.exe"

function Require-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $currentUser
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Host "This operation requires administrator privileges." -ForegroundColor Red
        Write-Host "Please run this script as administrator." -ForegroundColor Red
        exit 1
    }
}

function Build-Service {
    Write-Host "Building secure service..." -ForegroundColor Cyan
    
    $features = "win-service"
    if ($Api) { $features += ",api" }
    
    Set-Location $CargoDir
    $buildCmd = "cargo build --release --features `"$features`""
    Write-Host "Executing: $buildCmd" -ForegroundColor Gray
    
    Invoke-Expression $buildCmd
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    
    Write-Host "Build successful" -ForegroundColor Green
}

function Install-Service {
    Require-Admin
    Write-Host "Installing $ServiceName..." -ForegroundColor Cyan
    
    if (-not (Test-Path $BinaryPath)) {
        Write-Host "Binary not found at $BinaryPath" -ForegroundColor Red
        Write-Host "Please build the service first with: $PSCommandPath -Action build" -ForegroundColor Red
        exit 1
    }
    
    $exists = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($exists) {
        Write-Host "Service already exists. Removing..." -ForegroundColor Yellow
        sc.exe delete $ServiceName
        Start-Sleep -Seconds 2
    }
    
    # sc.exe expects space after binPath= and quoted path if it contains spaces
    $binPathArg = "binPath= `"$BinaryPath`""
    $result = sc.exe create $ServiceName $binPathArg DisplayName= "Bitcoin Sprint Secure Service" start= auto
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Service installation failed: $result" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    
    # Add environment variables if API is enabled
    if ($Api) {
        Write-Host "Setting up SECUREBUFFER_TOKEN environment variable for service..." -ForegroundColor Cyan
        $envCmd = "sc.exe config $ServiceName env=SECUREBUFFER_TOKEN=$Token"
        Invoke-Expression $envCmd
    }
    
    Write-Host "Service installed successfully" -ForegroundColor Green
    Write-Host "Run '$PSCommandPath -Action start' to start the service" -ForegroundColor Green
}

function Uninstall-Service {
    Require-Admin
    Write-Host "Uninstalling $ServiceName..." -ForegroundColor Cyan
    
    $exists = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $exists) {
        Write-Host "Service not installed" -ForegroundColor Yellow
        return
    }
    
    # Stop if running
    $status = (Get-Service -Name $ServiceName).Status
    if ($status -eq "Running") {
        sc.exe stop $ServiceName
        Write-Host "Waiting for service to stop..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
    
    # Delete service
    sc.exe delete $ServiceName
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Service uninstallation failed" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    
    Write-Host "Service uninstalled successfully" -ForegroundColor Green
}

function Start-SecureService {
    Require-Admin
    Write-Host "Starting $ServiceName..." -ForegroundColor Cyan
    
    $exists = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $exists) {
        Write-Host "Service not installed. Please install first." -ForegroundColor Red
        exit 1
    }
    
    sc.exe start $ServiceName
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to start service" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    
    Write-Host "Service started successfully" -ForegroundColor Green
}

function Stop-SecureService {
    Require-Admin
    Write-Host "Stopping $ServiceName..." -ForegroundColor Cyan
    
    $exists = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $exists) {
        Write-Host "Service not installed" -ForegroundColor Yellow
        return
    }
    
    sc.exe stop $ServiceName
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to stop service" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    
    Write-Host "Service stopped successfully" -ForegroundColor Green
}

function Get-ServiceStatus {
    Write-Host "Checking status of $ServiceName..." -ForegroundColor Cyan
    
    $exists = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $exists) {
        Write-Host "Service not installed" -ForegroundColor Yellow
        return
    }
    
    $service = Get-Service -Name $ServiceName
    $status = $service.Status
    
    Write-Host "Service status: $status" -ForegroundColor Green
    
    # If running and API enabled, check connectivity
    if ($status -eq "Running" -and $Api) {
        Test-ApiConnectivity
    }
}

function Test-ApiConnectivity {
    Write-Host "Testing API connectivity..." -ForegroundColor Cyan
    try {
        $headers = @{ "X-API-Key" = $Token }
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:8081/status" -Headers $headers -UseBasicParsing
        Write-Host "API Response ($($response.StatusCode)):" -ForegroundColor Green
        Write-Host $response.Content -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to connect to API: $_" -ForegroundColor Red
    }
}

function Run-Local {
    Write-Host "Running service in console mode with token '$Token'..." -ForegroundColor Cyan
    
    if (-not (Test-Path $BinaryPath)) {
        Write-Host "Binary not found. Building first..." -ForegroundColor Yellow
        Build-Service
    }
    
    $features = "win-service"
    if ($Api) { $features += ",api" }
    
    Set-Location $CargoDir
    $env:SECUREBUFFER_TOKEN = $Token
    
    Write-Host "Starting with features: $features" -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
    
    # Cargo run in a separate process to allow the PS script to continue
    $runCmd = "cargo run --release --features `"$features`""
    Write-Host "Executing: $runCmd" -ForegroundColor Gray
    Invoke-Expression $runCmd
}

# Execute the requested action
switch ($Action) {
    "build"     { Build-Service }
    "install"   { Install-Service }
    "uninstall" { Uninstall-Service }
    "start"     { Start-SecureService }
    "stop"      { Stop-SecureService }
    "status"    { Get-ServiceStatus }
    "run-local" { Run-Local }
    "test-api"  { Test-ApiConnectivity }
}

# Output usage instructions if completed successfully
if ($LASTEXITCODE -eq 0) {
    Write-Host "`nUsage Examples:" -ForegroundColor Cyan
    Write-Host "  Build service:         .\manage-secure-service.ps1 -Action build -Api" -ForegroundColor DarkGray
    Write-Host "  Install as service:    .\manage-secure-service.ps1 -Action install -Api -Token 'your-secure-token'" -ForegroundColor DarkGray
    Write-Host "  Start service:         .\manage-secure-service.ps1 -Action start" -ForegroundColor DarkGray
    Write-Host "  Check status:          .\manage-secure-service.ps1 -Action status -Api -Token 'your-secure-token'" -ForegroundColor DarkGray
    Write-Host "  Test API:              .\manage-secure-service.ps1 -Action test-api -Token 'your-secure-token'" -ForegroundColor DarkGray
    Write-Host "  Run in console:        .\manage-secure-service.ps1 -Action run-local -Api -Token 'your-secure-token'" -ForegroundColor DarkGray
    Write-Host "  Stop service:          .\manage-secure-service.ps1 -Action stop" -ForegroundColor DarkGray
    Write-Host "  Uninstall service:     .\manage-secure-service.ps1 -Action uninstall" -ForegroundColor DarkGray
}
