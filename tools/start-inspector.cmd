@echo off
if "%~1"=="" (
  echo Verwendung: start-inspector.cmd "Unterrichtseinheit.schului"
  exit /b 1
)
start "" "%~dp0schului.exe" --inspector --lesson-file "%~f1"
