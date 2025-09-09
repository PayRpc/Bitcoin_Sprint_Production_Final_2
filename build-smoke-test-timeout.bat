@echo off
setlocal

echo Setting up MSVC environment...
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x64

echo Environment variables:
echo CC=%CC%
echo CXX=%CXX%
echo CGO_ENABLED=%CGO_ENABLED%
echo PATH segment: %PATH:~0,100%...

echo Building Go smoke test...
rem Use canonical cl wrapper in repository scripts folder. This makes the smoke test portable.
set SCRIPTS_DIR=%~dp0scripts
rem Compute short (8.3) path for scripts dir to avoid spaces in the path when invoked by cgo
for %%I in ("%SCRIPTS_DIR%") do set SCRIPTS_SHORT=%%~sI
set LOCAL_TMP=%SCRIPTS_SHORT%\\tmp_wrapper
if not exist "%LOCAL_TMP%" mkdir "%LOCAL_TMP%"
copy /Y "%SCRIPTS_SHORT%\\cl_wrapper_fixed.bat" "%LOCAL_TMP%\\cl_wrapper.bat" >nul 2>&1
rem Ensure the local tmp wrapper folder is on PATH and use the bare filename so Windows finds it via PATH
set "PATH=%LOCAL_TMP%;%PATH%"
set "CC=cl_wrapper.bat"
set "CXX=cl_wrapper.bat"
set CGO_ENABLED=1

REM Build with a simple timeout
set TIMEOUT=60
timeout /t 1 /nobreak >nul
echo Running build with %TIMEOUT% second timeout...

REM Run go build with a timeout (Windows-native redirection)
start /b cmd /c "go build -v ./cmd/smoke > build-output.log 2>&1 & type build-output.log"
set start_time=%time%
set wait_seconds=0

:wait_loop
timeout /t 2 /nobreak >nul
set /a wait_seconds+=2
if %wait_seconds% gtr %TIMEOUT% (
    echo Build timed out after %TIMEOUT% seconds.
    taskkill /f /im go.exe >nul 2>&1
    taskkill /f /im gcc.exe >nul 2>&1
    taskkill /f /im powershell.exe >nul 2>&1
    goto build_failed
)

REM Check if build succeeded or failed
if exist smoke.exe (
    echo Build completed successfully.
    goto build_success
)

REM Check if output file has errors
findstr /C:"error" build-output.log >nul 2>&1
if %errorlevel% equ 0 (
    echo Build failed with errors.
    type build-output.log
    goto build_failure
)

REM Still building, continue waiting
goto wait_loop

:build_success
echo Build succeeded!
echo Running smoke test...
smoke.exe
goto end

:build_failure
echo Build failed!
goto end

:end
pause

if %ERRORLEVEL% EQU 0 (
    echo Build successful!
    echo Running smoke test...
    smoke.exe
) else (
    echo Build failed!
)

pause
