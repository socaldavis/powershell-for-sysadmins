<#
    Start-PingLogger.ps1 — continuous ping that logs ONLY the failures (for "the network keeps dropping" tickets)
    PC-Addicts script library · github.com/socaldavis/powershell-for-sysadmins
    Rewritten, generalized version of a script shown in the "Sr. SysAdmin PowerShell" series.
#>

<#
.SYNOPSIS
    Pings a host continuously and logs only the failures/timeouts to a file.

.DESCRIPTION
    The classic troubleshooting tool for "users say the network drops but it works
    every time I look at it." Start-PingLogger pings -TargetHost on an interval and
    writes a line to -LogPath ONLY when a ping fails, with a timestamp and the error
    detail. Successful pings stay quiet (a heartbeat is available via -Verbose), so
    after an hour — or overnight — the log file IS the list of outages.

    Runs until Ctrl+C by default, or for a fixed window with -DurationMinutes.
    On exit it emits a summary object: total pings, failures, and failure percentage.

    Windows PowerShell 5.1 compatible. (On PowerShell 7, Test-Connection has extra
    switches like -TargetName; nothing here relies on them.)

.PARAMETER TargetHost
    Hostname or IP address to ping (e.g. DC01, 192.168.1.1, corp.example.lab).

.PARAMETER LogPath
    File that failures are appended to. Created (including the folder) if missing.

.PARAMETER IntervalSeconds
    Seconds to wait between pings. Default: 2.

.PARAMETER DurationMinutes
    How long to run, in minutes. Default: 0 = run until you press Ctrl+C.

.EXAMPLE
    PS> .\Start-PingLogger.ps1 -TargetHost DC01 -LogPath C:\Temp\dc01-drops.log -Verbose

    Pings DC01 every 2 seconds until Ctrl+C, logging failures to dc01-drops.log.
    -Verbose shows a heartbeat on the console so you can see it's alive.

.EXAMPLE
    PS> .\Start-PingLogger.ps1 -TargetHost 192.168.1.1 -LogPath C:\Temp\gw.log -IntervalSeconds 5 -DurationMinutes 60

    Pings the gateway every 5 seconds for one hour, then returns the summary object —
    perfect to kick off before lunch and review when you're back.

.NOTES
    Part of the PC-Addicts script library — github.com/socaldavis/powershell-for-sysadmins
    — demonstrated on youtube.com/@PCAddicts. Test in a lab before production.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetHost,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$LogPath,

    [ValidateRange(1, 3600)]
    [int]$IntervalSeconds = 2,

    # 0 = no time limit; run until Ctrl+C
    [ValidateRange(0, 10080)]
    [int]$DurationMinutes = 0
)

# Make sure the log folder exists before we start — failing an hour in would hurt.
$logFolder = Split-Path -Path $LogPath -Parent
if ($logFolder -and -not (Test-Path -Path $logFolder)) {
    New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
}

$totalPings = 0
$failures   = 0
$startTime  = Get-Date

# Precompute the stop time once instead of checking DurationMinutes math every loop.
$stopTime = if ($DurationMinutes -gt 0) { $startTime.AddMinutes($DurationMinutes) } else { [datetime]::MaxValue }

"[{0:yyyy-MM-dd HH:mm:ss}] === Ping logger started against {1} (interval {2}s) ===" -f (Get-Date), $TargetHost, $IntervalSeconds |
    Add-Content -Path $LogPath

Write-Verbose "Logging failures to $LogPath — press Ctrl+C to stop."

try {
    while ((Get-Date) -lt $stopTime) {
        $totalPings++

        try {
            # -Count 1 + -ErrorAction Stop: one echo, and a timeout/unreachable throws
            # so we land in catch with the real error message for the log.
            $reply = Test-Connection -ComputerName $TargetHost -Count 1 -ErrorAction Stop
            Write-Verbose ("[{0:HH:mm:ss}] #{1} OK  {2}ms" -f (Get-Date), $totalPings, $reply.ResponseTime)
        }
        catch {
            $failures++
            $line = "[{0:yyyy-MM-dd HH:mm:ss}] FAIL #{1} — {2}" -f (Get-Date), $totalPings, $_.Exception.Message
            Add-Content -Path $LogPath -Value $line
            Write-Warning $line
        }

        Start-Sleep -Seconds $IntervalSeconds
    }
}
finally {
    # This block runs on normal completion AND on Ctrl+C, so the log always
    # gets a closing summary line even if you kill the script mid-run.
    $failurePct = if ($totalPings -gt 0) { [math]::Round(($failures / $totalPings) * 100, 2) } else { 0 }

    $summary = [PSCustomObject]@{
        TargetHost     = $TargetHost
        StartTime      = $startTime
        EndTime        = Get-Date
        TotalPings     = $totalPings
        Failures       = $failures
        FailurePercent = $failurePct
        LogPath        = $LogPath
    }

    "[{0:yyyy-MM-dd HH:mm:ss}] === Stopped. {1} pings, {2} failures ({3}%) ===" -f (Get-Date), $totalPings, $failures, $failurePct |
        Add-Content -Path $LogPath

    # Note: on Ctrl+C the pipeline is already shutting down, so object output can be
    # swallowed — the Write-Warning below guarantees you still see the numbers.
    Write-Warning ("Summary: {0} pings, {1} failures ({2}%). Details: {3}" -f $totalPings, $failures, $failurePct, $LogPath)
    $summary
}

# Example (commented out so pasting this file does nothing):
# .\Start-PingLogger.ps1 -TargetHost DC01 -LogPath C:\Temp\dc01-drops.log -Verbose
