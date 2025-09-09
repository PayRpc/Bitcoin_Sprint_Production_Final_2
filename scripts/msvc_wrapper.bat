@echo off
setlocal enabledelayedexpansion

rem Log the invocation
echo [msvc_wrapper] Called with: %* >> C:\temp\msvc_wrapper_log.txt

rem Special cases for CGO capability probes
if "%~1"=="-###" (
    echo [msvc_wrapper] Detected CGO dry-run, exiting successfully >> C:\temp\msvc_wrapper_log.txt
    exit /b 0
)
if "%~1"=="-E" if "%~2"=="-dM" (
    echo [msvc_wrapper] Detected CGO preprocessor probe, exiting successfully >> C:\temp\msvc_wrapper_log.txt
    exit /b 0
)
if "%~1"=="-dM" if "%~2"=="-E" (
    echo [msvc_wrapper] Detected CGO preprocessor probe, exiting successfully >> C:\temp\msvc_wrapper_log.txt
    exit /b 0
)

rem Setup the MSVC arguments collection
set "MSVC_ARGS="
set "i=0"
set "skip_next=0"

:arg_loop
if "%~1"=="" goto run_cl

rem Skip if this is a value for a flag we already processed
if "%skip_next%"=="1" (
    set "skip_next=0"
    shift
    goto arg_loop
)

rem Special case for stdin handling
if "%~1"=="-" (
    echo [msvc_wrapper] Ignoring stdin input request >> C:\temp\msvc_wrapper_log.txt
    shift
    goto arg_loop
)

rem Handle language flags
if "%~1"=="-x" (
    echo [msvc_wrapper] Filtering language flag: %~1 %~2 >> C:\temp\msvc_wrapper_log.txt
    set "skip_next=1"
    shift
    goto arg_loop
)

rem Handle flags that take a value
if "%~1"=="-fmessage-length" (
    echo [msvc_wrapper] Filtering flag with value: %~1 %~2 >> C:\temp\msvc_wrapper_log.txt
    set "skip_next=1"
    shift
    goto arg_loop
)
if "%~1"=="-frandom-seed" (
    echo [msvc_wrapper] Filtering flag with value: %~1 %~2 >> C:\temp\msvc_wrapper_log.txt
    set "skip_next=1"
    shift
    goto arg_loop
)

rem Filter GCC compilation and warning flags
if "%~1"=="-m64" goto filter_flag
if "%~1"=="-mthreads" goto filter_flag
if "%~1"=="-Wall" goto filter_flag
if "%~1"=="-Werror" goto filter_flag
if "%~1"=="-fno-stack-protector" goto filter_flag
if "%~1"=="-Wdeclaration-after-statement" goto filter_flag
if "%~1"=="-fPIC" goto filter_flag
if "%~1"=="-fPIE" goto filter_flag
if "%~1"=="-dM" goto filter_flag
if "%~1"=="-E" goto filter_flag

rem Check for -Wl, flags (linker flags)
echo.%~1 | findstr /b /C:"-Wl," > nul 2>&1
if %errorlevel% equ 0 goto filter_flag

rem Convert -I include paths to MSVC format
if "%~1"=="-I" (
    echo [msvc_wrapper] Converting include path: %~1 %~2 >> C:\temp\msvc_wrapper_log.txt
    if "%~2"=="" goto next_arg
    set "MSVC_ARGS=!MSVC_ARGS! /I"%~2""
    set "skip_next=1"
    shift
    goto arg_loop
)

rem Handle combined -I paths
echo.%~1 | findstr /b /C:"-I" > nul 2>&1
if %errorlevel% equ 0 (
    set "incpath=%~1"
    set "incpath=!incpath:-I=!"
    echo [msvc_wrapper] Converting combined include path: -I!incpath! >> C:\temp\msvc_wrapper_log.txt
    set "MSVC_ARGS=!MSVC_ARGS! /I"!incpath!""
    goto next_arg
)

rem Convert -o to /Fo for output
if "%~1"=="-o" (
    echo [msvc_wrapper] Converting output path: %~1 %~2 >> C:\temp\msvc_wrapper_log.txt
    if "%~2"=="" goto next_arg
    set "MSVC_ARGS=!MSVC_ARGS! /Fo"%~2""
    set "skip_next=1"
    shift
    goto arg_loop
)

rem Convert -c compile-only flag
if "%~1"=="-c" (
    echo [msvc_wrapper] Converting compile flag: %~1 >> C:\temp\msvc_wrapper_log.txt
    set "MSVC_ARGS=!MSVC_ARGS! /c"
    goto next_arg
)

rem Pass through source files and other arguments
echo.%~1 | findstr /R "\.c$" > nul 2>&1
if %errorlevel% equ 0 (
    echo [msvc_wrapper] Found source file: %~1 >> C:\temp\msvc_wrapper_log.txt
    set "MSVC_ARGS=!MSVC_ARGS! "%~1""
    goto next_arg
)

rem Pass through Windows-style flags
echo.%~1 | findstr /b /C:"/" > nul 2>&1
if %errorlevel% equ 0 (
    echo [msvc_wrapper] Passing through MSVC flag: %~1 >> C:\temp\msvc_wrapper_log.txt
    set "MSVC_ARGS=!MSVC_ARGS! %~1"
    goto next_arg
)

rem Pass through defines
echo.%~1 | findstr /b /C:"-D" > nul 2>&1
if %errorlevel% equ 0 (
    set "def=%~1"
    set "def=!def:-D=/D!"
    echo [msvc_wrapper] Converting define: %~1 to !def! >> C:\temp\msvc_wrapper_log.txt
    set "MSVC_ARGS=!MSVC_ARGS! !def!"
    goto next_arg
)

echo [msvc_wrapper] Unknown flag, passing through: %~1 >> C:\temp\msvc_wrapper_log.txt
set "MSVC_ARGS=!MSVC_ARGS! %~1"
goto next_arg

:filter_flag
echo [msvc_wrapper] Filtering GCC flag: %~1 >> C:\temp\msvc_wrapper_log.txt
goto next_arg

:next_arg
shift
goto arg_loop

:run_cl
echo [msvc_wrapper] Running MSVC with args: !MSVC_ARGS! >> C:\temp\msvc_wrapper_log.txt

rem Check if we have any arguments to pass
if "!MSVC_ARGS!"=="" (
    echo [msvc_wrapper] No arguments to pass to cl.exe, exiting >> C:\temp\msvc_wrapper_log.txt
    exit /b 0
)

rem Run the MSVC compiler
"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe" !MSVC_ARGS!
set ERRORLEVEL_SAVE=%ERRORLEVEL%
echo [msvc_wrapper] cl.exe exited with code %ERRORLEVEL_SAVE% >> C:\temp\msvc_wrapper_log.txt
exit /b %ERRORLEVEL_SAVE%
