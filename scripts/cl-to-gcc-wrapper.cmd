@echo off
REM GCC wrapper that acts like cl.exe but calls GCC
REM This allows Go's CGO to work with GCC-style flags

setlocal enabledelayedexpansion

REM Convert MSVC-style flags to GCC equivalents
set "ARGS="
set "output_file="
set "source_files="

:parse_args
if "%~1"=="" goto :execute

REM Convert MSVC flags to GCC
if "%~1"=="/c" (
    REM /c means compile only (don't link)
    set "ARGS=!ARGS! -c"
    goto :next
)
if "%~1"=="/O2" (
    REM /O2 means optimize for speed
    set "ARGS=!ARGS! -O2"
    goto :next
)
if "%~1"=="/Zi" (
    REM /Zi means debug info
    set "ARGS=!ARGS! -g"
    goto :next
)
if "%~1"=="/W3" (
    REM /W3 means warning level 3
    set "ARGS=!ARGS! -Wall"
    goto :next
)
if "%~1"=="/MD" (
    REM /MD means multithreaded DLL
    REM Skip for GCC
    goto :next
)
if "%~1"=="/D" (
    REM /D means define macro
    set "ARGS=!ARGS! -D%~2"
    shift
    goto :next
)
if "%~1"=="/I" (
    REM /I means include path
    set "ARGS=!ARGS! -I%~2"
    shift
    goto :next
)
if "%~1"=="/Fo" (
    REM /Fo means output file
    set "output_file=%~2"
    shift
    goto :next
)

REM Check if it's a source file
echo %~1 | findstr "\.c\|\.cpp\|\.cc\|\.cxx" >nul
if %errorlevel% equ 0 (
    set "source_files=!source_files! %~1"
    goto :next
)

REM For other flags, try to convert / to -
echo %~1 | findstr "^/" >nul
if %errorlevel% equ 0 (
    REM Convert leading / to -
    for /f "tokens=1,* delims=/" %%a in ("%~1") do (
        set "ARGS=!ARGS! -%%b"
    )
) else (
    REM Pass through as-is
    set "ARGS=!ARGS! %~1"
)

:next
shift
goto :parse_args

:execute
REM Build the GCC command
if defined output_file (
    set "GCC_CMD=gcc !ARGS! !source_files! -o !output_file!"
) else (
    set "GCC_CMD=gcc !ARGS! !source_files!"
)

REM Execute GCC
REM echo !GCC_CMD!
!GCC_CMD!

endlocal
