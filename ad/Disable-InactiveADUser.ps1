#Requires -Modules ActiveDirectory
<#
    Disable-InactiveADUser.ps1 — disable AD user accounts that haven't logged on in N days
    PC-Addicts script library · github.com/socaldavis/powershell-for-sysadmins
    Rewritten, generalized version of a script shown in the "Sr. SysAdmin PowerShell" series.
#>

<#
.SYNOPSIS
    Finds enabled AD user accounts inactive for a given number of days and disables them.

.DESCRIPTION
    Queries Active Directory for ENABLED user accounts whose lastLogonTimestamp is older than
    today minus -DaysInactive, then disables each one. Before disabling, the account's
    Description field is stamped with an audit note:

        Disabled 2026-07-15 - inactive 90 days - by Disable-InactiveADUser.ps1

    That stamp is the difference between a cleanup script and a mystery six months later —
    anyone who opens the account in ADUC can see when, why, and what disabled it.

    Teaching point: lastLogonTimestamp is replicated but only refreshed when it's more than
    ~14 days stale, so it's reliable for 90-day questions, not same-week ones.

    This script CHANGES accounts, so it supports -WhatIf / -Confirm and defaults to prompting
    (ConfirmImpact = High). Use -ReportOnly to just see the candidate list.

.PARAMETER DaysInactive
    How many days without a logon before an account counts as inactive. Defaults to 90.

.PARAMETER SearchBase
    Optional distinguished name of an OU to limit the search to,
    e.g. "OU=Staff,DC=corp,DC=example,DC=lab". Defaults to the whole domain — which is why
    you should almost always scope this in production.

.PARAMETER ReportOnly
    Output the candidate accounts without disabling anything. Run with this first, always.

.EXAMPLE
    .\Disable-InactiveADUser.ps1 -WhatIf

    Shows exactly which accounts WOULD be disabled without touching anything.

.EXAMPLE
    .\Disable-InactiveADUser.ps1 -DaysInactive 120 -ReportOnly

    Just lists accounts inactive 120+ days — no changes, no prompts.

.EXAMPLE
    .\Disable-InactiveADUser.ps1 -DaysInactive 90 -SearchBase "OU=Staff,DC=corp,DC=example,DC=lab" -Confirm:$false

    Disables inactive accounts in the Staff OU without per-account prompts (for a scheduled
    task you've already validated in the lab).

.NOTES
    Part of the PC-Addicts script library — github.com/socaldavis/powershell-for-sysadmins
    — demonstrated on youtube.com/@PC-Addicts. Test in a lab before production.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$DaysInactive = 90,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SearchBase,

    [Parameter()]
    [switch]$ReportOnly
)

$cutoff = (Get-Date).AddDays(-$DaysInactive)
Write-Verbose "Cutoff date: $cutoff (enabled users silent since before this are candidates)"

# Splat so -SearchBase is only passed when the caller supplied one.
$searchParams = @{
    # Filter server-side: enabled accounts only (disabled ones are already handled),
    # with a lastLogonTimestamp older than the cutoff. Users who have NEVER logged on
    # are deliberately excluded here — brand-new hires would match otherwise.
    Filter     = { (Enabled -eq $true) -and (lastLogonTimestamp -lt $cutoff) }
    Properties = 'lastLogonTimestamp', 'description'
}
if ($SearchBase) { $searchParams['SearchBase'] = $SearchBase }

$candidates = Get-ADUser @searchParams

Write-Verbose "Found $(@($candidates).Count) candidate account(s)."

foreach ($user in $candidates) {

    $lastLogon = [DateTime]::FromFileTime($user.lastLogonTimestamp)

    # Emit the candidate object first, so both -ReportOnly and the real run
    # produce the same reviewable output.
    [PSCustomObject]@{
        SamAccountName = $user.SamAccountName
        Name           = $user.Name
        LastLogon      = $lastLogon
        DaysInactive   = [int]((Get-Date) - $lastLogon).Days
        Disabled       = -not $ReportOnly
    }

    # Report mode: look, don't touch.
    if ($ReportOnly) { continue }

    # ShouldProcess is what makes -WhatIf and -Confirm work — every state change
    # goes through this gate, one account at a time.
    if ($PSCmdlet.ShouldProcess($user.SamAccountName, "Disable inactive AD user (last logon $lastLogon)")) {

        # Audit stamp goes on FIRST: if the script dies between the two calls,
        # a stamped-but-enabled account is easier to explain than a silently
        # disabled one. Dashes only — some tools choke on < > in Description.
        $stamp = 'Disabled {0} - inactive {1} days - by Disable-InactiveADUser.ps1' -f (Get-Date -Format 'yyyy-MM-dd'), $DaysInactive
        Set-ADUser -Identity $user.DistinguishedName -Description $stamp

        Disable-ADAccount -Identity $user.DistinguishedName
        Write-Verbose "Disabled $($user.SamAccountName)"
    }
}

# --- Example invocation (uncomment to run) ---
# .\Disable-InactiveADUser.ps1 -DaysInactive 90 -SearchBase "OU=Staff,DC=corp,DC=example,DC=lab" -WhatIf
