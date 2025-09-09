@echo off
REM MSVC cl.exe wrapper that filters out GCC-style flags
REM This is the definitive solution for CGO + MSVC integration

setlocal enabledelayedexpansion

REM Build the command line, filtering out problematic flags
set "ARGS="

:parse_args
if "%~1"=="" goto :execute

REM Debug: show all arguments (comment out for production)
REM echo Processing arg: %~1 1>&2

REM === Handle flags that take arguments ===

REM Include directory (-I path)
if "%~1"=="-I" (
    if not "%~2"=="" (
        set "ARGS=!ARGS! "/I%~2""
        shift
        shift
        goto :parse_args
    )
)

REM Output file (-o path)
if "%~1"=="-o" (
    if not "%~2"=="" (
        set "ARGS=!ARGS! "/Fo%~2""
        shift
        shift
        goto :parse_args
    )
)

REM === GCC/MinGW-specific flags to filter out ===

REM Warning flags (-W...)
echo %~1 | findstr "^-W" >nul
if %errorlevel% equ 0 (
    goto :next
)

REM Machine/target flags (-m...)
echo %~1 | findstr "^-m" >nul
if %errorlevel% equ 0 (
    goto :next
)

REM Feature flags (-f...)
echo %~1 | findstr "^-f" >nul
if %errorlevel% equ 0 (
    goto :next
)

REM Linker flags (-Wl)
if "%~1"=="-Wl" (
    shift
    goto :next
)

REM Other GCC-specific flags
if "%~1"=="-pthread" goto :next
if "%~1"=="-pipe" goto :next
if "%~1"=="-g" goto :next
if "%~1"=="-O0" goto :next
if "%~1"=="-O1" goto :next
if "%~1"=="-O2" goto :next
if "%~1"=="-O3" goto :next
if "%~1"=="-Os" goto :next
if "%~1"=="-Og" goto :next

REM === MSVC-compatible flags and files to keep ===

REM Include directories (-I becomes /I for MSVC, but CGO should pass /I already)
REM Define macros (-D becomes /D for MSVC, but CGO should pass /D already)
REM Keep all /... flags (MSVC style)
REM Keep all source files (.c, .cpp, .cc, .cxx, .S)
REM Keep output specification (-o, /Fo, /Fe)

REM For other flags, keep them as-is (including MSVC /... flags and filenames)
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
