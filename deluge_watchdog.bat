@echo off
setlocal enabledelayedexpansion
c:
cd \

:: 1. ADMIN CHECK
net session >nul 2>&1
if %errorLevel% neq 0 (echo [ERROR] ADMIN REQ & pause & exit /b)

:: 2. PATHS & LOGGING
set "LOG_DIR=C:\ProgramData\deluge"
set "LOCK_FILE=%LOG_DIR%\watchdog_pid.txt"
set "LOG_FILE=%LOG_DIR%\watchdog.log"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" 2>nul

:: 3. PID GENERATION
for /f "tokens=1-2 delims=: " %%a in ("%time%") do (
    set "H_RAW=%%a"
    set "M_RAW=%%b"
)
set "H_RAW=%H_RAW: =0%"
set "MYPID=%H_RAW%%M_RAW%-%RANDOM%"
echo %MYPID%> "%LOCK_FILE%"

:: 4. CONFIG - REDACTED FOR GITHUB
set "REAL_USER_PATH=C:\Users\YOUR_USERNAME"
set "DEL_DIR=C:\Program Files\Deluge"
set "PIA_CTL=C:\Program Files\Private Internet Access\piactl.exe"
set "ADAPTER=wgpia0"
set "D_CONF=%REAL_USER_PATH%\AppData\Roaming\deluge"
set "D_PID=%D_CONF%\deluged.pid"
set "D_USER=localclient"
set "D_PASS=YOUR_PASSWORD_HERE"
set "D_PORT=58846"
set "STATE_FILE=%D_CONF%\watchdog_uptime.txt"

:: TIMING CONFIG
set /a "CHECK_INT=5", "RETRY=15", "H_INT=60"
set /a "HB_TIMER=0"
set /a "MAINTENANCE_LIMIT=86400" 

call :LOG "[STARTUP] Watchdog v1.1.6 active (ID: %MYPID%)"

:: Initialize Uptime
set /a D_UPTIME=0
if exist "%STATE_FILE%" (
    for /f "usebackq delims=" %%A in ("%STATE_FILE%") do set /a D_UPTIME=%%A 2>nul
)

:VPN_CHECK
set "NEW_IP="
for /f "tokens=3" %%a in ('netsh interface ipv4 show addresses "%ADAPTER%" 2^>nul ^| findstr /C:"IP Address"') do set "NEW_IP=%%a"
for /f "tokens=*" %%i in ('"%PIA_CTL%" get portforward 2^>nul') do set "RAW_PORT=%%i"

if "%NEW_IP%"=="" (
    call :LOG "[ERROR] VPN Interface down. Waiting..."
    timeout /t %RETRY% >nul & goto VPN_CHECK
)

call :VALIDATE_PORT "%RAW_PORT%"
if "!PORT_VALID!"=="0" (
    call :LOG "[WARNING] Port [%RAW_PORT%] not ready. Waiting..."
    timeout /t 10 >nul & goto VPN_CHECK
)

set "OLD_PORT=%RAW_PORT%"
set "OLD_IP=%NEW_IP%"
call :LOG "[INIT] Monitoring: %OLD_IP%:%OLD_PORT%"

:MONITOR_LOOP
if exist "%LOCK_FILE%" (
    set /p L_CHECK=<"%LOCK_FILE%"
    if NOT "!L_CHECK: =!"=="%MYPID%" (exit /b 0)
)

if !D_UPTIME! GEQ %MAINTENANCE_LIMIT% (
    call :LOG "[MAINTENANCE] Uptime !D_UPTIME!s exceeds 24h limit. Initiating VPN Sledgehammer..."
    call :SLEDGEHAMMER
    goto VPN_CHECK
)

tasklist /FI "IMAGENAME eq deluged.exe" 2>nul | find /I "deluged.exe" >nul
if errorlevel 1 (
    call :LOG "[WARNING] Daemon down. Starting with forced binding..."
    call :START_BOUND_DAEMON
    goto VPN_CHECK
)

set /a HB_TIMER+=1
if !HB_TIMER! GEQ %H_INT% (
    set /a "UP_HOURS=!D_UPTIME!/3600"
    call :LOG "[HEARTBEAT] Deluge Active: !UP_HOURS!h - Bound to: %OLD_IP%"
    set /a HB_TIMER=0
)

set "NEW_IP="
for /f "tokens=3" %%a in ('netsh interface ipv4 show addresses "%ADAPTER%" 2^>nul ^| findstr /C:"IP Address"') do set "NEW_IP=%%a"
for /f "tokens=*" %%i in ('"%PIA_CTL%" get portforward 2^>nul') do set "NEW_PORT=%%i"

if not "!NEW_IP!"=="!OLD_IP!" (goto APPLY_UPDATE)
call :VALIDATE_PORT "!NEW_PORT!"
if "!PORT_VALID!"=="1" (
    if not "!NEW_PORT!"=="!OLD_PORT!" (goto APPLY_UPDATE)
)

set /a W_SEC=0
:WAIT_LOOP
timeout /t 1 /nobreak >nul
set /a W_SEC+=1
set /a D_UPTIME+=1
if !W_SEC! LSS %CHECK_INT% goto WAIT_LOOP
echo !D_UPTIME!> "%STATE_FILE%"
goto MONITOR_LOOP

:START_BOUND_DAEMON
if exist "%D_PID%" del /f /q "%D_PID%" 2>nul
start "" "%DEL_DIR%\deluged.exe" -c "%D_CONF%" -i %NEW_IP%
set /a D_UPTIME=0
echo 0 > "%STATE_FILE%"
timeout /t 5 >nul
"%DEL_DIR%\deluge-console.exe" --config "%D_CONF%" "connect 127.0.0.1:%D_PORT% %D_USER% %D_PASS%; config -s outgoing_interface %NEW_IP%; config -s listen_ports (%RAW_PORT%,%RAW_PORT%); config -s upnp False; config -s natpmp False; quit" >nul 2>&1
goto :EOF

:APPLY_UPDATE
taskkill /F /IM deluged.exe >nul 2>&1
set "OLD_IP=!NEW_IP!"
set "OLD_PORT=!NEW_PORT!"
set "RAW_PORT=!NEW_PORT!"
call :START_BOUND_DAEMON
goto VPN_CHECK

:SLEDGEHAMMER
"%DEL_DIR%\deluge-console.exe" --config "%D_CONF%" "connect 127.0.0.1:%D_PORT% %D_USER% %D_PASS%; halt; quit" >nul 2>&1
timeout /t 15 >nul
taskkill /F /IM deluged.exe >nul 2>&1
"%PIA_CTL%" disconnect
timeout /t 10 >nul
"%PIA_CTL%" connect
timeout /t 15 >nul
goto :EOF

:LOG
set "M=[%date% %time%] [ID:%MYPID%] %~1"
echo %M% >> "%LOG_FILE%"
goto :EOF

:VALIDATE_PORT
set "PORT_VALID=0"
set "V_PORT=%~1"
if not defined V_PORT goto :EOF
echo !V_PORT!| findstr /r "^[0-9][0-9]*$" >nul
if not errorlevel 1 (
    if !V_PORT! GEQ 1024 if !V_PORT! LEQ 65535 set "PORT_VALID=1"
)
goto :EOF
