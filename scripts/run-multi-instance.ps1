param(
    [int]$InstanceCount = 3,
    [int]$DurationSec = 600,
    [switch]$UseRealEndpoints,
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

# Determine workspace paths
$scriptPath = $MyInvocation.MyCommand.Path
$scriptsDir = Split-Path -Parent $scriptPath
$ws = Split-Path -Parent $scriptsDir

# Create run timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$runId = [guid]::NewGuid().ToString("N").Substring(0, 8)

# Create output directory
$outputDir = Join-Path $ws "logs" "multi-smoke-$timestamp-$runId"
if (!(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

Write-Host "========= BITCOIN SPRINT MULTI-INSTANCE SMOKE TEST =========" -ForegroundColor Green
Write-Host "Run ID: $runId" -ForegroundColor Green
Write-Host "Instances: $InstanceCount" -ForegroundColor Green
Write-Host "Duration: $($DurationSec/60) minutes per instance" -ForegroundColor Green
Write-Host "Real Endpoints: $($UseRealEndpoints -eq $true ? 'Yes' : 'No')" -ForegroundColor Green
Write-Host "Output Directory: $outputDir" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green

# Create a summary list
$summaryList = @()

# Start each instance asynchronously
$jobs = @()

# Start with a port base that's unlikely to conflict
$portBase = Get-Random -Minimum 9500 -Maximum 19000
$portIncrement = 100 # Space instances far apart to avoid port conflicts

for ($i = 0; $i -lt $InstanceCount; $i++) {
    $instancePort = $portBase + ($i * $portIncrement)
    $instanceLogFile = Join-Path $outputDir "instance-${i}-output.log"
    
    Write-Host "Starting instance $($i+1)/$InstanceCount on port $instancePort..." -ForegroundColor Cyan
    
    # Build the script block for running an instance
    $scriptBlock = {
        param($ScriptPath, $Port, $Duration, $LogFile, $UseRealEndpoints, $Verbose)
        
        # Parameters for the smoke test script
        $params = @{
            DurationSec = $Duration
            PreferredPort = $Port
            LogLevel = "info"
        }
        
        if ($UseRealEndpoints) {
            $params.Add("UseRealEndpoints", $true)
        }
        
        if ($Verbose) {
            $params.Add("Verbose", $true)
        }
        
        # Run the script and capture the output
        & $ScriptPath @params *> $LogFile
        
        # Return the last line which should be the summary path
        $lastLine = Get-Content -Path $LogFile -Tail 1
        return $lastLine
    }
    
    # Start the job
    $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList @(
        (Join-Path $scriptsDir "run-ten-min.ps1"),
        $instancePort,
        $DurationSec,
        $instanceLogFile,
        $UseRealEndpoints,
        $Verbose
    )
    
    $jobs += @{
        JobObject = $job
        InstanceId = $i
        Port = $instancePort
        LogFile = $instanceLogFile
    }
    
    # Small delay between starting instances to prevent resource contention
    Start-Sleep -Seconds 3
}

# Monitor job progress
$completedCount = 0
$inProgressCount = $jobs.Count
$startTime = Get-Date

Write-Host "`nMonitoring $($jobs.Count) test instances..." -ForegroundColor Yellow

while ($inProgressCount -gt 0) {
    $currentTime = Get-Date
    $elapsedMinutes = [Math]::Round(($currentTime - $startTime).TotalMinutes, 1)
    $remainingMinutes = [Math]::Max(0, [Math]::Round(($DurationSec/60) - $elapsedMinutes, 1))
    
    # Update progress
    Write-Host "`r[$elapsedMinutes min elapsed, ~$remainingMinutes min remaining] $completedCount completed, $inProgressCount running..." -NoNewline -ForegroundColor Yellow
    
    # Check status of all jobs
    foreach ($jobInfo in $jobs) {
        if ($jobInfo.JobObject.State -eq "Completed" -and -not $jobInfo.Completed) {
            # Mark as processed
            $jobInfo.Completed = $true
            $completedCount++
            $inProgressCount--
            
            # Get the result
            $result = Receive-Job -Job $jobInfo.JobObject
            $summaryPath = $result
            
            # Add to summary list
            if ($summaryPath -and (Test-Path $summaryPath)) {
                $summaryList += @{
                    InstanceId = $jobInfo.InstanceId
                    Port = $jobInfo.Port
                    SummaryPath = $summaryPath
                }
                
                Write-Host "`nInstance $($jobInfo.InstanceId) completed. Summary: $summaryPath" -ForegroundColor Green
            } else {
                Write-Host "`nInstance $($jobInfo.InstanceId) completed but no summary path found." -ForegroundColor Yellow
            }
        }
        elseif ($jobInfo.JobObject.State -eq "Failed" -and -not $jobInfo.Completed) {
            # Mark as processed
            $jobInfo.Completed = $true
            $completedCount++
            $inProgressCount--
            
            # Log error
            Write-Host "`nInstance $($jobInfo.InstanceId) failed!" -ForegroundColor Red
            $error = Receive-Job -Job $jobInfo.JobObject -ErrorAction SilentlyContinue
            Write-Host $error -ForegroundColor Red
        }
    }
    
    # Exit if all jobs are complete
    if ($inProgressCount -eq 0) {
        break
    }
    
    # Sleep before checking again
    Start-Sleep -Seconds 5
}

Write-Host "`nAll test instances have completed!" -ForegroundColor Green

# Generate a combined summary
$combinedSummaryPath = Join-Path $outputDir "combined-summary.md"

$combinedSummaryContent = @"
# Bitcoin Sprint Multi-Instance Smoke Test Summary

## Test Information
- **Run ID**: $runId
- **Date**: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
- **Instance Count**: $InstanceCount
- **Duration**: $($DurationSec/60) minutes per instance
- **Real Endpoints**: $($UseRealEndpoints -eq $true ? 'Yes' : 'No')

## Instance Results

"@

$errorCount = 0
$successCount = 0

foreach ($summary in $summaryList) {
    # Read the summary file
    if (Test-Path $summary.SummaryPath) {
        $content = Get-Content -Path $summary.SummaryPath -Raw
        
        # Check for errors
        $hasErrors = $content -match "ISSUES DETECTED"
        if ($hasErrors) {
            $errorCount++
        } else {
            $successCount++
        }
        
        $status = if ($hasErrors) { "❌ ISSUES" } else { "✅ SUCCESS" }
        
        $combinedSummaryContent += "### Instance $($summary.InstanceId) (Port $($summary.Port)) - $status`n`n"
        $combinedSummaryContent += "$content`n`n"
        $combinedSummaryContent += "---`n`n"
    } else {
        $combinedSummaryContent += "### Instance $($summary.InstanceId) (Port $($summary.Port)) - ❓ UNKNOWN`n`n"
        $combinedSummaryContent += "Summary file not found: $($summary.SummaryPath)`n`n"
        $combinedSummaryContent += "---`n`n"
        $errorCount++
    }
}

$combinedSummaryContent += @"
## Overall Summary
- **Total Instances**: $InstanceCount
- **Successful**: $successCount
- **With Issues**: $errorCount
- **Success Rate**: $([Math]::Round(100 * $successCount / [Math]::Max(1, $InstanceCount), 1))%

## Overall Status
**Status**: $(if($errorCount -eq 0) {'✅ ALL TESTS PASSED'} else {'⚠️ SOME TESTS FAILED'})
"@

$combinedSummaryContent | Out-File -FilePath $combinedSummaryPath -Encoding utf8

# Clean up jobs
$jobs | ForEach-Object { Remove-Job -Job $_.JobObject -Force }

# Final output
Write-Host "`n========= TEST COMPLETE =========" -ForegroundColor Green
Write-Host "Successful instances: $successCount" -ForegroundColor $(if($successCount -eq $InstanceCount) {'Green'} else {'Yellow'})
Write-Host "Failed instances: $errorCount" -ForegroundColor $(if($errorCount -eq 0) {'Green'} else {'Red'})
Write-Host "Combined summary: $combinedSummaryPath" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Green

# Return the combined summary path
return $combinedSummaryPath
