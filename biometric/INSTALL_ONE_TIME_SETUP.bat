@echo off
cd /d "%~dp0"
title GymOS Biometric Sync - 1-Time Setup Wizard
color 0A

echo ====================================================================
echo             GYMOS BIOMETRIC SYNC - 1-TIME AUTO INSTALLER
echo             [Compatible with Windows 7, 8, 10, and 11]
echo ====================================================================
echo.

:: 1. Check if Node.js is installed
where node >nul 2>nul
if %errorlevel% equ 0 goto :node_ok

color 0C
echo [ERROR] Node.js is not installed on this PC!
echo Node.js is required to run the bridge on Windows 7-11.
echo.
echo Please download and install Node.js LTS from:
echo https://nodejs.org/
echo.
pause
exit /b 1

:node_ok
:: 2. Run Interactive Configuration Wizard
echo Starting Interactive Setup Wizard...
node setup_wizard.js
if %errorlevel% neq 0 goto :wizard_failed

echo.
echo [1/3] Terminating any old bridge processes...
powershell -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*gymos_biometric_bridge*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>nul

echo [2/3] Registering Silent Background Auto-Start [Windows 7/8/10/11]...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "GymOSBiometricBridge" /t REG_SZ /d "wscript.exe \"%~dp0silent_runner.vbs\"" /f >nul
schtasks /create /tn "GymOSBiometricBridge" /tr "wscript.exe \"%~dp0silent_runner.vbs\"" /sc onlogon /f >nul 2>nul

echo [3/3] Starting Silent Background Service...
wscript.exe "%~dp0silent_runner.vbs"

timeout /t 2 >nul

color 0A
echo.
echo ====================================================================
echo        SUCCESS: GYMOS BIOMETRIC BRIDGE INSTALLED SUCCESSFULLY!
echo ====================================================================
echo.
echo 1. Background Service SILENT MODE me start ho chuki hai.
echo    [Koi bhi black CMD window open rakhne ki bilkul zaroorat nahi hai!]
echo.
echo 2. PC restart ya band hone par yeh AUTOMATICALLY background me chalega.
echo.
echo 3. Status check karne ke liye: 'CHECK_STATUS.bat' par click karein.
echo 4. Service stop karne ke liye: 'STOP_BRIDGE.bat' par click karein.
echo.
echo Setup Complete! Aap yeh window ab close kar sakte hain.
echo ====================================================================
echo.
pause
exit /b 0

:wizard_failed
color 0C
echo.
echo [ERROR] Setup wizard was cancelled or failed.
echo Please run 'INSTALL_ONE_TIME_SETUP.bat' again when ready.
echo.
pause
exit /b 1
