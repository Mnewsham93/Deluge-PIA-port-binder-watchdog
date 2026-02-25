# Deluge & PIA Port Binder Watchdog (v1.2.3)

A robust Windows script designed to monitor Deluge and the Private Internet Access (PIA) VPN. This watchdog ensures Deluge is bound to the correct network interfaces and forwarded ports while proactively mitigating `libtorrent` memory issues, VPN "ghost ports", and headless zombie processes on Windows.

> **WARNING:** This script requires Windows Smart App Control (SAC) to be disabled. Without it disabled, Windows may block `deluged.exe` from executing after 24-48 hours.

## Features
* **Full-Bind Interface Locking:** Automatically synchronizes both the `listen_interface` (incoming) and `outgoing_interface` (leak protection) to the active VPN IP and dynamic Port.
* **Proactive Sledgehammer Cycle:** Native integration with `piactl` to perform a 24-hour maintenance cycle, forcing a fresh VPN tunnel and new port assignment daily to prevent stale connections.
* **Force-Rebind Architecture (v1.2.3):** Detects zombified daemon threads after network drops and actively double-taps the `deluged.exe` process to guarantee clean IP bindings on headless setups.
* **Stopwatch State Tracking:** Bypasses Windows Session Isolation and "Access Denied" errors by maintaining an internal uptime counter in a local state file (`watchdog_uptime.txt`).
* **Log Analyzer Utility:** Includes a PowerShell dashboard to parse logs, displaying real-time uptime, Sledgehammer countdowns, combined IP/Port data, and a tail of recent events.

## Included Files
* `deluge_watchdog.bat` - The core monitoring script.
* `AnalyzeLogs.ps1` - PowerShell script to parse logs and display the health dashboard.
* `AnalyzeLogs.bat` - Simple batch runner that auto-elevates to Administrator to run the analyzer.

## Configuration & Setup

### 1. Script Variables
Open `deluge_watchdog.bat` and verify the paths in the `:: 4. CONFIG` section:
* `REAL_USER_PATH`: Your Windows user directory (e.g., `C:\Users\Michael`).
* `DEL_DIR`: The installation directory for Deluge.
* `PIA_CTL`: The path to `piactl.exe`.
* `D_PASS`: Your local Deluge daemon password.

### 2. Windows Task Scheduler (Recommended)
Set up via Task Scheduler with "Highest Privileges" to ensure continuous background operation:
1. **Trigger:** At log on and repeat every 15 minutes.
2. **Action:** Start a program -> Path to `deluge_watchdog.bat`.
