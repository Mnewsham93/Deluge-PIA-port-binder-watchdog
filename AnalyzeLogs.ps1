<#
.SYNOPSIS
    Parses watchdog.log files to provide a health summary of the Deluge & PIA Watchdog.
    v1.5.1 Update: Dynamically calculates and displays the active lifespan of the current VPN IP lease, and reduces the total number of times the log file is read. 
#>

# --- 1. Smart Config Inheritance ---
$LogDir = "C:\ProgramData\deluge" # Fallback Default
$BatPath = Join-Path $PSScriptRoot "deluge_watchdog.bat"

if (Test-Path $BatPath) {
    $BatLine = Get-Content $BatPath | Where-Object { $_ -match '^set "LOG_DIR=(.*?)"' } | Select-Object -First 1
    if ($BatLine -match '^set "LOG_DIR=(.*?)"') {
        $LogDir = $matches[1]
    }
}

$LogFiles = Get-ChildItem -Path $LogDir -Filter "watchdog.log*" | Sort-Object LastWriteTime -Descending

if ($LogFiles.Count -eq 0) {
    Write-Host "No watchdog logs found in $LogDir." -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit
}

# --- Initialize Counters ---
$LifeVpnDrops = 0; $30dVpnDrops = 0
$LifeNetworkUpdates = 0; $30dNetworkUpdates = 0
$LifeSledgehammerCycles = 0; $30dSledgehammerCycles = 0
$LifeRxMB = 0; $30dRxMB = 0
$LifeTxMB = 0; $30dTxMB = 0
$CurrentVPN = "Unknown"

# Define Time Windows
$ThirtyDaysAgo = (Get-Date).AddDays(-30)
$LastDropTime = [datetime]::MinValue

# --- Parse Logs ---
Write-Host "Analyzing $($LogFiles.Count) log file(s)..." -ForegroundColor Cyan

# Reverse the array to read from oldest to newest
[array]::Reverse($LogFiles)

foreach ($File in $LogFiles) {
    $Lines = Get-Content $File.FullName
    foreach ($Line in $Lines) {
        
        # Main parsing gate
        if ($Line -match "\[ERROR\] VPN Interface down" -or $Line -match "\[UPDATE\]" -or $Line -match "\[MAINTENANCE\] Disconnecting VPN" -or $Line -match "\[STATS\]") {
            
            $IsRecent = $false
            $EventTime = [datetime]::MinValue

            # Universal Date Regex: Ignores localized day abbreviations and accepts slashes, dashes, or dots
            if ($Line -match "^\[.*?\s+(\d{2,4}[-/\.]\d{2}[-/\.]\d{2,4}\s+\d{1,2}:\d{2}:\d{2})") {
                try {
                    $EventTime = [datetime]$matches[1]
                    if ($EventTime -ge $ThirtyDaysAgo) { $IsRecent = $true }
                } catch {}
            }

            # 1. EVENT DEBOUNCING: The VPN Drop Cluster Logic
            if ($Line -match "\[ERROR\] VPN Interface down") {
                if ($EventTime -gt $LastDropTime.AddMinutes(5)) {
                    $LifeVpnDrops++
                    if ($IsRecent) { $30dVpnDrops++ }
                }
                $LastDropTime = $EventTime 
            }

            # 2. Standard Tallying for isolated events
            if ($Line -match "\[UPDATE\]") {
                $LifeNetworkUpdates++
                if ($IsRecent) { $30dNetworkUpdates++ }
            }
            if ($Line -match "\[MAINTENANCE\] Disconnecting VPN") {
                $LifeSledgehammerCycles++
                if ($IsRecent) { $30dSledgehammerCycles++ }
            }
            
            # 3. Telemetry Parsing
            if ($Line -match "\[STATS\] Delta -> RX: ([\d\.]+) MB \| TX: ([\d\.]+) MB") {
                try {
                    $rx = [double]$matches[1]
                    $tx = [double]$matches[2]
                    $LifeRxMB += $rx
                    $LifeTxMB += $tx
                    if ($IsRecent) {
                        $30dRxMB += $rx
                        $30dTxMB += $tx
                    }
                } catch {}
            }
        }
        
        # --- End of main parse loop ---
        # IP Extraction
        if ($Line -match "Monitoring: ([\d\.]+):(\d+)") { $CurrentVPN = "$($matches[1]):$($matches[2])" }
        elseif ($Line -match "clean bind to: ([\d\.]+):(\d+)") { $CurrentVPN = "$($matches[1]):$($matches[2])" }
    }
}

# $Lines naturally retains the contents of the newest log from the final loop iteration.
# We can filter it directly from memory without hitting the disk again.
$Last10Lines = $Lines | Where-Object { $_.Trim() -ne "" } | Select-Object -Last 10

# --- Calculate True IP Lease Age ---
$VpnDurationString = "N/A"
if ($CurrentVPN -and $CurrentVPN -ne "Unknown") {
    $RawIpToFind = $CurrentVPN.Split(':')[0]
    
    # Default our historical boundary index to the very first line of the log file
    $BoundaryIndex = 0

    # Scan backward from the end of the log array
    for ($i = $Lines.Count - 1; $i -ge 0; $i--) {
        # Check if the line explicitly defines a binding or status checkpoint for a DIFFERENT IP address
        if ($Lines[$i] -match "(?:Monitoring|bind to|Bound to):\s*([\d\.]+)") {
            $FoundIp = $matches[1]
            if ($FoundIp -ne $RawIpToFind) {
                # We have found the absolute newest log line associated with an OLD IP address.
                # Therefore, the lease age boundary is the line immediately following this one (+1).
                $BoundaryIndex = $i + 1
                if ($BoundaryIndex -ge $Lines.Count) { $BoundaryIndex = $Lines.Count - 1 }
                break
            }
        }
    }

    # Extract the timestamp from the derived historical boundary line
    $BoundaryLine = $Lines[$BoundaryIndex]
    if ($BoundaryLine -match "^\[([A-Za-z]{3}\s+\d{2}/\d{2}/\d{4}\s+\d{1,2}:\d{2}:\d{2}\.\d{2})\]") {
        $LogTimeStampRaw = $matches[1]
        $NormalizedStamp = $LogTimeStampRaw -replace '\s+', ' '
        
        try {
            $FirstSeenDate = [datetime]::ParseExact($NormalizedStamp, "ddd MM/dd/yyyy H:mm:ss.ff", $null)
            $TimeSpan = (Get-Date) - $FirstSeenDate
            
            if ($TimeSpan.TotalDays -ge 1) {
                $VpnDurationString = "{0}d {1}h {2}m" -f [math]::Floor($TimeSpan.TotalDays), $TimeSpan.Hours, $TimeSpan.Minutes
            } else {
                $VpnDurationString = "{0}h {1}m" -f $TimeSpan.Hours, $TimeSpan.Minutes
            }
        } catch {}
    }
}

# --- Calculate Uptime & Next Cycle ---
$DaemonProcess = Get-Process -Name "deluged" -ErrorAction SilentlyContinue | Select-Object -First 1

if ($DaemonProcess) {
    $DaemonStatus = "RUNNING"
    $StatusColor = "Green"
    
    try {
        $UptimeSeconds = [math]::Truncate((New-TimeSpan -Start $DaemonProcess.StartTime).TotalSeconds)
        $UptimeSpan = [timespan]::fromseconds($UptimeSeconds)
        $TotalHours = [int][math]::Floor($UptimeSpan.TotalHours)
        $UptimeString = "{0:D2}h {1:D2}m {2:D2}s" -f $TotalHours, $UptimeSpan.Minutes, $UptimeSpan.Seconds
        
        $SecondsToSledgehammer = 86400 - $UptimeSeconds
        if ($SecondsToSledgehammer -lt 0) { $SecondsToSledgehammer = 0 }
        
        $SledgeSpan = [timespan]::fromseconds($SecondsToSledgehammer)
        $TotalSledgeHours = [int][math]::Floor($SledgeSpan.TotalHours)
        $SledgeString = "{0:D2}h {1:D2}m {2:D2}s" -f $TotalSledgeHours, $SledgeSpan.Minutes, $SledgeSpan.Seconds
    } catch {
        $UptimeString = "[Calculation Error]"
        $SledgeString = "[Calculation Error]"
        $DaemonStatus = "OFFLINE"
        $StatusColor = "Red"
        $LiveError = "Math/TimeSync Error: $($_.Exception.Message)"
    }
} else {
    $UptimeString = "N/A"
    $SledgeString = "N/A"
    $DaemonStatus = "OFFLINE"
    $StatusColor = "Red"
}

# --- Format Data Strings (Convert MB to GB) ---
$30dRxDisp = "$([math]::Round($30dRxMB / 1024, 2)) GB"
$LifeRxDisp = "$([math]::Round($LifeRxMB / 1024, 2)) GB"
$30dTxDisp = "$([math]::Round($30dTxMB / 1024, 2)) GB"
$LifeTxDisp = "$([math]::Round($LifeTxMB / 1024, 2)) GB"

# --- Output Dashboard ---
Clear-Host
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  DELUGE WATCHDOG v1.5.1 HEALTH DASHBOARD " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Daemon Status:     " -NoNewline; Write-Host $DaemonStatus -ForegroundColor $StatusColor
Write-Host "Current VPN IP:    $CurrentVPN"
Write-Host "IP Lease Age:      $VpnDurationString"
Write-Host "Daemon Uptime:     $UptimeString"
Write-Host "Next Sledgehammer: $SledgeString"
Write-Host ""
Write-Host "--- Activity Metrics ---" -ForegroundColor Yellow
Write-Host "                       [30-Day]    [Lifetime]" -ForegroundColor DarkGray
Write-Host "VPN Drops Detected:    $("$30dVpnDrops".PadRight(12))$LifeVpnDrops"
Write-Host "Network Updates:       $("$30dNetworkUpdates".PadRight(12))$LifeNetworkUpdates"
Write-Host "24h Sledgehammers:     $("$30dSledgehammerCycles".PadRight(12))$LifeSledgehammerCycles"
Write-Host "Data Downloaded:       $($30dRxDisp.PadRight(12))$LifeRxDisp"
Write-Host "Data Uploaded:         $($30dTxDisp.PadRight(12))$LifeTxDisp"
Write-Host ""
Write-Host "--- Last 10 Watchdog Events ---" -ForegroundColor Yellow
if ($Last10Lines) {
    foreach ($line in $Last10Lines) {
        Write-Host $line -ForegroundColor Gray
    }
} else {
    Write-Host "No recent events found." -ForegroundColor DarkGray
}
Write-Host ""

# NEW: Display live UI errors if they occurred
if ($LiveError) {
    Write-Host "--- System Diagnostics ---" -ForegroundColor Red
    Write-Host "[!] $LiveError" -ForegroundColor Red
    Write-Host ""
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
