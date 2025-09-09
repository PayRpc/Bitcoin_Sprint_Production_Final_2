@echo off
rem Simple clang-cl shim: prefer known LLVM install path, else use where.exe to find clang-cl.exe
set REAL="C:\Program Files\LLVM\bin\clang-cl.exe"
if not exist %REAL% (
  for /f "usebackq tokens=*" %%a in (`where clang-cl 2^>nul`) do (
    set REAL=%%a
    goto :FOUND
  )
)
:FOUND
if not exist %REAL% (
  echo ERROR: clang-cl.exe not found
  exit /b 2
)
set EXTRA=-Wno-error -Wno-error=reserved-identifier -Wno-error=unknown-argument -Wno-error=unknown-warning-option -Wno-error=unused-macros -Wno-unused-macros -Qunused-arguments
%REAL% %* %EXTRA%
exit /b %ERRORLEVEL%
