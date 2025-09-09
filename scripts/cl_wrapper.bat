@echo off
setlocal enabledelayedexpansion

:: This script filters GCC flags and properly handles paths with spaces for MSVC cl.exe

set "args="
set "linker_args="
set "in_linker_mode=0"
set "skip_next=0"

:process_args
if "%~1"=="" goto execute

:: Check if we should skip this argument (because it was the value of a filtered flag)
if !skip_next! equ 1 (
    set "skip_next=0"
    echo [cl_wrapper] Skipping argument: %~1
    shift
    goto process_args
)

:: Check if we are processing linker arguments (after /link)
if "!in_linker_mode!"=="1" (
    :: Quote linker arguments that might contain spaces
    echo "%~1" | findstr /C:" " >nul
    if !errorlevel! equ 0 (
        set "linker_args=!linker_args! "%~1""
    ) else (
        set "linker_args=!linker_args! %~1"
    )
    shift
    goto process_args
)

:: Check for the /link delimiter that separates compiler flags from linker flags
if "%~1"=="/link" (
    set "in_linker_mode=1"
    set "args=!args! %~1"
    shift
    goto process_args
)

:: Filter out specific GCC flags that don't take values
if "%~1"=="-m64" (
    echo [cl_wrapper] Filtering out GCC flag: %~1
    shift
    goto process_args
)
if "%~1"=="-mthreads" (
    echo [cl_wrapper] Filtering out GCC flag: %~1
    shift
    goto process_args
)
if "%~1"=="-Wall" (
    echo [cl_wrapper] Filtering out GCC flag: %~1
    shift
    goto process_args
)
if "%~1"=="-Werror" (
    echo [cl_wrapper] Filtering out GCC flag: %~1
    shift
    goto process_args
)
if "%~1"=="-fPIC" (
    echo [cl_wrapper] Filtering out GCC flag: %~1
    shift
    goto process_args
)
if "%~1"=="-fPIE" (
    echo [cl_wrapper] Filtering out GCC flag: %~1
    shift
    goto process_args
)
if "%~1"=="-fno-stack-protector" (
    echo [cl_wrapper] Filtering out GCC flag: %~1
    shift
    goto process_args
)
if "%~1"=="-Wdeclaration-after-statement" (
    echo [cl_wrapper] Filtering out GCC flag: %~1
    shift
    goto process_args
)

:: Filter out GCC flags that take values
if "%~1"=="-fmessage-length" (
    echo [cl_wrapper] Filtering out GCC flag: %~1 %~2
    shift
    shift
    goto process_args
)
if "%~1"=="-frandom-seed" (
    echo [cl_wrapper] Filtering out GCC flag: %~1 %~2
    shift
    shift
    goto process_args
)
if "%~1"=="-Wl" (
    echo [cl_wrapper] Filtering out GCC linker flag: %~1 %~2
    shift
    shift
    goto process_args
)

:: Handle -I and -o flags properly (these are valid for MSVC too)
if "%~1"=="-I" (
    echo [cl_wrapper] Converting -I flag to MSVC format
    set "args=!args! /I"%~2""
    shift
    shift
    goto process_args
)
if "%~1"=="-o" (
    echo [cl_wrapper] Converting -o flag to MSVC format
    set "args=!args! /Fo"%~2""
    shift
    shift
    goto process_args
)

:: Handle -c flag (compile only)
if "%~1"=="-c" (
    echo [cl_wrapper] Converting -c flag to MSVC format
    set "args=!args! /c"
    shift
    goto process_args
)

:: Keep MSVC-compatible flags and file paths
echo "%~1" | findstr /C:" " >nul
if !errorlevel! equ 0 (
    set "args=!args! "%~1""
) else (
    set "args=!args! %~1"
)
shift
goto process_args

:execute
:: Run the real cl.exe with properly quoted arguments
echo [cl_wrapper] Executing: "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe" %args% %linker_args%
"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe" %args% %linker_args%
endlocal
