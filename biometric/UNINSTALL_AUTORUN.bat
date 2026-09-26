@echo off
cd /d "%~dp0"
title Uninstall GymOS Biometric Auto-Start
color 0C

echo ====================================================================
echo              UNINSTALL GYMOS BIOMETRIC BACKGROUND SERVICE
echo ====================================================================
echo.

echo [1/3] Stopping running processes...
powershell -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*gymos_biometric_bridge*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"

echo [2/3] Removing from Windows Startup Registry...
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "GymOSBiometricBridge" /f >nul 2>nul

echo [3/3] Removing from Task Scheduler...
schtasks /delete /tn "GymOSBiometricBridge" /f >nul 2>nul

echo.
echo ====================================================================
echo GymOS Bridge has been completely removed from Auto-Start!
echo (Your local database and config files were kept safe).
echo ====================================================================
echo.
pause
