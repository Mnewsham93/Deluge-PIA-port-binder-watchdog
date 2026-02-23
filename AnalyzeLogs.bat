@echo off
:: 1. Check for Administrator Privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting Administrative Privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: 2. Shift directory to the script's location
cd /d "%~dp0"

:: 3. Run the PowerShell Dashboard
powershell -NoProfile -ExecutionPolicy Bypass -File "AnalyzeLogs.ps1"
