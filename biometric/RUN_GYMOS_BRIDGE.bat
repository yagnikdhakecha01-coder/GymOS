@echo off
cd /d "%~dp0"
title GymOS Biometric Sync Bridge
color 0A

echo ====================================================================
echo                   GYMOS BIOMETRIC SYNC BRIDGE
echo           [Offline-First Reception PC Attendance Service]
echo ====================================================================
echo.

where node >nul 2>nul
if %errorlevel% neq 0 goto :try_python

echo [RUNNING VIA NODE.JS]
findstr /i "PASTE_YOUR_GYM_DEVICE_SECRET_HERE" gymos_bridge_config.json >nul 2>nul
if %errorlevel% equ 0 (
    node setup_wizard.js
)

echo Starting GymOS Biometric Bridge...
echo.
node gymos_biometric_bridge.js
goto :end

:try_python
echo Node.js not detected. Checking Python...
python --version >nul 2>nul
if %errorlevel% neq 0 goto :no_runtime

echo [RUNNING VIA PYTHON]
pip show requests >nul 2>nul
if %errorlevel% neq 0 (
    echo Installing requests package...
    pip install requests
)
python gymos_biometric_bridge.py
goto :end

:no_runtime
color 0C
echo.
echo ====================================================================
echo [ERROR] Neither Node.js nor Python was found on this PC!
echo Please install Node.js LTS from: https://nodejs.org/
echo ====================================================================
echo.

:end
echo.
echo Bridge process stopped.
pause
