@echo off
setlocal enabledelayedexpansion
c:
cd \

:: 1. ADMIN CHECK
net session >nul 2>&1
if %errorLevel% neq 0 (echo [ERROR] ADMIN REQ & pause & exit /b)

:: 2. PATHS
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

:: 4. CONFIG
set "REAL_USER_PATH=C:\Users\"
set "DEL_DIR=C:\Program Files\Deluge"
set "PIA_CTL=C:\Program Files\Private Internet Access\piactl.exe"
set "ADAPTER=wgpia0"
set "D_CONF=%REAL_USER_PATH%\AppData\Roaming\deluge"
set "D_PID=%D_CONF%\deluged.pid"
set "D_USER=localclient"
set "D_PASS="
set "D_PORT=58846"

:: CHECK_INT: 5 seconds for rapid leak detection
:: H_INT: 60 cycles * 5s = 5 minutes per heartbeat log
set /a "CHECK_INT=5", "RETRY=15", "H_INT=60"
set /a "HB_TIMER=0"

:: RESTART LIMIT: 48 Hours (172800 seconds)
set /a "RESTART_LIMIT=172800"

call :LOG "[STARTUP] Watchdog active (ID: %MYPID%)"

:: 5. INITIAL VPN SYNC
:VPN_CHECK
set "NEW_IP="
for /f "tokens=3" %%a in ('netsh interface ipv4 show addresses "%ADAPTER%" 2^>nul ^| findstr /C:"IP Address"') do set "NEW_IP=%%a"
for /f "tokens=*" %%i in ('"%PIA_CTL%" get portforward 2^>nul') do set "RAW_PORT=%%i"

:: If VPN is down, wait here. Deluge cannot start without an IP to bind to.
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

:: ============================================
::                 MONITORING LOOP
:: ============================================
:MONITOR_LOOP
:: 1. INSTANCE HANDOFF
if exist "%LOCK_FILE%" (
    set /p L_CHECK=<"%LOCK_FILE%"
    if NOT "!L_CHECK: =!"=="%MYPID%" (
        call :LOG "[EXIT] Newer instance detected (!L_CHECK!). Closing %MYPID%."
        exit /b 0
    )
)

:: 2. PROCESS UPTIME CHECK (Stateless 48h Timer)
set "D_UPTIME=0"
for /f "usebackq" %%A in (`powershell -NoProfile -Command "try { [math]::Truncate(((Get-Date) - (Get-Process deluged -ErrorAction Stop | Select-Object -First 1).StartTime).TotalSeconds) } catch { 0 }"`) do set "D_UPTIME=%%A"

if !D_UPTIME! GEQ %RESTART_LIMIT% (
    call :LOG "[MAINTENANCE] Uptime !D_UPTIME!s exceeds 48h limit. Restarting..."
    call :RESTART_DELUGE
    timeout /t 15 >nul
    goto VPN_CHECK
)

:: 3. DAEMON CHECK (Ensures it is running AND bound)
tasklist /FI "IMAGENAME eq deluged.exe" 2>nul | find /I "deluged.exe" >nul
if errorlevel 1 (
    call :LOG "[WARNING] Daemon down. Starting with forced binding..."
    call :START_BOUND_DAEMON
    goto VPN_CHECK
)

:: 4. HEARTBEAT LOGGING
set /a HB_TIMER=HB_TIMER + 1
if !HB_TIMER! GEQ %H_INT% (
    if "!D_UPTIME!"=="" set "D_UPTIME=0"
    set /a "UP_HOURS=!D_UPTIME!/3600"
    call :LOG "[HEARTBEAT] Deluge Active: !UP_HOURS!h - Bound to: %OLD_IP%"
    set /a HB_TIMER=0
)

:: 5. NETWORK INTEGRITY CHECKS (Primary Function)
set "NEW_IP="
for /f "tokens=3" %%a in ('netsh interface ipv4 show addresses "%ADAPTER%" 2^>nul ^| findstr /C:"IP Address"') do set "NEW_IP=%%a"
for /f "tokens=*" %%i in ('"%PIA_CTL%" get portforward 2^>nul') do set "NEW_PORT=%%i"

if not "!NEW_IP!"=="!OLD_IP!" (
    call :LOG "[UPDATE] VPN IP Changed (!OLD_IP! -> !NEW_IP!). Re-Binding..."
    goto APPLY_UPDATE
)

call :VALIDATE_PORT "!NEW_PORT!"
if "!PORT_VALID!"=="1" (
    if not "!NEW_PORT!"=="!OLD_PORT!" (
        call :LOG "[UPDATE] Port Changed (!OLD_PORT! -> !NEW_PORT!). Re-Configuring..."
        goto APPLY_UPDATE
    )
)

:: 6. RESPONSIVE WAIT
set /a W_SEC=0
:WAIT_LOOP
if exist "%LOCK_FILE%" (
    set /p L_CHECK=<"%LOCK_FILE%"
    if NOT "!L_CHECK: =!"=="%MYPID%" (
        call :LOG "[EXIT] Newer instance detected (!L_CHECK!). Closing %MYPID%."
        timeout /t 2 >nul
        exit /b 0
    )
)

title 48h Timer: !D_UPTIME!/%RESTART_LIMIT%s ^| ID: %MYPID%
timeout /t 1 /nobreak >nul
set /a W_SEC=W_SEC + 1
if !W_SEC! LSS %CHECK_INT% goto WAIT_LOOP
goto MONITOR_LOOP

:: ============================================
::                SUBROUTINES
:: ============================================

:START_BOUND_DAEMON
:: v5.5 Full-Bind Enforcer:
:: -i: Binds listen_interface (Incoming UDP/TCP)
if exist "%D_PID%" del /f /q "%D_PID%" 2>nul
start "" "%DEL_DIR%\deluged.exe" -c "%D_CONF%" -i %NEW_IP%

:: Wait for daemon to initialize
timeout /t 5 >nul

:: Force Config via Console: 
:: 1. Outgoing Interface (Back-door leak protection)
:: 2. Port Allocation
:: 3. Disable UPnP/NAT-PMP (Tunnel bypass prevention)
call :LOG "[CONFIG] Enforcing Full Bind: %NEW_IP%:%RAW_PORT%"
"%DEL_DIR%\deluge-console.exe" --config "%D_CONF%" "connect 127.0.0.1:%D_PORT% %D_USER% %D_PASS%; config -s outgoing_interface %NEW_IP%; config -s listen_ports (%RAW_PORT%,%RAW_PORT%); config -s upnp False; config -s natpmp False; quit" >nul 2>&1
goto :EOF

:APPLY_UPDATE
taskkill /F /IM deluged.exe >nul 2>&1
if exist "%D_PID%" del /f /q "%D_PID%" 2>nul
timeout /t 2 >nul
set "OLD_IP=!NEW_IP!"
set "OLD_PORT=!NEW_PORT!"
set "RAW_PORT=!NEW_PORT!"
call :START_BOUND_DAEMON
timeout /t 10 >nul
goto VPN_CHECK

:RESTART_DELUGE
"%DEL_DIR%\deluge-console.exe" --config "%D_CONF%" "connect 127.0.0.1:%D_PORT% %D_USER% %D_PASS%; halt; quit" >nul 2>&1
timeout /t 45 >nul
taskkill /F /IM deluged.exe >nul 2>&1
call :START_BOUND_DAEMON
goto :EOF

:LOG
set "M=[%date% %time%] [ID:%MYPID%] %~1"
echo %M% >> "%LOG_FILE%"
for %%I in ("%LOG_FILE%") do (
    if %%~zI GTR 104857600 (
        pushd "%LOG_DIR%"
        if exist watchdog.log.9 del /f /q watchdog.log.9 2>nul
        if exist watchdog.log.8 ren watchdog.log.8 watchdog.log.9
        if exist watchdog.log.7 ren watchdog.log.7 watchdog.log.8
        if exist watchdog.log.6 ren watchdog.log.6 watchdog.log.7
        if exist watchdog.log.5 ren watchdog.log.5 watchdog.log.6
        if exist watchdog.log.4 ren watchdog.log.4 watchdog.log.5
        if exist watchdog.log.3 ren watchdog.log.3 watchdog.log.4
        if exist watchdog.log.2 ren watchdog.log.2 watchdog.log.3
        if exist watchdog.log.1 ren watchdog.log.1 watchdog.log.2
        if exist watchdog.log ren watchdog.log watchdog.log.1
        popd & echo [%date% %time%] [SYSTEM] Rotated. > "%LOG_FILE%"
    )
)
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
