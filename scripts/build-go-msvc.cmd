@echo off
setlocal
set VSDEVCMD="C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
if not exist %VSDEVCMD% set VSDEVCMD="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat"
echo Calling %VSDEVCMD%
call %VSDEVCMD% -arch=amd64

where cl || (
  echo ERROR: cl.exe not found in PATH after running VsDevCmd.bat
  exit /b 2
)

set CC=cl
set CXX=cl
set CGO_ENABLED=1

cd /d "%~dp0\.."
echo Building Go smoke test (MSVC)...
go env
go build -v ./cmd/smoke
if %ERRORLEVEL% neq 0 (
  echo GO BUILD FAILED exit %ERRORLEVEL%
  exit /b %ERRORLEVEL%
)

echo Go build complete.
endlocal
exit /b 0
