@echo off
REM MSVC cl.exe wrapper that filters out GCC-style flags

setlocal enabledelayedexpansion

REM Build the command line, filtering out problematic flags
set "ARGS="

:parse_args
if "%~1"=="" goto :execute

REM Debug: show all arguments
echo Processing arg: %~1 1>&2
if "%~1"=="/Werror" (
    REM echo Filtering out /Werror
    goto :next
)
if "%~1"=="-Werror" (
    REM echo Filtering out -Werror
    goto :next
)
if "%~1"=="/Wno-error" (
    REM echo Filtering out /Wno-error
    goto :next
)
if "%~1"=="-Wno-error" (
    REM echo Filtering out -Wno-error
    goto :next
)
if "%~1"=="/Wno-error=*" (
    REM echo Filtering out /Wno-error=*
    goto :next
)
if "%~1"=="-Wno-error=*" (
    REM echo Filtering out -Wno-error=*
    goto :next
)
REM Skip GCC linker flags - check if it starts with /Wl,
echo %~1 | findstr "^/Wl," >nul
if %errorlevel% equ 0 (
    echo Filtering out /Wl linker flag: %~1 1>&2
    goto :next
)
REM Skip GCC linker flags - check if it starts with -Wl,
echo %~1 | findstr "^-Wl," >nul
if %errorlevel% equ 0 (
    REM echo Filtering out -Wl linker flag: %~1
    goto :next
)
REM Skip other GCC-specific flags
if "%~1"=="-fPIC" (
    REM echo Filtering out -fPIC
    goto :next
)
if "%~1"=="-fPIE" (
    REM echo Filtering out -fPIE
    goto :next
)

REM If /Wl or -Wl is encountered, skip it and the next argument
if "%~1"=="/Wl" (
    echo Filtering out /Wl and next arg: %~2 1>&2
    shift
    goto :next
)
if "%~1"=="-Wl" (
    echo Filtering out -Wl and next arg: %~2 1>&2
    shift
    goto :next
)

REM For other flags, keep them as-is
set "ARGS=!ARGS! "%~1""

:next
shift
goto :parse_args

:execute
REM Find the real cl.exe in PATH
for /f "tokens=*" %%i in ('where cl.exe 2^>nul') do set "CL_EXE=%%i" & goto :found_cl
echo ERROR: cl.exe not found in PATH 1>&2
exit /b 1

:found_cl
REM Execute the real cl.exe with filtered arguments
REM echo !CL_EXE! !ARGS! 1>&2
!CL_EXE! !ARGS!

endlocal
