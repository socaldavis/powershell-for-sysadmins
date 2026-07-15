# =====================================================================================
#  PC-Addicts PowerShell Library  —  Disable-UnusedADAccounts
#  ------------------------------------------------------------------------------------
#  FINE PRINT / USE AT YOUR OWN RISK
#  Provided as-is, as a teaching example, with NO WARRANTY of any kind, express or
#  implied. This script is DESTRUCTIVE: it disables Active Directory accounts. Read it,
#  understand exactly what it does, and TEST IT IN A LAB. ALWAYS run it with -WhatIf
#  first and eyeball the list. You are solely responsible for what it does on your
#  systems. Not affiliated with or representative of any employer.
#
#  IMPORTANT SAFETY NOTE: "inactive" is based on lastLogonTimeStamp, which is only
#  replicated periodically (up to ~14 days behind). Service accounts and other
#  non-interactive accounts often look "inactive" and could be caught here — disabling
#  one can break a service. Use -Exclude to protect known accounts, and review every
#  account in the -WhatIf output before running for real.
# =====================================================================================
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Find and disable Active Directory user accounts that haven't logged in for N days.
.DESCRIPTION
    Uses Search-ADAccount to find ENABLED user accounts inactive for the given number
    of days, disables them, and stamps the Description with the date so you keep an
    audit trail of what was auto-disabled and when.

    Modernized from Chris's original (which used the legacy Quest / QAD cmdlets) to the
    built-in ActiveDirectory module so anyone can run it with no extra tools.
.PARAMETER NumberOfDays
    Inactivity threshold in days. Default 180.
.PARAMETER SearchBase
    Distinguished name of the OU to limit the search to. Omit to search the whole domain.
.PARAMETER Exclude
    One or more SamAccountNames to never disable (service accounts, break-glass, etc.).
    Matching is case-insensitive.
.EXAMPLE
    Disable-UnusedADAccounts -NumberOfDays 180 -WhatIf
    Preview which accounts WOULD be disabled — always run this first.
.EXAMPLE
    Disable-UnusedADAccounts -NumberOfDays 90 -SearchBase "OU=Staff,DC=corp,DC=example,DC=lab" -Exclude svc-backup,svc-sql
.NOTES
    Lab-first and destructive. Preview, read the list, protect service accounts, then run.
#>
function Disable-UnusedADAccounts {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [int]$NumberOfDays = 180,
        [string]$SearchBase,
        [string[]]$Exclude = @()
    )

    $searchParams = @{
        AccountInactive = $true
        TimeSpan        = (New-TimeSpan -Days $NumberOfDays)
        UsersOnly       = $true
    }
    if ($SearchBase) { $searchParams['SearchBase'] = $SearchBase }

    $stamp = Get-Date -UFormat '%Y%m%d'

    Search-ADAccount @searchParams |
        Where-Object { $_.Enabled -and ($Exclude -notcontains $_.SamAccountName) } |
        ForEach-Object {
            if ($PSCmdlet.ShouldProcess($_.SamAccountName, 'Disable inactive account')) {
                $current = (Get-ADUser $_.SamAccountName -Properties Description).Description
                Set-ADUser $_.SamAccountName -Enabled $false -Description "Disabled $stamp Auto - $current"
            }
        }
}
