@echo off
setlocal

set "DUCKTERM_INSTALLER_URL=https://raw.githubusercontent.com/ducksee/duckterm-hookd-releases/main/install.ps1"
set "DUCKTERM_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%DUCKTERM_POWERSHELL%" (
  echo [hookd] Windows PowerShell 5.1 was not found. 1>&2
  exit /b 1
)

"%DUCKTERM_POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; Invoke-RestMethod -UseBasicParsing -Uri '%DUCKTERM_INSTALLER_URL%' | Invoke-Expression"
exit /b %ERRORLEVEL%
