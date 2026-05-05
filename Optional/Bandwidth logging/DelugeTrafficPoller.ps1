<#
.SYNOPSIS
    Standalone Traffic Poller for wgpia0.
    Calculates delta traffic to survive VPN adapter resets.
    Designed as a decoupled "Sidecar" to the Deluge Watchdog.
#>

$AdapterName = "wgpia0"
$LogFile = "C:\ProgramData\deluge\watchdog.log"
$StateFile = "C:\ProgramData\deluge\traffic_state.json"

# --- 1. Get Current Stats from Windows ---
$Stats = Get-NetAdapterStatistics -Name $AdapterName -ErrorAction SilentlyContinue

if (-not $Stats) {
    # Adapter is currently down, exit silently
    exit
}

$CurrentRx = $Stats.ReceivedBytes
$CurrentTx = $Stats.SentBytes

# --- 2. Load Previous State ---
$LastRx = 0; $LastTx = 0
if (Test-Path $StateFile) {
    try {
        $State = Get-Content $StateFile | ConvertFrom-Json
        $LastRx = $State.LastRx
        $LastTx = $State.LastTx
    } catch {}
}

# --- 3. Calculate Delta ---
# If Current is less than Last, the adapter was reset. Current is the total since reset.
if ($CurrentRx -lt $LastRx) { $DeltaRx = $CurrentRx } else { $DeltaRx = $CurrentRx - $LastRx }
if ($CurrentTx -lt $LastTx) { $DeltaTx = $CurrentTx } else { $DeltaTx = $CurrentTx - $LastTx }

# --- 4. Format and Log (Only if data actually moved) ---
if ($DeltaRx -gt 0 -or $DeltaTx -gt 0) {
    $MbRx = [math]::Round($DeltaRx / 1MB, 2)
    $MbTx = [math]::Round($DeltaTx / 1MB, 2)

    # Capture time once to prevent race-condition desync
    $Now = Get-Date
    $RawTime = $Now.ToString("H:mm:ss.ff")
    
    # Pad single-digit hours with a leading space (matches Windows %TIME% behavior)
    if ($RawTime.Length -eq 10) { $RawTime = " $RawTime" } 
    
    # Use ONE space in the format string. 
    # Result: [Date  Time] for 1-9 AM, [Date Time] for 10-12 PM.
    $Timestamp = "[{0} {1}]" -f $Now.ToString("ddd MM/dd/yyyy"), $RawTime
    
    $LogLine = "$Timestamp [ID:SIDECAR] [STATS] Delta -> RX: $MbRx MB | TX: $MbTx MB"
    
    # Anti-Collision Retry Logic (Out-of-phase with 15s Watchdog loop)
    $MaxAttempts = 3
    $Attempt = 0
    $WriteSuccess = $false

    while (-not $WriteSuccess -and $Attempt -lt $MaxAttempts) {
        try {
            Add-Content -Path $LogFile -Value $LogLine -ErrorAction Stop
            $WriteSuccess = $true
        } catch {
            $Attempt++
            if ($Attempt -lt $MaxAttempts) {
                # Wait 12 seconds to break resonance with the Watchdog's 15s loop
                Start-Sleep -Seconds 12 
            }
        }
    }
}

# --- 5. Save Current State for Next Run ---
try {
    $NewState = @{ LastRx = $CurrentRx; LastTx = $CurrentTx }
    $NewState | ConvertTo-Json | Set-Content -Path $StateFile -ErrorAction SilentlyContinue
} catch {}
