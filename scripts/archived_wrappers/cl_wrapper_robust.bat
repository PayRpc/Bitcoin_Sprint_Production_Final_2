@echo off
setlocal enabledelayedexpansion

rem Simple wrapper that passes arguments to cl.exe with GCC flag filtering
echo %* > C:\temp\cl_args.log

rem Special case handling for compiler capability check
if "%~1"=="-###" (
    rem Ignore dry run
    exit /b 0
)

if "%~1"=="-dM" if "%~2"=="-E" if "%~3"=="-" (
    rem CGO capability check
    exit /b 0
)

rem Initialize filtered arguments list
set MSVC_ARGS=

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

rem Check for -Wl linker flags
echo.%~1 | findstr /b "-Wl" > nul
if not errorlevel 1 goto next_arg

rem Handle -I include paths
if "%~1"=="-I" (
    set "MSVC_ARGS=!MSVC_ARGS! /I"%~2""
    shift
    goto next_arg
)

rem Handle -I combined with path
echo.%~1 | findstr /b "-I" > nul
if not errorlevel 1 (
    for /f "tokens=* delims=-I" %%a in ("%~1") do set "include_path=%%a"
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

rem Pass through all other arguments
if "%~1" neq "" (
    rem Check if argument has spaces and quote it if needed
    echo.%~1 | findstr " " > nul
    if errorlevel 1 (
        set "MSVC_ARGS=!MSVC_ARGS! %~1"
    ) else (
        set "MSVC_ARGS=!MSVC_ARGS! "%~1""
    )
)

:next_arg
shift
goto parse_loop

:run_cl
echo cl.exe !MSVC_ARGS! >> C:\temp\cl_args.log
cl.exe !MSVC_ARGS!
exit /b %ERRORLEVEL%
