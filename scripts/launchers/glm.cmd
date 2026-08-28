@echo off
setlocal

where powershell.exe >nul 2>&1
if errorlevel 1 (
  >&2 echo glm: Windows PowerShell was not found on PATH.
  exit /b 127
)

if not exist "%~dp0glm.ps1" (
  >&2 echo glm: companion launcher "%~dp0glm.ps1" was not found.
  exit /b 2
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0glm.ps1" %*
set "glm_exit=%ERRORLEVEL%"
endlocal & exit /b %glm_exit%
