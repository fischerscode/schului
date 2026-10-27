@echo off
setlocal
if "%~1"=="" (
  start "" /D "%~dp0" "%~dp0schului.exe" --lesson-file "%~dp0unterricht.schului"
) else (
  start "" /D "%~dp0" "%~dp0schului.exe" --lesson-file "%~f1"
)
