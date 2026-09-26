@echo off
cd /d "%~dp0"
title GymOS Bridge Status Monitor
color 0B

echo ====================================================================
echo                   GYMOS BRIDGE - LIVE STATUS
echo ====================================================================
echo.

:: Check if process is running
tasklist /fi "IMAGENAME eq node.exe" | findstr /i "node.exe" >nul
if %errorlevel% equ 0 (
    color 0A
    echo [STATUS]: RUNNING in Background (Silent Service Active)
) else (
    color 0C
    echo [STATUS]: NOT RUNNING
    echo Run 'INSTALL_ONE_TIME_SETUP.bat' to start the service.
)

echo.
echo --------------------------------------------------------------------
echo Recent Log Entries (from gymos_bridge.log):
echo --------------------------------------------------------------------
if exist gymos_bridge.log (
    powershell -Command "Get-Content -Path '.\gymos_bridge.log' -Tail 15"
) else (
    echo No log file generated yet.
)

echo.
echo ====================================================================
pause
