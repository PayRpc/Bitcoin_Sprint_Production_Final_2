@echo off
REM Launch MSVC Developer Command Prompt and run MSVC direct build

echo Launching MSVC Developer Command Prompt...
echo.

REM Find Visual Studio installation
for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
    set "VS_PATH=%%i"
)

if not defined VS_PATH (
    echo ERROR: Visual Studio 2022 not found
    echo Please install Visual Studio 2022 with C++ development tools
    pause
    exit /b 1
)

REM Launch Developer Command Prompt and run our build script
"%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" && cd /d "%~dp0" && scripts\build-go-msvc-direct.cmd

pause
