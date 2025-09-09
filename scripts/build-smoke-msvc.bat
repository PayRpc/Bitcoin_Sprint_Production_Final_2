@echo off
"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" -arch=amd64
set CC=cl
set CXX=cl
set CGO_ENABLED=1
cd /d "c:\Projects 2\Bitcoin_Sprint_Production_3"
go build -v .\cmd\smoke
if %ERRORLEVEL% neq 0 pause
