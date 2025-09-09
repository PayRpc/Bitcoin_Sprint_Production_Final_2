@echo off
REM Build Go smoke test with GCC (MinGW)
echo Building Go smoke test with GCC...

REM Set GCC as the compiler
set CC=gcc
set CXX=g++
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
