@echo off
REM Shim to call our robust PowerShell wrapper for cl.exe
REM This allows Go's CGO to use PowerShell for argument handling without parsing issues
powershell -ExecutionPolicy Bypass -File "%~dp0cl_wrapper_robust.ps1" %*
exit /b %ERRORLEVEL%
