#Requires -Modules GroupPolicy
<#
    Find-GPOBySetting.ps1 — search every GPO in the domain for a setting/string
    PC-Addicts script library · github.com/socaldavis/powershell-for-sysadmins
    Rewritten, generalized version of a script shown in the "Sr. SysAdmin PowerShell" series.
#>

<#
.SYNOPSIS
    Finds which GPO(s) contain a given setting, string, or value.

.DESCRIPTION
    "Which GPO is setting the screensaver timeout?" In a domain with hundreds of
    GPOs, clicking through the GPMC is misery. This script pulls the XML report for
    every GPO (Get-GPOReport -ReportType Xml) and does a case-insensitive text match
    for -SearchString, telling you which GPOs matched and whether the hit was in the
    Computer half, the User half, or both.

    It searches the raw XML, so it matches setting names, registry keys/values,
    script paths, drive-map targets — anything that appears in the report. Expect a
    full run to take a while in a big domain (one report per GPO); Write-Progress
    keeps you posted.

    Windows PowerShell 5.1 compatible.

.PARAMETER SearchString
    Text to look for, case-insensitive. Examples: "ScreenSaveTimeOut",
    "\\FS01\Software", "Prevent access to the command prompt".

.PARAMETER Domain
    Optional domain to query (defaults to the current user's domain),
    e.g. corp.example.lab.

.EXAMPLE
    PS> .\Find-GPOBySetting.ps1 -SearchString "ScreenSaveTimeOut"

    Reports every GPO that touches the screensaver timeout, and whether the setting
    lives in the Computer or User configuration.

.EXAMPLE
    PS> .\Find-GPOBySetting.ps1 -SearchString "\\FS01\Software" -Domain corp.example.lab |
            Sort-Object GpoName | Format-Table -AutoSize

    Finds every GPO in corp.example.lab that references the FS01 software share —
    the first step of "we're decommissioning FS01, what will break?"

.NOTES
    Part of the PC-Addicts script library — github.com/socaldavis/powershell-for-sysadmins
    — demonstrated on youtube.com/@PC-Addicts. Test in a lab before production.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SearchString,

    [ValidateNotNullOrEmpty()]
    [string]$Domain
)

# Build splatting once so -Domain is only passed when the caller supplied it.
$gpParams = @{}
if ($Domain) { $gpParams['Domain'] = $Domain }

Write-Verbose "Collecting GPO list..."
$allGpos = Get-GPO -All @gpParams
$total   = $allGpos.Count
$index   = 0

Write-Verbose "Searching $total GPOs for '$SearchString'..."

foreach ($gpo in $allGpos) {
    $index++
    # Hundreds of GPOs at ~a report each: a progress bar is the difference between
    # "working" and "is it hung?"
    Write-Progress -Activity "Searching GPOs for '$SearchString'" `
                   -Status  "$index of ${total}: $($gpo.DisplayName)" `
                   -PercentComplete (($index / $total) * 100)

    try {
        [xml]$report = Get-GPOReport -Guid $gpo.Id -ReportType Xml @gpParams -ErrorAction Stop
    }
    catch {
        # A single unreadable GPO (permissions, orphaned SYSVOL) shouldn't kill the search.
        Write-Warning "Could not read report for '$($gpo.DisplayName)': $($_.Exception.Message)"
        continue
    }

    # Rough split: search the Computer and User sections of the XML separately.
    # OuterXml gives us the whole subtree as text; -like with wildcards is
    # case-insensitive by default in PowerShell, which is what we want.
    $pattern       = "*$SearchString*"
    $computerMatch = $report.GPO.Computer -and ($report.GPO.Computer.OuterXml -like $pattern)
    $userMatch     = $report.GPO.User     -and ($report.GPO.User.OuterXml     -like $pattern)

    if (-not ($computerMatch -or $userMatch)) { continue }

    $matchedIn = if ($computerMatch -and $userMatch) { 'Both' }
                 elseif ($computerMatch)             { 'Computer' }
                 else                                { 'User' }

    [PSCustomObject]@{
        GpoName   = $gpo.DisplayName
        GpoId     = $gpo.Id
        MatchedIn = $matchedIn
    }
}

Write-Progress -Activity "Searching GPOs for '$SearchString'" -Completed

# Example (commented out so pasting this file does nothing):
# .\Find-GPOBySetting.ps1 -SearchString "ScreenSaveTimeOut" -Verbose
