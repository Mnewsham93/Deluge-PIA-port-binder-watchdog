<#
.SYNOPSIS
    Parses watchdog.log files to provide a health summary of the Deluge & PIA Watchdog.
#>

$LogDir = "C:\ProgramData\deluge"
$LogFiles = Get-ChildItem -Path $LogDir -Filter "watchdog.log*" | Sort-Object LastWriteTime -Descending
$StateFile = "C:\Users\Michael\AppData\Roaming\deluge\watchdog_uptime.txt"

if ($LogFiles.Count -eq 0) {
    Write-Host "No watchdog logs found in $LogDir." -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit
}

# --- Initialize Counters ---
$VpnDrops = 0
$NetworkUpdates = 0
$SledgehammerCycles = 0
$CurrentVPN = "Unknown"

# --- Parse Logs ---
Write-Host "Analyzing $($LogFiles.Count) log file(s)..." -ForegroundColor Cyan

# Reverse the array to read from oldest to newest, ensuring the variables hold the latest data
[array]::Reverse($LogFiles)

foreach ($File in $LogFiles) {
    $Lines = Get-Content $File.FullName
    foreach ($Line in $Lines) {
        if ($Line -match "\[ERROR\] VPN Interface down") { $VpnDrops++ }
        if ($Line -match "\[UPDATE\]") { $NetworkUpdates++ }
        if ($Line -match "\[MAINTENANCE\] Disconnecting VPN") { $SledgehammerCycles++ }
        # Capture the combined IP and Port from the init or config lines
        if ($Line -match "Monitoring: ([\d\.]+):(\d+)") { $CurrentVPN = "$($matches[1]):$($matches[2])" }
        elseif ($Line -match "Enforcing Full Bind: ([\d\.]+):(\d+)") { $CurrentVPN = "$($matches[1]):$($matches[2])" }
    }
}

# Re-fetch the newest log specifically to grab the last 5 entries
$NewestLog = Get-ChildItem -Path $LogDir -Filter "watchdog.log*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Last5Lines = Get-Content $NewestLog.FullName | Where-Object { $_.Trim() -ne "" } | Select-Object -Last 5

# --- Calculate Uptime & Next Cycle ---
$DaemonProcess = Get-Process -Name "deluged" -ErrorAction SilentlyContinue | Select-Object -First 1

if ($DaemonProcess) {
    $DaemonStatus = "RUNNING"
    $StatusColor = "Green"
    
    if (Test-Path $StateFile) {
        try {
            $Raw = (Get-Content $StateFile) -join ""
            $Clean = $Raw -replace '\D',''
            if ($Clean -eq "") { $Clean = "0" }
            
            $UptimeSeconds = [int]$Clean
            
            $UptimeSpan = [timespan]::fromseconds($UptimeSeconds)
            $TotalHours = [int][math]::Floor($UptimeSpan.TotalHours)
            $UptimeString = "{0:D2}h {1:D2}m {2:D2}s" -f $TotalHours, $UptimeSpan.Minutes, $UptimeSpan.Seconds
            
            $SecondsToSledgehammer = 86400 - $UptimeSeconds
            if ($SecondsToSledgehammer -lt 0) { $SecondsToSledgehammer = 0 }
            
            $SledgeSpan = [timespan]::fromseconds($SecondsToSledgehammer)
            $TotalSledgeHours = [int][math]::Floor($SledgeSpan.TotalHours)
            $SledgeString = "{0:D2}h {1:D2}m {2:D2}s" -f $TotalSledgeHours, $SledgeSpan.Minutes, $SledgeSpan.Seconds
        } catch {
            $UptimeString = "[Formatting Error - Check Console]"
            $SledgeString = "[Formatting Error - Check Console]"
            $StatusColor = "Yellow"
        }
    } else {
        $UptimeString = "[Waiting for State File]"
        $SledgeString = "[Waiting for State File]"
        $StatusColor = "Yellow"
    }
} else {
    $UptimeString = "N/A"
    $SledgeString = "N/A"
    $DaemonStatus = "OFFLINE"
    $StatusColor = "Red"
}

# --- Output Dashboard ---
Clear-Host
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  DELUGE WATCHDOG v1.2.2 HEALTH DASHBOARD " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Daemon Status:     " -NoNewline; Write-Host $DaemonStatus -ForegroundColor $StatusColor
Write-Host "Current VPN IP:    $CurrentVPN"
Write-Host "Daemon Uptime:     $UptimeString"
Write-Host "Next Sledgehammer: $SledgeString"
Write-Host ""
Write-Host "--- 30-Day Activity History ---" -ForegroundColor Yellow
Write-Host "VPN Drops Detected:    $VpnDrops"
Write-Host "Network Updates:       $NetworkUpdates"
Write-Host "24h Sledgehammers:     $SledgehammerCycles"
Write-Host ""
Write-Host "--- Last 5 Watchdog Events ---" -ForegroundColor Yellow
if ($Last5Lines) {
    foreach ($line in $Last5Lines) {
        Write-Host $line -ForegroundColor Gray
    }
} else {
    Write-Host "No recent events found." -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
