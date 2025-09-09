@echo off
REM Simplified wrapper that handles most common CGO flags for MSVC
setlocal enabledelayedexpansion

REM Log original arguments
echo CGO Arguments: %* > C:\temp\cl_wrapper_debug.txt

REM Special cases
if "%~1"=="-###" (
    echo "Dry run detected, exiting" >> C:\temp\cl_wrapper_debug.txt
    exit /b 0
)
if "%~1"=="-dM" if "%~2"=="-E" if "%~3"=="-" (
    echo "Compiler capability check, exiting" >> C:\temp\cl_wrapper_debug.txt
    exit /b 0
)

REM Prepare for argument conversion
set "MSVC_ARGS="
set "i=0"
set "ARG_COUNT=%~#"

:PARSE_ARGS
if %i% geq %ARG_COUNT% goto EXEC_CL

REM Get current argument and increment counter
set /a "i+=1"
set "arg=!%i%!"

REM Skip GCC flags
echo !arg! | findstr /r /c:"^-m" /c:"^-W" /c:"^-f" > nul
if !errorlevel! equ 0 (
    echo Filtering flag: !arg! >> C:\temp\cl_wrapper_debug.txt
    goto PARSE_ARGS
)

REM Handle preprocessor flags
if "!arg!"=="-dM" (
    echo Filtering preprocessor flag: !arg! >> C:\temp\cl_wrapper_debug.txt
    goto PARSE_ARGS
)
if "!arg!"=="-E" (
    echo Filtering preprocessor flag: !arg! >> C:\temp\cl_wrapper_debug.txt
    goto PARSE_ARGS
)

REM Handle -c (compile only)
if "!arg!"=="-c" (
    echo Converting -c to /c >> C:\temp\cl_wrapper_debug.txt
    set "MSVC_ARGS=!MSVC_ARGS! /c"
    goto PARSE_ARGS
)

REM Handle -I paths
echo !arg! | findstr /r /c:"^-I" > nul
if !errorlevel! equ 0 (
    set "include=!arg:~2!"
    echo Converting -I to /I: !include! >> C:\temp\cl_wrapper_debug.txt
    set "MSVC_ARGS=!MSVC_ARGS! /I"!include!""
    goto PARSE_ARGS
)
if "!arg!"=="-I" (
    if %i% lss %ARG_COUNT% (
        set /a "i+=1"
        set "path=!%i%!"
        echo Converting -I to /I: !path! >> C:\temp\cl_wrapper_debug.txt
        set "MSVC_ARGS=!MSVC_ARGS! /I"!path!""
    )
    goto PARSE_ARGS
)

REM Handle -o output
if "!arg!"=="-o" (
    if %i% lss %ARG_COUNT% (
        set /a "i+=1"
        set "outpath=!%i%!"
        echo Converting -o to /Fo: !outpath! >> C:\temp\cl_wrapper_debug.txt
        set "MSVC_ARGS=!MSVC_ARGS! /Fo"!outpath!""
    )
    goto PARSE_ARGS
)

REM Handle -x language specifier
if "!arg!"=="-x" (
    if %i% lss %ARG_COUNT% (
        set /a "i+=1"
        echo Skipping -x and language: !%i%! >> C:\temp\cl_wrapper_debug.txt
    )
    goto PARSE_ARGS
)

REM Handle stdin
if "!arg!"=="-" (
    echo Skipping stdin marker >> C:\temp\cl_wrapper_debug.txt
    goto PARSE_ARGS
)

REM Default case: keep the argument, quoted if it contains spaces
echo !arg! | findstr " " > nul
if !errorlevel! equ 0 (
    echo Keeping quoted argument: !arg! >> C:\temp\cl_wrapper_debug.txt
    set "MSVC_ARGS=!MSVC_ARGS! "!arg!""
) else (
    echo Keeping argument: !arg! >> C:\temp\cl_wrapper_debug.txt
    set "MSVC_ARGS=!MSVC_ARGS! !arg!"
)
goto PARSE_ARGS

:EXEC_CL
echo Final MSVC args: !MSVC_ARGS! >> C:\temp\cl_wrapper_debug.txt
echo Executing cl.exe !MSVC_ARGS! >> C:\temp\cl_wrapper_debug.txt
cl.exe !MSVC_ARGS!
exit /b %ERRORLEVEL%
