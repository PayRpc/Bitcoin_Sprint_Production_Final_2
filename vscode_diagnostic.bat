@echo off
REM VS Code Performance Diagnostic Script

echo VS Code Performance Diagnostic
echo ==============================
echo.

echo Checking workspace size...
powershell -Command "Get-ChildItem -Path '.' -Recurse -File -ErrorAction SilentlyContinue | Measure-Object | Select-Object Count" 2>nul
echo.

echo Checking for large files (>10MB)...
powershell -Command "Get-ChildItem -Path '.' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 10MB } | Select-Object FullName, @{Name='SizeMB';Expression={[math]::Round($_.Length / 1MB, 2)}} | Format-Table -AutoSize" 2>nul
echo.

echo Checking system memory...
powershell -Command "Get-WmiObject -Class Win32_OperatingSystem | Select-Object TotalVisibleMemorySize, FreePhysicalMemory" 2>nul
echo.

echo Recommendations:
echo ================
echo 1. Close VS Code and run vscode_cleanup.bat
echo 2. Restart VS Code
echo 3. If still crashing, try opening smaller subdirectories
echo 4. Consider increasing VS Code memory limits in settings
echo 5. Monitor Task Manager for memory usage
echo 6. Disable unnecessary VS Code extensions
echo.

pause
