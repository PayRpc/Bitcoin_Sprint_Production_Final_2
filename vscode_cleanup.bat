@echo off
REM VS Code Crash Prevention Script
REM This script helps optimize the workspace to prevent VS Code crashes

echo Cleaning up VS Code workspace for better performance...
echo.

REM Clean Rust target directories (large debug files)
echo Cleaning Rust target directories...
if exist "secure\target" (
    echo Removing secure/target directory...
    rmdir /s /q "secure\target" 2>nul
)

REM Clean Node.js node_modules if not needed
if exist "web\node_modules" (
    echo Node modules found in web/ directory
    echo Consider excluding web/node_modules from VS Code if not actively developing frontend
)

REM Clean build artifacts
echo Cleaning build artifacts...
del /q "*.exe" 2>nul
del /q "*.log" 2>nul
del /q "err.txt" 2>nul
del /q "out.txt" 2>nul

REM Clean test artifacts
if exist "coverage" (
    echo Cleaning coverage directory...
    rmdir /s /q "coverage" 2>nul
)

REM Clean cache directories
if exist "cache" (
    echo Cleaning cache directory...
    rmdir /s /q "cache" 2>nul
)

echo.
echo VS Code optimization complete!
echo.
echo Recommendations:
echo 1. Restart VS Code after running this script
echo 2. If VS Code still crashes, try opening smaller subdirectories instead of the root
echo 3. Consider using VS Code's 'Files: Exclude' settings for large directories
echo 4. Monitor memory usage with Task Manager while using VS Code
echo.
pause
