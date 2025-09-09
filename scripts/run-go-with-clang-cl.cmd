@echo off
setlocal

rem Prefer Community VsDevCmd, fallback to BuildTools
set VSDEVCMD="C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
if not exist %VSDEVCMD% set VSDEVCMD="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat"

echo Calling %VSDEVCMD%
call %VSDEVCMD% -arch=amd64

rem Ensure LLVM clang-cl exists
set "LLVM_DIR=C:\Program Files\LLVM\bin"
if exist "%LLVM_DIR%\clang-cl.exe" (
  set "PATH=%LLVM_DIR%;%PATH%"
) else (
  echo ERROR: clang-cl.exe not found in %LLVM_DIR%
  exit /b 2
)

echo --- verify tools ---
where clang-cl || (echo clang-cl not found && exit /b 2)
where cl || echo cl not found (ok if using clang-cl)

set "CC=clang-cl"
set "CXX=clang-cl"
set "CGO_ENABLED=1"

rem Clear GCC-style env flags
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

echo --- building Go smoke test with clang-cl ---
cd /d "%~dp0\.."
go build -x -v .\cmd\smoke
echo GO BUILD EXIT CODE: %ERRORLEVEL%
endlocal
exit /b 0
