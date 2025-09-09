@echo off
setlocal enabledelayedexpansion

rem Log the arguments
echo %* > C:\temp\cl_args.log

rem Special case handling for compiler capability check
if "%~1"=="-###" (
    echo CGO dry run detected, exiting successfully >> C:\temp\cl_args.log
    exit /b 0
)

if "%~1"=="-dM" if "%~2"=="-E" if "%~3"=="-" (
    echo CGO capability check detected, exiting successfully >> C:\temp\cl_args.log
    exit /b 0
)

rem Initialize filtered arguments list
set "MSVC_ARGS="

:parse_loop
if "%~1"=="" goto run_cl

rem Skip GCC-style flags
if "%~1"=="-m64" goto next_arg
if "%~1"=="-mthreads" goto next_arg
if "%~1"=="-Wall" goto next_arg
if "%~1"=="-Werror" goto next_arg
if "%~1"=="-fPIC" goto next_arg
if "%~1"=="-fPIE" goto next_arg
if "%~1"=="-fno-stack-protector" goto next_arg
if "%~1"=="-Wdeclaration-after-statement" goto next_arg
if "%~1"=="-fomit-frame-pointer" goto next_arg
if "%~1"=="-dM" goto next_arg
if "%~1"=="-E" goto next_arg

rem Handle flags with arguments
if "%~1"=="-fmessage-length" (
    shift
    goto next_arg
)

rem Check for -Wl linker flags - use string prefix check
set "arg=%~1"
if "!arg:~0,4!"=="-Wl," goto next_arg

rem Handle -I include paths
if "%~1"=="-I" (
    if "%~2" NEQ "" (
        set "MSVC_ARGS=!MSVC_ARGS! /I"%~2""
        shift
    )
    goto next_arg
)

rem Handle -I combined with path
set "arg=%~1"
if "!arg:~0,2!"=="-I" (
    set "include_path=!arg:~2!"
    set "MSVC_ARGS=!MSVC_ARGS! /I"!include_path!""
    goto next_arg
)

rem Handle -o output file
if "%~1"=="-o" (
    if "%~2" NEQ "" (
        set "MSVC_ARGS=!MSVC_ARGS! /Fo"%~2""
        shift
    )
    goto next_arg
)

rem Handle -c compile only
if "%~1"=="-c" (
    set "MSVC_ARGS=!MSVC_ARGS! /c"
    goto next_arg
)

rem Ignore -x language flag
if "%~1"=="-x" (
    shift
    goto next_arg
)

rem Pass through source files and other arguments
set "arg=%~1"
if "!arg:~-2!"==".c" (
    set "MSVC_ARGS=!MSVC_ARGS! "%~1""
) else if "!arg:~0,1!"=="/" (
    set "MSVC_ARGS=!MSVC_ARGS! %~1"
) else if "!arg:~0,2!"=="/D" (
    set "MSVC_ARGS=!MSVC_ARGS! %~1"
) else if "!arg:~0,2!"=="/I" (
    set "MSVC_ARGS=!MSVC_ARGS! %~1"
) else if "!arg:~0,2!"=="/W" (
    set "MSVC_ARGS=!MSVC_ARGS! %~1"
) else if "!arg:~0,2!"=="/O" (
    set "MSVC_ARGS=!MSVC_ARGS! %~1"
) else (
    rem Safely add other arguments
    echo [DBG] Adding arg: %~1 >> C:\temp\cl_args.log
    set "MSVC_ARGS=!MSVC_ARGS! "%~1""
)

:next_arg
shift
goto parse_loop

:run_cl
echo Final command: "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe" !MSVC_ARGS! >> C:\temp\cl_args.log
"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe" !MSVC_ARGS!
exit /b %ERRORLEVEL%
