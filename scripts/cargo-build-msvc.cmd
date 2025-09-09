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
cd /d "%~dp0\..\secure\rust"
echo Building Rust release (MSVC) (library-only)...
cargo build --release --lib
set EXITCODE=%ERRORLEVEL%
echo cargo exit code %EXITCODE%
endlocal & exit /b %EXITCODE%
