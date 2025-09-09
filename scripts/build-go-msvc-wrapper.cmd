@echo off
REM Build Go smoke test with MSVC using wrapper to filter GCC flags
echo Calling "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"

echo Building Go smoke test (MSVC with wrapper)...
set "SCRIPT_DIR=%~dp0"
set CC="%SCRIPT_DIR%cl-wrapper.cmd"
set CXX="%SCRIPT_DIR%cl-wrapper.cmd"
set CGO_ENABLED=1

echo CC=%CC%
echo CXX=%CXX%
echo CGO_ENABLED=%CGO_ENABLED%

go build -v ./cmd/smoke

if %ERRORLEVEL% EQU 0 (
    echo.
    echo GO BUILD SUCCESS
    echo.
    echo Running smoke test...
    go run ./cmd/smoke
) else (
    echo.
    echo GO BUILD FAILED exit %ERRORLEVEL%
)
