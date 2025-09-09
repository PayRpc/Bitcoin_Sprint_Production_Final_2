@echo off
REM Simplified wrapper that dumps args to a file and calls a PowerShell script to process them
setlocal enabledelayedexpansion

REM Special case 1: Exit immediately on -### (cgo debug)
if "%~1"=="-###" exit /b 0

REM Special case 2: Exit successfully on compiler capability check
if "%~1"=="-dM" if "%~2"=="-E" if "%~3"=="-" exit /b 0

REM Skip default preprocessor mode
if "%~1"=="-E" if "%~2"=="-dM" exit /b 0

REM Filter GCC flags that cause problems for MSVC
set MSVC_FLAGS=
for %%a in (%*) do (
  set "flag=%%a"
  
  REM Skip GCC-specific flags
  echo !flag! | findstr /r "^-m.* ^-W.* ^-fPIC ^-fPIE ^-f.*" > nul
  if !errorlevel! equ 0 (
    REM Skip this GCC flag
  ) else if "!flag!"=="-E" (
    REM Skip preprocessor flag
  ) else if "!flag!"=="-dM" (
    REM Skip preprocessor flag
  ) else if "!flag!"=="-c" (
    set "MSVC_FLAGS=!MSVC_FLAGS! /c"
  ) else if "!flag:~0,2!"=="-I" (
    REM Convert -I to /I
    set "include=!flag:~2!"
    set "MSVC_FLAGS=!MSVC_FLAGS! /I"!include!""
  ) else if "!flag!"=="-I" (
    REM Next arg is include path (handled below)
  ) else if "!flag!"=="-o" (
    REM Next arg is output path (handled below)
  ) else if "!flag!"=="-" (
    REM Skip stdin input
  ) else if "!flag!"=="-x" (
    REM Skip language specifier and the next arg
  ) else (
    set "MSVC_FLAGS=!MSVC_FLAGS! "!flag!""
  )
)

REM Invoke the MSVC compiler
"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe" !MSVC_FLAGS!
exit /b %errorlevel%
