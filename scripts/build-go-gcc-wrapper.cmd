@echo off
REM Build Go smoke test using GCC wrapper that accepts MSVC-style flags
REM This allows CGO to work with GCC while Go thinks it's using MSVC

echo Setting up MSVC environment for Go CGO build...
echo.

REM Check if we're in MSVC Developer Command Prompt
if "%VSCMD_ARG_TGT_ARCH%"=="" (
    echo ERROR: This script must be run from MSVC Developer Command Prompt
    echo Please run: "x64 Native Tools Command Prompt for VS 2022"
    echo Then cd to the project directory and run this script
    pause
    exit /b 1
)

REM Set Go environment variables
set CGO_ENABLED=1
set "CC=%~dp0cl-to-gcc-wrapper.cmd"
set "CXX=%~dp0cl-to-gcc-wrapper.cmd"

REM Add GCC to PATH if not already there
REM Assuming GCC is installed via MSYS2 or similar
set PATH=C:\msys64\mingw64\bin;%PATH%

REM Set CGO flags to work with GCC
set CGO_CFLAGS=-D_CRT_SECURE_NO_WARNINGS -DWIN32 -D_WIN32 -Wno-error
set CGO_CXXFLAGS=-D_CRT_SECURE_NO_WARNINGS -DWIN32 -D_WIN32 -Wno-error
set CGO_LDFLAGS=-L%~dp0..\..\secure\rust\target\release -lsecurebuffer -lws2_32 -ladvapi32 -luserenv

echo Building Go smoke test with CGO enabled...
echo CC=%CC%
echo CXX=%CXX%
echo CGO_ENABLED=%CGO_ENABLED%
echo.

REM Build the smoke test
go build -v ./cmd/smoke

if %errorlevel% neq 0 (
    echo.
    echo Build failed with error code %errorlevel%
    echo.
    echo Common issues:
    echo - GCC not found in PATH (install MSYS2 or MinGW)
    echo - Rust library not built (run: cd secure/rust && cargo build --release)
    echo - Missing dependencies (run: go mod tidy)
    echo.
    pause
    exit /b 1
)

echo.
echo Build successful! Running smoke test...
echo.

REM Run the smoke test
bitcoin-sprint.exe

if %errorlevel% neq 0 (
    echo.
    echo Smoke test failed with error code %errorlevel%
    pause
    exit /b 1
)

echo.
echo Smoke test completed successfully!
pause
