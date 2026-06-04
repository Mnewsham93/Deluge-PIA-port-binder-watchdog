# Deluge & PIA Port Binder Watchdog (v1.5.1)

A high-resilience Windows automation utility designed to manage the Deluge daemon and Private Internet Access (PIA) VPN. Built as a "batch-metal" alternative to Dockerized solutions (such as Gluetun), this watchdog avoids WSL2 virtualization overhead and container "stale socket" failures by running natively on the host system. It ensures that your traffic is strictly bound to the active VPN interface and forwarded port, providing an autonomous, self-healing killswitch for long-term deployments.

> **CRITICAL REQUIREMENT:** Windows Smart App Control (SAC) must be disabled. If enabled, SAC may block `deluged.exe` from spawning after 24-48 hours of background operation.

---

### Why Native Watchdog vs. Docker/Gluetun?
While Gluetun is excellent for Linux, running a VPN-torrent stack in Docker on Windows 11 introduces a virtualization performance cost.
* **Memory Efficiency:** Consumes virtually 0 MB RAM while idling, avoiding the 1.5 GB - 2.0 GB baseline `vmmemWSL` tax required by Docker Desktop.
* **Disk I/O Performance:** Operates at native NTFS speeds. Bypasses the 9P translation layer overhead that typically throttles high-speed torrenting in WSL2.
* **Network Stability:** Avoids "Stale Sockets" common in virtualized network bridges by managing the physical Windows network stack directly.

---

### Key Features
* **Proactive Sledgehammer (24h):** Performs a daily graceful shutdown of Deluge followed by a full VPN tunnel reset via `piactl` to mitigate `libtorrent` memory leaks and request fresh port-forwarding tokens.
* **Atomic Uptime Clock:** Eliminates text-file timer drift by querying the OS directly for the exact `deluged.exe` process start time, ensuring the 24h reset cycle is mathematically flawless.
* **Universal Parsing Engine:** Employs a localization-proof, double-filter regex algorithm to extract the VPN IP. Bypasses language-specific `netsh` variations and ignores WireGuard subnet prefixes.
* **Headless Storm Protection:** Actively polls for the primary user's desktop session (`explorer.exe`). Prevents runaway Task Scheduler instances and cascading log errors when the PC reboots and stalls at the Windows login screen.
* **Atomic State & Log Management:** Utilizes transactional file operations (`move /y`) to prevent race conditions during Task Scheduler handoffs, and natively rotates logs in a 50MB rolling-five buffer to prevent filesystem bloat.
* **Dynamic Telemetry & Dashboard:** Decoupled PowerShell analytics dynamically inherit configurations from the core `.bat` file (Single Source of Truth), providing debounced incident tracking and self-reporting diagnostics without hardcoded paths.

---

### Configuration & Setup

#### 1. Core Script Setup
Open `deluge_watchdog.bat` and update the `:: 4. CONFIG` section with your specific environment variables:
* `PRIMARY_USER`: Your Windows login name (e.g., `Username`).
* `REAL_USER_PATH`: Your Windows user directory (e.g., `C:\Users\Username`).
* `DEL_DIR`: Path to your Deluge install directory (default `C:\Program Files\Deluge`).
* `PIA_CTL`: Path to your `piactl.exe` (usually in `C:\Program Files\Private Internet Access\`).
* `ADAPTER`: Your PIA WireGuard adapter name (default `wgpia0`; only change this if you are not on the default WireGuard tunnel).
* `D_PASS`: Your Deluge `localclient` daemon password.

#### 2. Core Automation (Task Scheduler)
To ensure 24/7 coverage, configure a Windows Task for the core watchdog:
* **Trigger:** "At log on" (or startup) AND "Repeat task every 15 minutes" indefinitely.
* **General:** Enable "Run with highest privileges".
* **Settings:** Set "If the task is already running..." to "Do not start a new instance".
* **Action:** "Start a program" -> Point to `deluge_watchdog.bat`.

---

### 📊 Optional: Lifetime Traffic Tracking (Sidecar)
For users who want to track their total data movement (RX/TX) directly on the Health Dashboard, we provide a decoupled `DelugeTrafficPoller.ps1` sidecar. 

By querying the Windows NDIS network stack instead of the Deluge RPC port, this script tracks bandwidth safely without risking a killswitch hang if the daemon freezes. It automatically calculates deltas to survive VPN adapter resets, and (as of v1.5.1) writes its state cache transactionally to prevent corruption mid-reset.

**Installation:**
1. Locate `DelugeTrafficPoller.ps1` in `/Optional/Bandwidth logging/`. The script inherits `LOG_DIR` from `deluge_watchdog.bat` when both files share the same folder; if you run it from anywhere else (e.g. your Deluge `ProgramData` folder) it falls back to the default `C:\ProgramData\deluge`. So if you have customized `LOG_DIR`, keep the poller alongside `deluge_watchdog.bat`.
2. Create a **new** Windows Task Scheduler task:
   * **Trigger:** "At log on" AND "Repeat task every 15 minutes" indefinitely.
   * **Action:** "Start a program" -> `powershell.exe`
   * **Add arguments:** `-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Path\To\DelugeTrafficPoller.ps1"`
3. The `AnalyzeLogs` dashboard will automatically detect the new data and display your total bandwidth. (Functions perfectly with or without this sidecar running).

---

### Troubleshooting
* **Physical Drops:** If your physical internet goes out, the script will enter a silent error loop. Once the internet returns, it automatically detects the new VPN IP/Port and forcefully restarts the daemon.
* **System Reboots:** The watchdog will peacefully sleep at the login screen. It will only begin attempting to sync and start the VPN/Daemon once the `PRIMARY_USER` physically logs into the desktop session.
* **System Diagnostics:** If file-system permissions fail or unexpected math errors occur, the Dashboard will output live diagnostic warnings at the bottom of the console rather than failing silently.

---

### Version History

* **v1.5.1:** Hardened state management and disk I/O. The optional Traffic Poller now uses transactional atomic writes (temp-file + `move`) for its state cache, eliminating edge-case corruption during adapter resets. The Log Analyzer was optimized to parse the newest log from memory rather than re-reading it from disk for the "Last 10 Events" panel. Retired the redundant uptime state-file (uptime is now sourced exclusively from the OS process clock), consolidated the duplicated VPN IP-extraction logic into a single `:GET_VPN_IP` routine, and hardened the uptime query against transient duplicate daemon instances. Corrected the optional sidecar path and configuration documentation.
* **v1.5.0:** Implemented dynamic configuration inheritance (PowerShell scripts now read paths directly from the Batch SSoT). Added self-reporting telemetry to the Sidecar and Dashboard to capture and display file-system/math errors without silent failures. Finalized documentation naming consistencies.
* **v1.4.1:** Implemented incident debouncing in Log Analyzer to group VPN drops accurately. Added optional decoupled `DelugeTrafficPoller.ps1` sidecar for bandwidth tracking. Added atomic 50MB log rotation to core script.
* **v1.4.0:** Implemented Atomic OS Uptime sync; Universal Regex IP extraction; Atomic State Writes; Bulletproof User Domain checks.
* **v1.3.1:** Updated `AnalyzeLogs.ps1` with portable environment variables to remove hardcoded user paths; Added native vs. virtualized performance documentation.
* **v1.3.0:** Added Headless Storm Protection via `explorer.exe` session gate; relocated instance handoff logic.
* **v1.2.4:** Added Outage Resilience; forced re-bind after physical network interface drops.
* **v1.2.0:** Shifted to proactive maintenance model. Replaced fragile OS queries with an internal stopwatch. Automated 24-hour VPN "Sledgehammer" tunnel resets. Enforced automated disabling of UPnP/NAT-PMP routing protocols.
* **v1.1.0:** Introduced connection-aware monitoring. Added Zero-Peer Failsafe (re-binds if active peers hit 0 for 10 minutes due to Ghost Ports). Dynamically locks outgoing traffic to the VPN interface IP (Full-Bind Security).
* **v1.0.1:** Added MIT License.
* **v1.0.0:** Initial public release. Forces binding to `wgpia0` and active PIA forwarded port. Includes 48h memory leak mitigation and basic 5-second polling killswitch.
