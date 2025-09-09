@echo off
setlocal enabledelayedexpansion

rem Simple wrapper that passes arguments to cl.exe with GCC flag filtering
echo %* > C:\temp\cl_args.log

rem Special case handling for compiler capability check
if "%~1"=="-###" (
    echo CGO dry run detected, exiting 0 >> C:\temp\cl_args.log
    exit /b 0
)

if "%~1"=="-dM" if "%~2"=="-E" if "%~3"=="-" (
    echo CGO capability check detected, exiting 0 >> C:\temp\cl_args.log
    exit /b 0
)

rem Initialize filtered arguments list
set "MSVC_ARGS="
set "SOURCE_FILE="

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

rem Handle flags with arguments
if "%~1"=="-fmessage-length" (
    shift
    goto next_arg
)

rem Check for -Wl linker flags - use string prefix check without findstr
set "arg=%~1"
if "!arg:~0,4!"=="-Wl," goto next_arg

rem Handle -I include paths
if "%~1"=="-I" (
    set "MSVC_ARGS=!MSVC_ARGS! /I"%~2""
    shift
    goto next_arg
)

rem Handle -I combined with path - use string prefix check without findstr
set "arg=%~1"
if "!arg:~0,2!"=="-I" (
    set "include_path=!arg:~2!"
    set "MSVC_ARGS=!MSVC_ARGS! /I"!include_path!""
    goto next_arg
)

rem Handle -o output file
if "%~1"=="-o" (
    set "MSVC_ARGS=!MSVC_ARGS! /Fo"%~2""
    shift
    goto next_arg
)

rem Handle -c compile only
if "%~1"=="-c" (
    set "MSVC_ARGS=!MSVC_ARGS! /c"
    goto next_arg
)

rem Ignore -E preprocessor flag
if "%~1"=="-E" goto next_arg

rem Ignore -x language flag
if "%~1"=="-x" (
    shift
    goto next_arg
)

rem Ignore -dM define flag
if "%~1"=="-dM" goto next_arg

rem Check for source file (.c extension)
set "arg=%~1"
if "!arg:~-2!"==".c" (
    set "SOURCE_FILE=!arg!"
    set "MSVC_ARGS=!MSVC_ARGS! "!arg!""
    goto next_arg
)

rem Pass through all other arguments
if "%~1" neq "" (
    rem Check if argument has spaces - safer method without findstr
    set "arg=%~1"
    set "arg_no_spaces=!arg: =!"
    if not "!arg!"=="!arg_no_spaces!" (
        set "MSVC_ARGS=!MSVC_ARGS! "%~1""
    ) else (
        set "MSVC_ARGS=!MSVC_ARGS! %~1"
    )
)

:next_arg
shift
goto parse_loop

:run_cl
echo cl.exe !MSVC_ARGS! >> C:\temp\cl_args.log

rem Check if we have a source file
if "!SOURCE_FILE!"=="" (
    echo No source file found in command line >> C:\temp\cl_args.log
    exit /b 0
)

cl.exe !MSVC_ARGS!
exit /b %ERRORLEVEL%
