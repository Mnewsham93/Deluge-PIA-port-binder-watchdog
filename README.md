# Deluge & PIA Port Binder Watchdog

A Windows script designed to monitor Deluge and the Private Internet Access (PIA) VPN. This watchdog ensures Deluge is bound to the correct incoming/outgoing network interfaces and forwarded ports, while proactively mitigating `libtorrent` memory allocation problems on Windows.

## Features
* **Strict Interface Binding:** Continuously monitors the VPN adapter (`wgpia0`) and ensures Deluge only communicates through the active VPN IP and forwarded port.
* **Leak Protection:** Automatically halts and restarts the Deluge daemon if the VPN connection drops or the port changes.
* **Memory Management (48h Cycle):** Combats Windows `libtorrent` memory leaks by safely tracking uptime and restarting `deluged.exe` every 48 hours.
* **Comprehensive Logging:** Maintains a 100MB rolling log of heartbeats, VPN resyncs, and maintenance cycles.
* **Log Analyzer Utility:** Includes a PowerShell script to parse logs and generate a 30-day rolling health summary of your torrenting environment.

## Included Files
* `deluge_watchdog.bat` - The core monitoring script.
* `AnalyzeLogs.ps1` - PowerShell script to parse the watchdog logs.
* `AnalyzeLogs.bat` - Simple batch runner to execute the analyzer while bypassing execution policies.

## Configuration & Setup

### 1. Script Variables
Before running the watchdog, open `deluge_watchdog.bat` and verify the paths in the `:: 4. CONFIG` section match your local environment:
* `REAL_USER_PATH`: Your Windows user directory.
* `DEL_DIR`: The installation directory for Deluge.
* `PIA_CTL`: The path to `piactl.exe`.
* `D_PASS`: Add your local Deluge daemon password here.

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
Once the scheduled task is running, the watchdog operates silently in the background. To check the health of your setup, simply double-click `AnalyzeLogs.bat`. It will output a clean dashboard showing your Deluge uptime, time until the next 48h memory wipe, and a count of any crashes or VPN resyncs over the last 30 days.
