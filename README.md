# Deluge & PIA Port Binder Watchdog (v1.2.4)

A high-resilience Windows automation utility designed to manage the Deluge daemon and Private Internet Access (PIA) VPN. This watchdog ensures that your traffic is strictly bound to the active VPN interface and forwarded port, providing an autonomous, self-healing killswitch for long-term headless deployments.

> **CRITICAL REQUIREMENT:** Windows Smart App Control (SAC) must be disabled. If enabled, SAC may block `deluged.exe` from spawning after 24-48 hours of background operation.

## Key Features
* **Interface Locking:** Force-binds both `listen_interface` and `outgoing_interface` to the dynamic VPN IP to prevent data leaks.
* **Proactive Sledgehammer (24h):** Performs a daily graceful shutdown of Deluge followed by a full VPN tunnel reset via `piactl` to mitigate `libtorrent` memory drift and stale ports.
* **Outage Resilience (v1.2.4):** Specifically engineered to detect physical internet drops. If the VPN interface disappears, the script initiates a "Force-Rebind" the moment connectivity returns, preventing "Dead-Tunnel" scenarios where the daemon process is running but disconnected.
* **Zombie Mitigation:** Employs a "Double-Tap" process termination logic to ensure lingering headless threads are fully cleared before re-establishing network bindings.
* **Persistent Uptime Tracking:** Uses a local state file to track maintenance cycles, ensuring reliability across system restarts and task handoffs.

## Included Files
* `deluge_watchdog.bat` — The core watchdog automation script.
* `AnalyzeLogs.ps1` — A PowerShell-based dashboard to view real-time health, uptime, and IP/Port status.
* `AnalyzeLogs.bat` — An auto-elevating runner for the PowerShell dashboard.

## Configuration

### 1. Script Setup
Open `deluge_watchdog.bat` and update the `:: 4. CONFIG` section:
* `REAL_USER_PATH`: Your Windows user directory (e.g., `C:\Users\Michael`).
* `D_PASS`: Your Deluge localclient daemon password.
* `PIA_CTL`: Path to your `piactl.exe` (usually in `C:\Program Files\Private Internet Access\`).

### 2. Automation (Task Scheduler)
To ensure 24/7 coverage, configure a Windows Task:
1. **Trigger:** `At log on` and `Repeat task every 15 minutes`.
2. **Settings:** Enable `Run with highest privileges`.
3. **Action:** `Start a program` -> Point to `deluge_watchdog.bat`.

## Troubleshooting Outages
If your physical internet goes out, the script will enter an error loop. Once the internet returns:
* The script automatically detects the new VPN IP and Port.
* It will **forcefully restart** the Deluge daemon to ensure the internal sockets are bound to the fresh connection.
* No manual intervention is required.

## Version History
* **v1.2.4:** Added Outage Resilience; forced re-bind after network interface drops.
* **v1.2.3:** Introduced `FORCE_REBIND` flag; fixed zombie process edge cases.
* **v1.2.2:** Initial release with Sledgehammer logic and state tracking.
