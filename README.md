# Deluge & PIA Port Binder Watchdog

A Windows script designed to monitor Deluge and the Private Internet Access (PIA) VPN. This watchdog ensures Deluge is bound to the correct incoming/outgoing network interfaces and forwarded ports, while proactively mitigating `libtorrent` memory allocation problems on Windows.

WARNING: This script requires Windows Smart App Control (SAC) to be disabled. Without it being disabled Windows will block Deluged.exe from running after a day or two. 

## Features
* **Full-Bind Interface Locking:** Automatically synchronizes both the `listen_interface` (incoming) and `outgoing_interface` (outgoing/leak protection) to the active VPN IP.
* **Traffic-Aware Failsafe:** Monitors active peer connections. If the daemon is running but reports **0 total peers** for more than 10 minutes, the script triggers a re-bind to resolve "Ghost Ports" or VPN API hangs.
* **Leak Protection:** Force-disables UPnP/NAT-PMP and automatically halts the Deluge daemon if the VPN connection drops or the IP subnet changes.
* **Memory Management (48h Cycle):** Combats Windows `libtorrent` memory leaks by safely tracking uptime and restarting `deluged.exe` every 48 hours.
* **Comprehensive Logging:** Maintains a 100MB rolling log of heartbeats, VPN resyncs, connection health events, and maintenance cycles.
* **Log Analyzer Utility:** Includes a PowerShell script to parse logs and generate a 30-day rolling health summary of your torrenting environment.

## Included Files
* `deluge_watchdog.bat` - The core monitoring script.
* `AnalyzeLogs.ps1` - PowerShell script to parse the watchdog logs.
* `AnalyzeLogs.bat` - Simple batch runner to execute the analyzer while bypassing execution policies.

## Configuration & Setup

### 1. Script Variables
Before running the watchdog, open `deluge_watchdog.bat` and verify the paths in the `:: 4. CONFIG` section match your local environment:
* `REAL_USER_PATH`: Your Windows user directory (e.g., C:\Users\Michael).
* `DEL_DIR`: The installation directory for Deluge.
* `PIA_CTL`: The path to `piactl.exe`.
* `D_PASS`: Add your local Deluge daemon password (found in your `auth` file).

### 2. Windows Task Scheduler (Recommended)
To ensure the watchdog runs continuously in the background, set it up via Windows Task Scheduler using a dedicated local admin account:

**General Tab:**
* Run with highest privileges.
* Configure for Windows 10/11.

**Triggers Tab (Create Two Triggers):**
1. At log on (Any user).
2. Daily at 12:00 PM -> Repeat task every 15 minutes for a duration of: Indefinitely.

**Actions Tab:**
* Action: Start a program.
* Program/script: Path to `deluge_watchdog.bat`.

**Settings Tab:**
* Check: "If the task fails, restart every 1 minute" (Attempt 3 times).
* Check: "If the running task does not end when requested, force it to stop."
* Ensure no conditional checkboxes (like "Start only if on AC power") are active.

## Usage
Once the scheduled task is running, the watchdog operates silently in the background. To check the health of your setup, simply double-click `AnalyzeLogs.bat`. It will output a clean dashboard showing your Deluge uptime, time until the next 48h memory wipe, and a count of any crashes, health-checks, or VPN resyncs over the last 30 days.
