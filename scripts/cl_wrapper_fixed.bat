@echo off
setlocal enabledelayedexpansion

rem Comprehensive wrapper to filter GCC flags and convert to MSVC format
echo [cl_wrapper] Called with arguments: %* >> C:\temp\cl_wrapper_log.txt
echo [cl_wrapper] =================== >> C:\temp\cl_wrapper_log.txt

rem If GCC dry-run requested, exit successfully (no compile)
if "%~1"=="-###" (
    >> C:\temp\cl_wrapper_log.txt echo [cl_wrapper] GCC dry-run (-###) detected, exiting 0
    exit /b 0
)

rem Special case: if CGO is just checking compiler capabilities, exit successfully
if "%~1"=="-dM" if "%~2"=="-E" if "%~3"=="-" (
    echo [cl_wrapper] CGO compiler capability check, exiting successfully >> C:\temp\cl_wrapper_log.txt
    exit /b 0
)

set "MSVC_ARGS="
set "skip_next=0"

:parse_args
if "%~1"=="" goto end_parse

rem Check if we need to skip this argument (it was a value for a previous flag)
if "!skip_next!"=="1" (
    set "skip_next=0"
    shift
    goto parse_args
)

rem Handle flags that take values (need to skip the next argument)
if "%~1"=="-fmessage-length" (
    echo [cl_wrapper] Filtering out GCC flag: %~1 %~2
    set "skip_next=1"
    shift
    shift
    goto parse_args
)
if "%~1"=="-frandom-seed" (
    echo [cl_wrapper] Filtering out GCC flag: %~1 %~2
    set "skip_next=1"
    shift
    shift
    goto parse_args
)

rem Handle -### (verbose GCC style dry-run) -> ignore
if "%~1"=="-###" (
    echo [cl_wrapper] Ignoring GCC dry-run flag: %~1
    shift
    goto parse_args
)

rem Handle -x language (e.g., -x c)
if "%~1"=="-x" (
    echo [cl_wrapper] Handling -x flag, skipping language token: %~2
    shift
    shift
    goto parse_args
)

rem Handle '-' which means read from stdin: save to temp file and replace with filename
if "%~1"=="-" (
    set "tmpfile=%TEMP%\cgo_stdin_%RANDOM%.c"
    echo [cl_wrapper] Reading stdin to temp file: !tmpfile! >> C:\temp\cl_wrapper_log.txt
    more >"!tmpfile!"
    set "MSVC_ARGS=!MSVC_ARGS! "!tmpfile!""
    shift
    goto parse_args
)

rem Check for -Wl, flags (linker flags)
echo %~1 | findstr /b /c:"-Wl," >nul
if !errorlevel! equ 0 (
    echo [cl_wrapper] Filtering out GCC linker flag: %~1
    shift
    goto parse_args
)

rem Filter out CGO preprocessor flags
if "%~1"=="-dM" (
    echo [cl_wrapper] Filtering out CGO preprocessor flag: %~1
    shift
    goto parse_args
)
if "%~1"=="-E" (
    echo [cl_wrapper] Filtering out CGO preprocessor flag: %~1
    shift
    goto parse_args
)

rem Filter out specific GCC flags that don't take values
if "%~1"=="-m64" (
    echo [cl_wrapper] Filtering out GCC flag: %~1
    shift
    goto parse_args
)
if "%~1"=="-mthreads" (
    echo [cl_wrapper] Filtering out GCC flag: %~1
    shift
    goto parse_args
)
if "%~1"=="-Wall" (
    echo [cl_wrapper] Filtering out GCC flag: %~1
    shift
    goto parse_args
)
if "%~1"=="-Werror" (
    echo [cl_wrapper] Filtering out GCC flag: %~1
    shift
    goto parse_args
)
if "%~1"=="-fPIC" (
    echo [cl_wrapper] Filtering out GCC flag: %~1
    shift
    goto parse_args
)
if "%~1"=="-fPIE" (
    echo [cl_wrapper] Filtering out GCC flag: %~1
    shift
    goto parse_args
)
if "%~1"=="-fno-stack-protector" (
    echo [cl_wrapper] Filtering out GCC flag: %~1
    shift
    goto parse_args
)
if "%~1"=="-Wdeclaration-after-statement" (
    echo [cl_wrapper] Filtering out GCC flag: %~1
    shift
    goto parse_args
)

rem Convert GCC flags to MSVC equivalents
if "%~1"=="-I" (
    echo [cl_wrapper] Converting -I flag to MSVC format
    set "path_part=%~2"
    rem If the path ends with a backslash, append a dot to avoid escaping the closing quote
    set "last_char=!path_part:~-1!"
    if "!last_char!"==\ (
        set "path_part=!path_part!."
    )
    set "MSVC_ARGS=!MSVC_ARGS! /I"!path_part!""
    shift
    shift
    goto parse_args
)

rem Handle -I flags combined with path (like -I/path)
echo %~1 | findstr /b /c:"-I" >nul
if !errorlevel! equ 0 (
    echo [cl_wrapper] Converting -I flag to MSVC format
    set "path_part=%~1"
    set "path_part=!path_part:~2!"
    rem If the path ends with a backslash, append a dot to avoid escaping the closing quote
    set "last_char=!path_part:~-1!"
    if "!last_char!"==\ (
        set "path_part=!path_part!."
    )
    set "MSVC_ARGS=!MSVC_ARGS! /I"!path_part!""
    shift
    goto parse_args
)

if "%~1"=="-o" (
    echo [cl_wrapper] Converting -o flag to MSVC format
    set "out_path=%~2"
    rem Append dot if path ends with backslash to keep quotes balanced
    set "last_char=!out_path:~-1!"
    if "!last_char!"==\ (
        set "out_path=!out_path!."
    )
    set "MSVC_ARGS=!MSVC_ARGS! /Fo"!out_path!""
    shift
    shift
    goto parse_args
)

if "%~1"=="-c" (
    echo [cl_wrapper] Converting -c flag to MSVC format
    set "MSVC_ARGS=!MSVC_ARGS! /c"
    shift
    goto parse_args
)

rem Pass through all other arguments (including source files and MSVC flags)
rem Don't skip empty arguments
if not "%~1"=="" (
    rem Safer check for spaces without invoking findstr to avoid "No search strings"
    set "arg=%~1"
    set "arg_no_spaces=!arg: =!"
    if not "!arg!"=="!arg_no_spaces!" (
        set "MSVC_ARGS=!MSVC_ARGS! "!arg!""
    ) else (
        set "MSVC_ARGS=!MSVC_ARGS! !arg!"
    )
)
shift
goto parse_args

:end_parse

rem Execute the MSVC compiler with the filtered and converted arguments
echo [cl_wrapper] Executing: "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe" !MSVC_ARGS!
"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe" !MSVC_ARGS!
exit /b %errorlevel%
