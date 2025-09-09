@echo off
setlocal

set "CLANG_DIR=C:\Program Files\LLVM\bin"
if not exist "%CLANG_DIR%\clang.exe" (
  echo ERROR: clang not found at %CLANG_DIR%\clang.exe
  exit /b 2
)

echo Prepending %CLANG_DIR% to PATH
set "PATH=%CLANG_DIR%;%PATH%"

echo --- where clang ---
where clang
if %ERRORLEVEL% neq 0 (
  echo ERROR: clang.exe not found in PATH
  exit /b 2
)

set "CC=clang"
set "CXX=clang++"
set "CGO_ENABLED=1"

rem Clear GCC-style env flags that might interfere
set "CFLAGS="
set "CXXFLAGS="
set "CPPFLAGS="
set "CGO_CFLAGS="
set "CGO_CPPFLAGS="
set "CGO_CXXFLAGS="
set "CGO_LDFLAGS="
set "GOGCCFLAGS="
set "GOFLAGS="

echo --- go env diagnostics ---
go env GOGCCFLAGS || echo "go env GOGCCFLAGS failed"

echo --- building Go smoke test with clang ---
cd /d "%~dp0\.."
go build -x -v .\cmd\smoke
echo GO BUILD EXIT CODE: %ERRORLEVEL%
endlocal
exit /b 0
