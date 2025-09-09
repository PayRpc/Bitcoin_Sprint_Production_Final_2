@echo off
setlocal

rem Call Visual Studio Developer Command Prompt to set INCLUDE/LIB and PATH
set VSDEVCMD="C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
if not exist %VSDEVCMD% set VSDEVCMD="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat"

echo Calling %VSDEVCMD%
call %VSDEVCMD% -arch=amd64

rem Ensure LLVM clang exists
set "CLANG_DIR=C:\Program Files\LLVM\bin"
if not exist "%CLANG_DIR%\clang.exe" (
  echo ERROR: clang not found at %CLANG_DIR%\clang.exe
  exit /b 2
)

echo Prepending %CLANG_DIR% to PATH
set "PATH=%CLANG_DIR%;%PATH%"

echo --- verify tools ---
where clang || (echo clang not found && exit /b 2)
where cl || echo cl not found (ok if not using cl)

set "CC=clang"
set "CXX=clang++"
set "CGO_ENABLED=1"

rem Clear interfering env vars
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

echo --- building Go smoke test with clang+MSVC environment ---
cd /d "%~dp0\.."
go build -x -v .\cmd\smoke
echo GO BUILD EXIT CODE: %ERRORLEVEL%
endlocal
exit /b 0
