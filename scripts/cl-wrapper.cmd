@echo off
REM MSVC wrapper script to convert GCC-style flags to MSVC equivalents
setlocal enabledelayedexpansion

REM Get all arguments
set "ARGS="

REM Parse arguments and convert GCC flags to MSVC
:parse_args
if "%~1"=="" goto :execute

REM Convert GCC-style flags to MSVC equivalents
if "%~1"=="-Werror" (
    REM Skip -Werror (MSVC doesn't have direct equivalent)
    goto :next
)
if "%~1"=="-Wno-error" (
    REM Skip -Wno-error flags
    goto :next
)
if "%~1"=="-Wno-error=unknown-argument" goto :next
if "%~1"=="-Wno-error=unknown-warning-option" goto :next
if "%~1"=="-Wno-error=unused-macros" goto :next
if "%~1"=="-Wno-unused-macros" goto :next
if "%~1"=="-Wno-error=reserved-identifier" goto :next
if "%~1"=="-Wno-error=missing-prototypes" goto :next
if "%~1"=="-Wno-error=strict-prototypes" goto :next
if "%~1"=="-Wno-error=unused-parameter" goto :next
if "%~1"=="-Wno-error=missing-noreturn" goto :next
if "%~1"=="-Wno-error=sign-conversion" goto :next
if "%~1"=="-Wno-error=missing-variable-declarations" goto :next
if "%~1"=="-Wno-error=nonportable-system-include-path" goto :next
if "%~1"=="-Wno-error=language-extension-token" goto :next
if "%~1"=="-Wno-error=implicit-int-conversion" goto :next
if "%~1"=="-Wno-error=pointer-integer-compare" goto :next
if "%~1"=="-Wno-error=implicit" goto :next
if "%~1"=="-Wno-error=incompatible-pointer-types" goto :next
if "%~1"=="-Qunused-arguments" goto :next
if "%~1"=="-ferror-limit=0" goto :next
if "%~1"=="-fmessage-length=0" goto :next
if "%~1"=="-fno-stack-protector" goto :next
if "%~1"=="-O2" (
    REM Convert -O2 to /O2
    set "ARGS=!ARGS! /O2"
    goto :next
)
if "%~1"=="-g" (
    REM Convert -g to /Zi
    set "ARGS=!ARGS! /Zi"
    goto :next
)
if "%~1"=="-c" (
    REM Convert -c to /c
    set "ARGS=!ARGS! /c"
    goto :next
)
if "%~1"=="-o" (
    REM Handle -o flag (next arg is output file)
    set "ARGS=!ARGS! /Fo%~2"
    shift
    goto :next
)
if "%~1"=="-I" (
    REM Handle -I flag (next arg is include path)
    set "ARGS=!ARGS! /I%~2"
    shift
    goto :next
)
if "%~1"=="-D" (
    REM Handle -D flag (next arg is define)
    set "ARGS=!ARGS! /D%~2"
    shift
    goto :next
)
if "%~1"=="-L" (
    REM Skip -L flags (library paths handled differently in MSVC)
    shift
    goto :next
)
if "%~1"=="-l" (
    REM Skip -l flags (library names handled differently in MSVC)
    shift
    goto :next
)
if "%~1"=="-shared" (
    REM Convert -shared to /LD
    set "ARGS=!ARGS! /LD"
    goto :next
)
if "%~1"=="-fPIC" (
    REM Skip -fPIC (not needed for MSVC)
    goto :next
)

REM Check if it's a file (contains .c or .cpp extension)
echo %~1 | findstr "\.c\|\.cpp\|\.cc\|\.cxx" >nul
if %errorlevel% equ 0 (
    REM It's a source file, add it as-is
    set "ARGS=!ARGS! %~1"
    goto :next
)

REM For any other arguments, pass them through but convert - to /
echo %~1 | findstr "^-" >nul
if %errorlevel% equ 0 (
    REM Convert leading - to /
    for /f "tokens=1,* delims=-" %%a in ("%~1") do (
        set "ARGS=!ARGS! /%%b"
    )
) else (
    REM No leading -, pass as-is
    set "ARGS=!ARGS! %~1"
)

:next
shift
goto :parse_args

:execute
REM Execute cl.exe with converted arguments
REM Uncomment the next line for debugging
echo cl.exe !ARGS!
cl.exe !ARGS!

endlocal
