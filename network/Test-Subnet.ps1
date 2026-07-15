<#
    Test-Subnet.ps1 — fast parallel ping sweep of a /24 subnet, with DNS names for live hosts
    PC-Addicts script library · github.com/socaldavis/powershell-for-sysadmins
    Rewritten, generalized version of a script shown in the "Sr. SysAdmin PowerShell" series.
#>

<#
.SYNOPSIS
    Sweeps a /24 subnet for live hosts using a parallel ping.

.DESCRIPTION
    Pings every address in a /24 (or a slice of it via -StartRange/-EndRange) and
    returns the hosts that answered, with the DNS name resolved where available.

    Speed comes from a runspace pool: all 254 pings run concurrently instead of one
    at a time, so a full sweep takes seconds, not minutes. This pattern works on
    Windows PowerShell 5.1 — it does NOT use ForEach-Object -Parallel, which is
    PowerShell 7-only.

.PARAMETER Subnet
    The first three octets of the /24, without a trailing dot. Example: "192.168.1".

.PARAMETER StartRange
    First host octet to test (1-254). Default: 1.

.PARAMETER EndRange
    Last host octet to test (1-254). Default: 254.

.PARAMETER TimeoutMs
    Per-ping timeout in milliseconds. Default: 1000. Lower it on a fast LAN.

.EXAMPLE
    PS> .\Test-Subnet.ps1 -Subnet "192.168.1"

    Sweeps 192.168.1.1 through 192.168.1.254 and lists every host that answered,
    with its DNS name where reverse lookup succeeds.

.EXAMPLE
    PS> .\Test-Subnet.ps1 -Subnet "10.0.50" -StartRange 100 -EndRange 150 |
            Export-Csv C:\Temp\dhcp-pool-scan.csv -NoTypeInformation

    Checks just the DHCP pool slice of 10.0.50.0/24 and saves the results to CSV.

.NOTES
    Part of the PC-Addicts script library — github.com/socaldavis/powershell-for-sysadmins
    — demonstrated on youtube.com/@PCAddicts. Test in a lab before production.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    # Three octets only — we build the fourth ourselves.
    [ValidatePattern('^(\d{1,3})\.(\d{1,3})\.(\d{1,3})$')]
    [string]$Subnet,

    [ValidateRange(1, 254)]
    [int]$StartRange = 1,

    [ValidateRange(1, 254)]
    [int]$EndRange = 254,

    [ValidateRange(100, 10000)]
    [int]$TimeoutMs = 1000
)

if ($StartRange -gt $EndRange) {
    throw "StartRange ($StartRange) cannot be greater than EndRange ($EndRange)."
}

# The work each runspace performs: one ping, return a result object.
# .NET's Ping class is used instead of Test-Connection because it's lighter
# and takes a timeout directly — 254 WMI pings would be much slower on 5.1.
$pingScript = {
    param ([string]$IPAddress, [int]$TimeoutMs)

    $pinger = New-Object System.Net.NetworkInformation.Ping
    try {
        $reply = $pinger.Send($IPAddress, $TimeoutMs)
        [PSCustomObject]@{
            IPAddress      = $IPAddress
            Alive          = ($reply.Status -eq 'Success')
            ResponseTimeMs = if ($reply.Status -eq 'Success') { $reply.RoundtripTime } else { $null }
        }
    }
    catch {
        # Treat any send error (e.g. no route) the same as "not alive".
        [PSCustomObject]@{ IPAddress = $IPAddress; Alive = $false; ResponseTimeMs = $null }
    }
    finally {
        $pinger.Dispose()
    }
}

# Runspace pool = a bounded set of worker threads we hand PowerShell instances to.
# 64 is plenty for a /24 and keeps thread count sane on modest hardware.
$pool = [runspacefactory]::CreateRunspacePool(1, 64)
$pool.Open()

$jobs = foreach ($octet in $StartRange..$EndRange) {
    $ip = "$Subnet.$octet"

    $ps = [powershell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript($pingScript).AddArgument($ip).AddArgument($TimeoutMs)

    # BeginInvoke starts the ping without waiting — that's the parallelism.
    [PSCustomObject]@{
        PowerShell = $ps
        Handle     = $ps.BeginInvoke()
    }
}

Write-Verbose ("Sweeping {0}.{1}-{2} ({3} addresses)..." -f $Subnet, $StartRange, $EndRange, $jobs.Count)

try {
    foreach ($job in $jobs) {
        # EndInvoke blocks until THAT ping is done; since they all started together,
        # total wall time is roughly one timeout, not 254 of them.
        $result = $job.PowerShell.EndInvoke($job.Handle)
        $job.PowerShell.Dispose()

        if (-not $result.Alive) { continue }

        # Reverse-DNS only the live hosts — resolving 254 dead IPs would be slow.
        $dnsName = try {
            [System.Net.Dns]::GetHostEntry($result.IPAddress).HostName
        }
        catch {
            $null  # no PTR record is normal; not an error worth surfacing
        }

        [PSCustomObject]@{
            IPAddress      = $result.IPAddress
            HostName       = $dnsName
            ResponseTimeMs = $result.ResponseTimeMs
        }
    }
}
finally {
    $pool.Close()
    $pool.Dispose()
}

# Example (commented out so pasting this file does nothing):
# .\Test-Subnet.ps1 -Subnet "192.168.1" -Verbose
