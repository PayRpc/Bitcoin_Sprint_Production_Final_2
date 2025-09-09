@echo off
setlocal
set VSDEVCMD="C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
if not exist %VSDEVCMD% set VSDEVCMD="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat"
echo Calling %VSDEVCMD%
call %VSDEVCMD% -arch=amd64

rem Ensure our scripts folder is first on PATH so clang-cl wrapper is picked up
set SCRIPTSDIR=%~dp0
set PATH=%SCRIPTSDIR%;%PATH%

where clang-cl || (
  echo ERROR: clang-cl not found in PATH after running VsDevCmd.bat
  exit /b 2
)

rem Clear GCC-style flags that can confuse clang-cl when passed by Go's toolchain
set GOGCCFLAGS=
set GOFLAGS=
set CGO_CFLAGS=
set CGO_CXXFLAGS=
set CGO_LDFLAGS=

rem Add flags that make clang-cl accept/ignore GCC-style options Go may pass
set CGO_CFLAGS=-Wno-error -Wno-error=unknown-argument -Wno-error=unknown-warning-option -Wno-error=unused-macros -Wno-unused-macros -Wno-error=reserved-identifier -Wno-error=missing-prototypes -Wno-error=strict-prototypes -Wno-error=unused-parameter -Wno-error=missing-noreturn -Wno-error=sign-conversion -Wno-error=missing-variable-declarations -Wno-error=nonportable-system-include-path -Wno-error=language-extension-token -Wno-error=implicit-int-conversion -Wno-error=pointer-integer-compare -Wno-error=implicit -Wno-error=incompatible-pointer-types -Qunused-arguments -ferror-limit=0
set CGO_CXXFLAGS=%CGO_CFLAGS%

rem Use GCC for the entire build process to avoid cgo type checking issues
set CC=gcc
set CXX=g++

rem Instruct the Go toolchain (GOGCCFLAGS) to pass these flags too when it invokes clang-cl
set GOGCCFLAGS=-Wno-error=reserved-identifier -Wno-error=unknown-argument -Wno-error=unknown-warning-option -Wno-error=unused-macros -Wno-error=missing-prototypes -Wno-error=strict-prototypes -Wno-error=unused-parameter -Wno-error=missing-noreturn -Wno-error=sign-conversion -Wno-error=missing-variable-declarations -Wno-error=nonportable-system-include-path -Wno-error=language-extension-token -Wno-error=implicit-int-conversion -Wno-error=pointer-integer-compare -Qunused-arguments

set CC="C:\Program Files\LLVM\bin\clang-cl.exe"
set CXX="C:\Program Files\LLVM\bin\clang-cl.exe"
set CGO_ENABLED=1

cd /d "%~dp0\.."
echo Building Go smoke test with clang-cl (MSVC env)...
go env
go build -x -v ./cmd/smoke
if %ERRORLEVEL% neq 0 (
  echo GO BUILD FAILED exit %ERRORLEVEL%
  exit /b %ERRORLEVEL%
)

echo Go build complete.
endlocal
exit /b 0
