@echo off
REM MSVC wrapper script to filter out GCC-style flags that Go passes

REM Execute cl.exe with all arguments, filtering out problematic GCC flags
REM This is a simplified version that just removes known problematic flags

set "ARGS="
:parse_args
if "%~1"=="" goto :execute

REM Skip GCC-style flags that MSVC doesn't understand
if "%~1"=="-Werror" goto :skip
if "%~1"=="-Wno-error" goto :skip
if "%~1"=="-Wno-error=unknown-argument" goto :skip
if "%~1"=="-Wno-error=unknown-warning-option" goto :skip
if "%~1"=="-Wno-error=unused-macros" goto :skip
if "%~1"=="-Wno-unused-macros" goto :skip
if "%~1"=="-Wno-error=reserved-identifier" goto :skip
if "%~1"=="-Wno-error=missing-prototypes" goto :skip
if "%~1"=="-Wno-error=strict-prototypes" goto :skip
if "%~1"=="-Wno-error=unused-parameter" goto :skip
if "%~1"=="-Wno-error=missing-noreturn" goto :skip
if "%~1"=="-Wno-error=sign-conversion" goto :skip
if "%~1"=="-Wno-error=missing-variable-declarations" goto :skip
if "%~1"=="-Wno-error=nonportable-system-include-path" goto :skip
if "%~1"=="-Wno-error=language-extension-token" goto :skip
if "%~1"=="-Wno-error=implicit-int-conversion" goto :skip
if "%~1"=="-Wno-error=pointer-integer-compare" goto :skip
if "%~1"=="-Wno-error=implicit" goto :skip
if "%~1"=="-Wno-error=incompatible-pointer-types" goto :skip
if "%~1"=="-Qunused-arguments" goto :skip
if "%~1"=="-ferror-limit=0" goto :skip
if "%~1"=="-fmessage-length=0" goto :skip
if "%~1"=="-fno-stack-protector" goto :skip
if "%~1"=="--param" goto :skip_two

REM Add valid argument
set "ARGS=%ARGS% %~1"
goto :next

:skip_two
shift
goto :next

:skip
goto :next

:next
shift
goto :parse_args

:execute
REM Execute cl.exe with filtered arguments
cl.exe %ARGS%
