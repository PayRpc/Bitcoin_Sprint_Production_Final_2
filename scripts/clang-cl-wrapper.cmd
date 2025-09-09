@echo off
rem Wrapper for clang-cl that appends flags to disable warnings-as-errors for cgo-generated code.
rem Find the real clang-cl.exe on PATH and invoke it with forwarded args plus our extra flags appended.
for %%I in ("%ProgramFiles%\LLVM\bin\clang-cl.exe" "C:\Program Files\LLVM\bin\clang-cl.exe" "C:\Program Files (x86)\LLVM\bin\clang-cl.exe") do (
  if exist %%~I set REAL_CLANG=%%~I
)
if not defined REAL_CLANG (
  for %%P in ("%PATH:;=" "%") do (
    if exist "%%~P\clang-cl.exe" set REAL_CLANG=%%~P\clang-cl.exe
  )
)
if not defined REAL_CLANG (
  echo ERROR: clang-cl.exe not found in common locations or PATH
  exit /b 2
)

rem Append suppressing flags so they appear after any -Werror injected by the Go toolchain.
set EXTRA_FLAGS=-Wno-error -Wno-error=reserved-identifier -Wno-error=unknown-argument -Wno-error=unknown-warning-option -Wno-error=unused-macros -Wno-unused-macros -Qunused-arguments
"%REAL_CLANG%" %* %EXTRA_FLAGS%
exit /b %ERRORLEVEL%
