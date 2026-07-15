#Requires -Modules ActiveDirectory
<#
    Get-InactiveADComputer.ps1 — find AD computer objects that haven't logged on in N days
    PC-Addicts script library · github.com/socaldavis/powershell-for-sysadmins
    Rewritten, generalized version of a script shown in the "Sr. SysAdmin PowerShell" series.
#>

<#
.SYNOPSIS
    Finds Active Directory computer objects whose lastLogonTimestamp is older than a given number of days.

.DESCRIPTION
    Queries AD for computer objects and compares their lastLogonTimestamp against a cutoff date
    (today minus -DaysInactive). Computers that have never logged on (no timestamp at all) are
    included too, since those are usually stale pre-staged objects.

    IMPORTANT teaching point: lastLogonTimestamp is replicated between DCs but only updated when
    it is more than ~14 days out of date. That makes it perfect for "is this machine dead?"
    questions (90+ days) and useless for "who logged on this morning?" questions.

    Read-only: this script changes nothing. Pipe the output to Disable-ADAccount or an export
    once you've reviewed it.

.PARAMETER DaysInactive
    How many days of silence before a computer counts as inactive. Defaults to 90, which is a
    common corporate cleanup threshold (safely past the ~14-day timestamp slack).

.PARAMETER SearchBase
    Optional distinguished name of an OU to limit the search to,
    e.g. "OU=Workstations,DC=corp,DC=example,DC=lab". Defaults to the whole domain.

.EXAMPLE
    .\Get-InactiveADComputer.ps1

    Lists every computer in the domain that hasn't logged on in 90+ days.

.EXAMPLE
    .\Get-InactiveADComputer.ps1 -DaysInactive 180 -SearchBase "OU=Workstations,DC=corp,DC=example,DC=lab"

    Only checks the Workstations OU and uses a stricter 180-day threshold.

.EXAMPLE
    .\Get-InactiveADComputer.ps1 | Export-Csv C:\Reports\stale-computers.csv -NoTypeInformation

    Exports the results for review before any cleanup action.

.NOTES
    Part of the PC-Addicts script library — github.com/socaldavis/powershell-for-sysadmins
    — demonstrated on youtube.com/@PC-Addicts. Test in a lab before production.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$DaysInactive = 90,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SearchBase
)

# Everything older than this date counts as inactive.
$cutoff = (Get-Date).AddDays(-$DaysInactive)
Write-Verbose "Cutoff date: $cutoff (computers silent since before this are flagged)"

# Build the Get-ADComputer call as a splat so -SearchBase is only added when supplied.
# Splatting keeps the actual call readable instead of a wall of backticks.
$searchParams = @{
    # -Filter runs server-side on the DC, so we only pull back the stale objects
    # instead of downloading every computer and filtering locally.
    Filter     = { (lastLogonTimestamp -lt $cutoff) -or (lastLogonTimestamp -notlike '*') }
    Properties = 'lastLogonTimestamp', 'operatingSystem'
}
if ($SearchBase) { $searchParams['SearchBase'] = $SearchBase }

Get-ADComputer @searchParams | ForEach-Object {

    # lastLogonTimestamp is stored as a raw FILETIME (a big integer); convert it to a
    # human-readable DateTime. A missing value means the computer has never logged on.
    $lastLogon = if ($_.lastLogonTimestamp) {
        [DateTime]::FromFileTime($_.lastLogonTimestamp)
    }
    else {
        $null
    }

    # The OU is just the DN with the leading "CN=<name>," chopped off — a handy trick
    # that avoids an extra AD query per computer.
    $ou = ($_.DistinguishedName -split ',', 2)[1]

    # Emit a clean object (not formatted text) so callers can sort, filter, or export it.
    [PSCustomObject]@{
        Name            = $_.Name
        OU              = $ou
        LastLogon       = $lastLogon
        OperatingSystem = $_.operatingSystem
    }
}

# --- Example invocation (uncomment to run) ---
# .\Get-InactiveADComputer.ps1 -DaysInactive 90 -Verbose
