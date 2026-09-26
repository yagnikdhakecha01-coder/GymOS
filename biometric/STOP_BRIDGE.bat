@echo off
cd /d "%~dp0"
title Stop GymOS Biometric Bridge
color 0E

echo ====================================================================
echo                   STOPPING GYMOS BIOMETRIC BRIDGE
echo ====================================================================
echo.

powershell -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*gymos_biometric_bridge*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host 'Stopped GymOS Bridge process ID:' $_.ProcessId }"

echo.
echo GymOS Bridge has been stopped.
echo To restart anytime, double-click 'INSTALL_ONE_TIME_SETUP.bat' or 'RUN_GYMOS_BRIDGE.bat'.
echo.
pause
