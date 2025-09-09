@echo off
REM Build Go smoke test using MSVC with CGO - Alternative approach
REM Uses MSVC directly but tries to avoid GCC-style flags

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

REM Set Go environment variables for MSVC
set CGO_ENABLED=1
set CC=cl.exe
set CXX=cl.exe

REM Try to override CGO flags to avoid GCC-style flags
set CGO_CPPFLAGS=
set CGO_CFLAGS=/D_CRT_SECURE_NO_WARNINGS /DWIN32 /D_WIN32 /W3 /O2
set CGO_CXXFLAGS=/D_CRT_SECURE_NO_WARNINGS /DWIN32 /D_WIN32 /W3 /O2 /EHsc
set CGO_LDFLAGS=/LIBPATH:%~dp0..\..\secure\rust\target\release securebuffer.lib ws2_32.lib advapi32.lib userenv.lib

echo Building Go smoke test with CGO enabled...
echo CC=%CC%
echo CXX=%CXX%
echo CGO_ENABLED=%CGO_ENABLED%
echo CGO_CFLAGS=%CGO_CFLAGS%
echo.

REM Build the smoke test
go build -v ./cmd/smoke

if %errorlevel% neq 0 (
    echo.
    echo Build failed with error code %errorlevel%
    echo.
    echo This might be due to Go's CGO system still generating GCC-style flags.
    echo Try using the GCC wrapper approach instead.
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
