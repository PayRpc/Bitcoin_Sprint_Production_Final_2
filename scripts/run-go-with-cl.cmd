@echo off
setlocal

rem Adjust CL_DIR if your MSVC version/path differs
set "CL_DIR=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64"

if not exist "%CL_DIR%\cl.exe" (
  echo ERROR: specified CL_DIR does not contain cl.exe: %CL_DIR%\cl.exe
  exit /b 2
)

echo Prepending %CL_DIR% to PATH
set "PATH=%CL_DIR%;%PATH%"

echo --- where cl ---
where cl
if %ERRORLEVEL% neq 0 (
  echo ERROR: cl.exe not found in PATH
  exit /b 2
)

set "CC=cl"
set "CXX=cl"
set "CGO_ENABLED=1"

rem Clear common GCC-style flags that may be injected into the compile command
set "CFLAGS="
set "CXXFLAGS="
set "CPPFLAGS="
set "CGO_CFLAGS="
set "CGO_CPPFLAGS="
set "CGO_CXXFLAGS="
set "CGO_LDFLAGS="

echo GOGCCFLAGS=%GOGCCFLAGS%
echo GOFLAGS=%GOFLAGS%
rem Unset GOGCCFLAGS/GOFLAGS if they contain GCC-style flags like -Werror
set "GOGCCFLAGS="
set "GOFLAGS="

echo --- go env diagnostics ---
go env GOGCCFLAGS || echo "go env GOGCCFLAGS failed"
go env CGO_CFLAGS || echo "go env CGO_CFLAGS failed"
go env CGO_CXXFLAGS || echo "go env CGO_CXXFLAGS failed"
go env CGO_LDFLAGS || echo "go env CGO_LDFLAGS failed"

echo --- building Go smoke test ---
cd /d "%~dp0\.."
go build -x -v .\cmd\smoke
echo GO BUILD EXIT CODE: %ERRORLEVEL%
endlocal
exit /b 0
