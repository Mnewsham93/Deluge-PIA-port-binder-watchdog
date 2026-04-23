# Deluge & PIA Port Binder Watchdog (v1.3)

A high-resilience Windows automation utility designed to manage the Deluge daemon and Private Internet Access (PIA) VPN. Built as a "batch-metal" alternative to Dockerized solutions (like Gluetun), this watchdog avoids WSL2 virtualization overhead and container "stale socket" failures by running natively on the host system. It ensures that your traffic is strictly bound to the active VPN interface and forwarded port, providing an autonomous, self-healing killswitch for long-term deployments.

> **CRITICAL REQUIREMENT:** Windows Smart App Control (SAC) must be disabled. If enabled, SAC may block `deluged.exe` from spawning after 24-48 hours of background operation.

## Key Features
* **Headless Storm Protection (v1.3):** Actively polls for the primary user's desktop session (`explorer.exe`). Prevents runaway Task Scheduler instances and cascading log errors when the PC reboots and stalls at the Windows login screen.
* **Interface Locking:** Force-binds both `listen_interface` and `outgoing_interface` to the dynamic VPN IP to natively prevent data leaks.
* **Outage Resilience:** Specifically engineered to detect physical internet drops. If the VPN interface disappears, the script initiates a "Force-Rebind" the moment connectivity returns, preventing "Dead-Tunnel" scenarios where the daemon process runs but is functionally disconnected.
* **Proactive Sledgehammer (24h):** Performs a daily graceful shutdown of Deluge followed by a full VPN tunnel reset via `piactl` to mitigate `libtorrent` memory drift and stale ports over long uptimes.
* **Zombie Mitigation:** Employs a "Double-Tap" process termination logic to ensure lingering headless threads are fully cleared before re-establishing network bindings.
* **Persistent Uptime Tracking:** Uses a local state file to track maintenance cycles, ensuring reliability across system restarts and task handoffs.

## Included Files
* `deluge_watchdog.bat` — The core watchdog automation script.
* `AnalyzeLogs.ps1` — A PowerShell-based dashboard to view real-time health, uptime, and IP/Port status.
* `AnalyzeLogs.bat` — An auto-elevating runner for the PowerShell dashboard.

## Configuration

### 1. Script Setup
Open `deluge_watchdog.bat` and update the `:: 4. CONFIG` section:
* `PRIMARY_USER`: Your Windows login name (e.g., `YourUsername`).
* `REAL_USER_PATH`: Your Windows user directory (e.g., `C:\Users\YourUsername`).
* `D_PASS`: Your Deluge localclient daemon password.
* `PIA_CTL`: Path to your `piactl.exe` (usually in `C:\Program Files\Private Internet Access\`).

### 2. Automation (Task Scheduler)
To ensure 24/7 coverage, configure a Windows Task:
1. **Trigger:** `At log on` (or startup) and `Repeat task every 15 minutes` indefinitely.
2. **General:** Enable `Run with highest privileges`.
3. **Settings:** Set "If the task is already running..." to `Do not start a new instance`.
4. **Action:** `Start a program` -> Point to `deluge_watchdog.bat`.

## Troubleshooting Outages & Reboots
* **Physical Drops:** If your physical internet goes out, the script will enter an error loop. Once the internet returns, it automatically detects the new VPN IP/Port and forcefully restarts the daemon. No manual intervention is required.
* **System Reboots:** If the PC restarts, the watchdog will silently sleep at the login screen. It will only begin attempting to sync the daemon and VPN once `PRIMARY_USER` physically logs into the desktop session.

## Version History
* **v1.3:** Added Headless Storm Protection via `explorer.exe` session gate; relocated instance handoff to prevent Task Scheduler cascades during prolonged VPN outages.
* **v1.2.4:** Added Outage Resilience; forced re-bind after network interface drops.
* **v1.2.3:** Introduced `FORCE_REBIND` flag; fixed zombie process edge cases.
* **v1.2.2:** Initial release with Sledgehammer logic and state tracking.
