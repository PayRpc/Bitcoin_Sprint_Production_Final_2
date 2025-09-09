@echo off
rem Build the Go smoke test using MSVC (must run in same cmd process)
rem Adjust the path to VsDevCmd.bat if your VS installation is in a different location.

setlocal

rem Try common VS Developer Command Prompt locations
set VSDEVCMD="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat"
if not exist %VSDEVCMD% set VSDEVCMD="C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
if not exist %VSDEVCMD% set VSDEVCMD="C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"

echo Using VsDevCmd: %VSDEVCMD%
call %VSDEVCMD% -arch=amd64

echo --- verify cl.exe is available ---
where cl || (
  echo ERROR: cl.exe not found in PATH after running VsDevCmd.bat
  echo Please open a Developer Command Prompt and run this script from there, or adjust VSDEVCMD variable.
  exit /b 2
)

rem Set environment variables for cgo
set CC=cl
set CXX=cl
set CGO_ENABLED=1

echo PATH=%PATH%
echo --- building Go smoke test ---
cd /d "%~dp0\.."
go build -v .\cmd\smoke
if %ERRORLEVEL% neq 0 (
  echo GO BUILD FAILED with exit code %ERRORLEVEL%
  exit /b %ERRORLEVEL%
)

echo Build complete.
endlocal
exit /b 0
