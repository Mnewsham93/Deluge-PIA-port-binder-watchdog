# ==============================================================================
# WATCHDOG TIMER ANALYZER v5.4
# Tracks 48h Maintenance Cycles, Network Resyncs, & System Boots (Rolling 30 Days)
# ==============================================================================

$logDir = "C:\ProgramData\deluge"
$logPath = "$logDir\watchdog.log"
$archivePath = "$logDir\watchdog.log.1"

# 1. READ LOGS
if (-not (Test-Path $logPath)) { Write-Host "Log file not found." -F Red; exit }
$allLines = Get-Content $logPath -ReadCount 0
if (Test-Path $archivePath) {
    $archiveLines = Get-Content $archivePath -ReadCount 0
    $combinedLines = $archiveLines + $allLines
} else {
    $combinedLines = $allLines
}

# --- 30-DAY ROLLING WINDOW FILTER ---
$cutoffDate = (Get-Date).AddDays(-30)

function Is-Recent ($line) {
    # Extracts the date from the custom bracket format: [Mon 02/16/2026 14:30:07.16]
    if ($line -match '\[[A-Za-z]{3}\s+(.*?)\.\d{2,3}\]') {
        try {
            return ([datetime]$matches[1] -ge $cutoffDate)
        } catch { return $false }
    }
    return $false
}

# 2. PARSE EVENTS (Filtered to last 30 days)
$maintenanceEvents = $combinedLines | Where-Object { $_ -match '\[MAINTENANCE\]' -and (Is-Recent $_) }
$rawCrashEvents    = $combinedLines | Where-Object { $_ -match '\[WARNING\] Daemon down' -and (Is-Recent $_) }
$vpnEvents         = $combinedLines | Where-Object { $_ -match '\[UPDATE\]' -and (Is-Recent $_) }
$heartbeats        = $combinedLines | Where-Object { $_ -match 'HEARTBEAT' }

# --- SYSTEM BOOT INTERCEPTION ---
$crashEvents = @()
$bootEventsCount = 0

$eventLogAccessible = $true
$systemBoots = @()

try {
    # Fetch boot events. It easily holds 30 days of boots with your 500MB log size.
    $systemBoots = Get-WinEvent -FilterHashtable @{LogName='System'; Id=6005} -MaxEvents 50 -ErrorAction Stop | Select-Object -ExpandProperty TimeCreated
} catch {
    if ($_.FullyQualifiedErrorId -match "NoMatchingEventsFound") {
        $systemBoots = @() 
    } else {
        $eventLogAccessible = $false 
    }
}

foreach ($line in $rawCrashEvents) {
    $isBoot = $false
    if ($line -match '\[[A-Za-z]{3}\s+(.*?)\.\d{2,3}\]') {
        try {
            $logTime = [datetime]$matches[1]
            if ($eventLogAccessible -and $systemBoots.Count -gt 0) {
                foreach ($boot in $systemBoots) {
                    # If the script logged a crash within 5 mins of Windows booting, it's just a restart
                    if ([math]::Abs(($logTime - $boot).TotalMinutes) -le 5) {
                        $isBoot = $true
                        break
                    }
                }
            }
        } catch {}
    }
    
    if ($isBoot) {
        $bootEventsCount++
    } else {
        $crashEvents += $line
    }
}
# --------------------------------

# 3. CALCULATE STATUS
$currentUptime = 0
$timeRemaining = 48

if ($heartbeats.Count -gt 0) {
    $lastBeat = $heartbeats[-1]
    if ($lastBeat -match 'Active:\s*(\d+)h') {
        $currentUptime = [int]$matches[1]
    }
    $timeRemaining = 48 - $currentUptime
    if ($timeRemaining -lt 0) { $timeRemaining = 0 }
}

# 4. REPORT
Clear-Host
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "      WATCHDOG TIMER ANALYZER v5.4" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$statusColor = "Green"
if ($timeRemaining -lt 2) { $statusColor = "Yellow" }
if ($crashEvents.Count -gt 5) { $statusColor = "Red" }

Write-Host " [DELUGE UPTIME] " -NoNewline
Write-Host "${currentUptime} Hours" -ForegroundColor White
Write-Host " [NEXT WIPE]     " -NoNewline
Write-Host "In $timeRemaining Hours" -ForegroundColor $statusColor

Write-Host "`n--------------------------------------------" -ForegroundColor DarkGray
Write-Host " EVENT HISTORY (Last 30 Days)" -ForegroundColor Gray
Write-Host "--------------------------------------------" -ForegroundColor DarkGray

Write-Host " [MAINTENANCE]   " -NoNewline
Write-Host "$($maintenanceEvents.Count)" -ForegroundColor Green -NoNewline
Write-Host " (Scheduled 48h Resets)"

Write-Host " [VPN RESYNCS]   " -NoNewline
Write-Host "$($vpnEvents.Count)" -ForegroundColor Cyan -NoNewline
Write-Host " (IP/Port Corrections)"

Write-Host " [SYSTEM BOOTS]  " -NoNewline
if ($eventLogAccessible) {
    Write-Host "$bootEventsCount" -ForegroundColor Yellow -NoNewline
    Write-Host " (Expected Restarts)"
} else {
    Write-Host "ERROR" -ForegroundColor Magenta -NoNewline
    Write-Host " (Need Admin Rights)"
}

Write-Host " [CRASHES]       " -NoNewline
if ($crashEvents.Count -gt 0) {
    Write-Host "$($crashEvents.Count)" -ForegroundColor Red
} else {
    Write-Host "0" -ForegroundColor White
}

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "        LAST 5 LOG ENTRIES"
Write-Host "============================================" -ForegroundColor Cyan
$allLines | Select-Object -Last 5
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
