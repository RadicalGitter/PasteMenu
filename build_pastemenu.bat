@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "SRC=%SCRIPT_DIR%PasteMenu.ahk"
set "DIST_DIR=%SCRIPT_DIR%dist"
set "BUILD_DIR=%SCRIPT_DIR%build"
set "BACKUP_DIR=%BUILD_DIR%\backups"
set "LOG_DIR=%BUILD_DIR%\logs"
set "OUT=%DIST_DIR%\PasteMenu.exe"
set "AHK2EXE="
set "BASEEXE="

if not exist "%SRC%" (
  echo Source script not found:
  echo   %SRC%
  exit /b 1
)

if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

set "STAMP="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do (
  if not defined STAMP set "STAMP=%%T"
)

if not defined STAMP (
  echo Failed to generate build timestamp.
  exit /b 1
)

set "LOG=%LOG_DIR%\build_!STAMP!.log"
> "%LOG%" echo PasteMenu build !STAMP!
>> "%LOG%" echo Source: %SRC%
>> "%LOG%" echo Output: %OUT%
>> "%LOG%" echo.

for %%P in (
  "%ProgramFiles%\AutoHotkey\Ahk2Exe.exe"
  "%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe"
  "%ProgramFiles%\AutoHotkey\v2\Compiler\Ahk2Exe.exe"
  "%LocalAppData%\Programs\AutoHotkey\Compiler\Ahk2Exe.exe"
  "%LocalAppData%\AutoHotkey\Compiler\Ahk2Exe.exe"
) do (
  if exist "%%~P" if not defined AHK2EXE set "AHK2EXE=%%~P"
)

if not defined AHK2EXE (
  where Ahk2Exe.exe >nul 2>nul
  if not errorlevel 1 (
    for /f "delims=" %%I in ('where Ahk2Exe.exe') do (
      if not defined AHK2EXE set "AHK2EXE=%%~I"
    )
  )
)

if not defined AHK2EXE (
  echo Ahk2Exe compiler not found.
  echo Install AutoHotkey compiler, then re-run this script.
  echo.
  echo Suggested command:
  echo   "%ProgramFiles%\AutoHotkey\UX\AutoHotkeyUX.exe" "%ProgramFiles%\AutoHotkey\UX\install-ahk2exe.ahk"
  >> "%LOG%" echo Ahk2Exe compiler not found.
  exit /b 1
)

for %%B in (
  "%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
  "%ProgramFiles%\AutoHotkey\v2\AutoHotkey.exe"
  "%LocalAppData%\Programs\AutoHotkey\v2\AutoHotkey64.exe"
  "%LocalAppData%\Programs\AutoHotkey\v2\AutoHotkey.exe"
) do (
  if exist "%%~B" if not defined BASEEXE set "BASEEXE=%%~B"
)

echo Using Ahk2Exe:
echo   %AHK2EXE%
>> "%LOG%" echo Ahk2Exe: %AHK2EXE%
if defined BASEEXE (
  echo Using base:
  echo   %BASEEXE%
  >> "%LOG%" echo Base: %BASEEXE%
)
echo.
echo Building:
echo   %SRC%
echo -^> %OUT%
echo Log:
echo   %LOG%
echo.

if exist "%OUT%" (
  set "BACKUP=%BACKUP_DIR%\PasteMenu_backup_!STAMP!.exe"
  copy /y "%OUT%" "!BACKUP!" >nul
  if errorlevel 1 (
    echo Failed to create backup:
    echo   !BACKUP!
    >> "%LOG%" echo Failed to create backup: !BACKUP!
    exit /b 1
  )
  echo Backup created:
  echo   !BACKUP!
  echo.
  >> "%LOG%" echo Backup: !BACKUP!
)

>> "%LOG%" echo.
>> "%LOG%" echo Compiler output:
if defined BASEEXE (
  "%AHK2EXE%" /in "%SRC%" /out "%OUT%" /base "%BASEEXE%" /silent >> "%LOG%" 2>&1
) else (
  "%AHK2EXE%" /in "%SRC%" /out "%OUT%" /silent >> "%LOG%" 2>&1
)
if errorlevel 1 (
  echo Build failed. See log:
  echo   %LOG%
  exit /b 1
)

if exist "%OUT%" (
  echo Build succeeded:
  echo   %OUT%
  echo Log:
  echo   %LOG%
  exit /b 0
)

echo Build command finished, but output file was not found:
echo   %OUT%
echo See log:
echo   %LOG%
exit /b 1
