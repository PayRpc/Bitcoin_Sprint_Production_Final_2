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
set CGO_CFLAGS=-D_CRT_SECURE_NO_WARNINGS
set CGO_CXXFLAGS=-D_CRT_SECURE_NO_WARNINGS

cd /d "%~dp0\.."
echo Building Go smoke test (MSVC)...
echo CC=%CC%
echo CXX=%CXX%
echo CGO_ENABLED=%CGO_ENABLED%

go build -v ./cmd/smoke
if %ERRORLEVEL% neq 0 (
  echo GO BUILD FAILED exit %ERRORLEVEL%
  exit /b %ERRORLEVEL%
)

echo.
echo GO BUILD SUCCESS
echo.
echo Running smoke test...
go run ./cmd/smoke

echo Go build and test complete.
endlocal
exit /b 0
