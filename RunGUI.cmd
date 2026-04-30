@echo off
rem Launches the AuthorityGate HealthCheck GUI. If the script exits with a non-zero
rem code (i.e., crashed before the form opened), pause so the operator can
rem read the error before the cmd window closes.
setlocal
set SCRIPT=%~dp0Start-HorizonHealthCheckGUI.ps1
where pwsh.exe >nul 2>&1 && (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
) || (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
)
if errorlevel 1 (
    echo.
    echo ============================================================
    echo  HealthCheck exited with error code %errorlevel%.
    echo  See last-error.log next to this script for full details.
    echo ============================================================
    pause
)
endlocal
