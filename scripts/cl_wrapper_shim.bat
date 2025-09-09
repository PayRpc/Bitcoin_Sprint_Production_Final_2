@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0cl_wrapper.ps1" %*
exit /b %errorlevel%
