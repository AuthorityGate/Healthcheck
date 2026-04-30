@echo off
rem One-click prerequisite install for AuthorityGate HealthCheck.
rem Default scope: CurrentUser  (no Administrator required).
rem
rem To install for ALL users (machine-wide), open an elevated CMD and run:
rem    Install-Prerequisites.cmd /allusers
setlocal
set ARGS=
if /i "%~1"=="/allusers" set ARGS=-AllUsers
where pwsh.exe >nul 2>&1 && (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Tools\Install-Prerequisites.ps1" %ARGS%
) || (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Tools\Install-Prerequisites.ps1" %ARGS%
)
echo.
pause
