@echo off
setlocal EnableExtensions

set "PS1=%~dp0smoke_check.ps1"
if not exist "%PS1%" (
  echo [FAIL] Missing script: "%PS1%"
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
exit /b %ERRORLEVEL%
