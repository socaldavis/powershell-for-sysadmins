#Requires -Modules ActiveDirectory
<#
    Sync-HRUserToAD.ps1 — teaching skeleton of a nightly HR-export → Active Directory sync
    PC-Addicts script library · github.com/socaldavis/powershell-for-sysadmins
    Rewritten, generalized version of a script shown in the "Sr. SysAdmin PowerShell" series.
#>

<#
.SYNOPSIS
    Syncs a nightly HR CSV export into Active Directory: disables terminated users,
    updates display name and department on changes.

.DESCRIPTION
    This is the teaching skeleton of the single most valuable automation in most shops:
    making the HR system the source of truth for AD. The flow is always the same four
    stages, and the script is laid out in matching #region blocks so you can follow along:

        1. IMPORT   — read the HR CSV export
        2. VALIDATE — refuse to run on bad/suspicious data (the step everyone skips)
        3. MATCH    — pair each HR row with an AD user via the employeeID attribute
        4. APPLY    — make the minimal set of changes, logging every one

    Expected CSV columns: EmployeeId, GivenName, Surname, Status, Department.
    Matching key: the AD "employeeID" attribute. Names change (marriage, typo fixes),
    usernames change (rehires) — the employee ID is the one identifier HR never recycles,
    which is exactly why we match on it and never on name.

    What it does:
      - Status = "Terminated"  →  disable the account and stamp the Description
        ("Disabled 2026-07-15 - HR status Terminated - by Sync-HRUserToAD.ps1")
      - DisplayName or Department differ from HR  →  update them to match HR

    What it deliberately does NOT do (yet — homework for the series):
      - create accounts for HR rows with no AD match (that's onboarding, a bigger topic)
      - move users between OUs, touch group memberships, or delete anything

    Supports -WhatIf / -Confirm on every change, and writes a timestamped log via -LogPath.

.PARAMETER CsvPath
    Path to the HR export CSV. Must contain columns:
    EmployeeId, GivenName, Surname, Status, Department.

.PARAMETER LogPath
    Path to a text log file. Appended (not overwritten) so one file can hold the
    nightly history. Defaults to Sync-HRUserToAD.log next to the CSV.

.EXAMPLE
    .\Sync-HRUserToAD.ps1 -CsvPath C:\HRDrop\hr-export.csv -WhatIf

    Dry run: shows every disable/update the sync WOULD make. Run this against every
    new HR export format before you trust it.

.EXAMPLE
    .\Sync-HRUserToAD.ps1 -CsvPath C:\HRDrop\hr-export.csv -LogPath C:\Logs\hr-sync.log -Confirm:$false

    The scheduled-task form: applies changes without prompting and logs to C:\Logs.

.NOTES
    Part of the PC-Addicts script library — github.com/socaldavis/powershell-for-sysadmins
    — demonstrated on youtube.com/@PC-Addicts. Test in a lab before production.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$CsvPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogPath
)

# Default the log next to the CSV so the export and its outcome travel together.
if (-not $LogPath) {
    $LogPath = Join-Path -Path (Split-Path -Path $CsvPath -Parent) -ChildPath 'Sync-HRUserToAD.log'
}

function Write-SyncLog {
    <#
    .SYNOPSIS
        Appends a timestamped line to the sync log (and echoes it as Verbose).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )
    # One consistent timestamp format makes the log grep-able and sortable.
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogPath -Value $line
    Write-Verbose $line
}

Write-SyncLog "=== Sync run started. CSV: $CsvPath ==="

#region Import ----------------------------------------------------------------------
# Import-Csv gives us one object per row with properties named after the header line.
$hrRows = @(Import-Csv -Path $CsvPath)
Write-SyncLog "Imported $($hrRows.Count) row(s) from HR export."
#endregion Import

#region Validate --------------------------------------------------------------------
# WHY this block exists: an HR export is an external input you don't control.
# The night HR ships a half-written file (or an empty one), a naive sync would
# happily disable nobody's account — or everybody's. Cheap checks here prevent
# expensive incidents later. Validate hard, then trust the data downstream.

# 1. Empty file? A legit nightly export is never zero rows — treat it as a broken feed.
if ($hrRows.Count -eq 0) {
    Write-SyncLog 'ABORT: CSV contained zero rows. Refusing to run against an empty export.'
    throw "HR export '$CsvPath' is empty — aborting sync."
}

# 2. Right columns? Catches HR renaming a column ("Dept") without telling anyone.
$requiredColumns = 'EmployeeId', 'GivenName', 'Surname', 'Status', 'Department'
$actualColumns = $hrRows[0].PSObject.Properties.Name
$missing = $requiredColumns | Where-Object { $_ -notin $actualColumns }
if ($missing) {
    Write-SyncLog "ABORT: CSV is missing column(s): $($missing -join ', ')."
    throw "HR export is missing required column(s): $($missing -join ', ')"
}

# 3. Every row needs an EmployeeId — it's our matching key; a blank one can't be synced.
$blankIds = @($hrRows | Where-Object { [string]::IsNullOrWhiteSpace($_.EmployeeId) })
if ($blankIds.Count -gt 0) {
    Write-SyncLog "ABORT: $($blankIds.Count) row(s) have a blank EmployeeId."
    throw "$($blankIds.Count) HR row(s) have a blank EmployeeId — fix the export before syncing."
}

Write-SyncLog 'Validation passed: columns present, no blank EmployeeIds.'
#endregion Validate

#region Match -----------------------------------------------------------------------
# WHY we pre-load AD into a hashtable: one Get-ADUser per CSV row means thousands of
# round-trips to the DC every night. One bulk query + an in-memory hashtable lookup
# turns an hours-long sync into seconds. This pattern (bulk load, index by key,
# iterate) is the backbone of nearly every sync script you'll ever write.

# Pull every AD user that HAS an employeeID, with just the attributes we compare on.
$adUsers = Get-ADUser -Filter { employeeID -like '*' } -Properties employeeID, displayName, department, description

# Index by employeeID for O(1) lookups. If two AD users share an employeeID that's a
# data problem worth surfacing, so log it and keep the first.
$adByEmployeeId = @{}
foreach ($adUser in $adUsers) {
    if ($adByEmployeeId.ContainsKey($adUser.employeeID)) {
        Write-SyncLog "WARNING: duplicate employeeID '$($adUser.employeeID)' in AD ($($adUser.SamAccountName)); keeping first match."
        continue
    }
    $adByEmployeeId[$adUser.employeeID] = $adUser
}
Write-SyncLog "Loaded $($adByEmployeeId.Count) AD user(s) with an employeeID."
#endregion Match

#region Apply -----------------------------------------------------------------------
# Counters make the end-of-run summary line meaningful ("0 disabled" on a night you
# expected 3 is itself a signal something's wrong upstream).
$stats = @{ Disabled = 0; Updated = 0; NoMatch = 0; Unchanged = 0 }

foreach ($row in $hrRows) {

    $adUser = $adByEmployeeId[$row.EmployeeId]

    # No AD match: log it, don't fail. Could be a new hire not provisioned yet —
    # account creation is intentionally out of scope for this skeleton.
    if (-not $adUser) {
        Write-SyncLog "NO MATCH: EmployeeId $($row.EmployeeId) ($($row.GivenName) $($row.Surname)) has no AD user."
        $stats.NoMatch++
        continue
    }

    # --- Terminations first: security-relevant changes take priority ---------------
    if ($row.Status -eq 'Terminated') {

        # Already disabled? Then a previous run handled it — don't re-stamp the
        # Description every night. Idempotence is what makes a nightly job safe.
        if (-not $adUser.Enabled) {
            $stats.Unchanged++
            continue
        }

        if ($PSCmdlet.ShouldProcess($adUser.SamAccountName, 'Disable (HR status: Terminated)')) {
            # Audit stamp before the disable, dashes not brackets (some tools choke on < >).
            $stamp = 'Disabled {0} - HR status Terminated - by Sync-HRUserToAD.ps1' -f (Get-Date -Format 'yyyy-MM-dd')
            Set-ADUser -Identity $adUser.DistinguishedName -Description $stamp
            Disable-ADAccount -Identity $adUser.DistinguishedName

            Write-SyncLog "DISABLED: $($adUser.SamAccountName) (EmployeeId $($row.EmployeeId)) - HR status Terminated."
            $stats.Disabled++
        }
        # Terminated users get no attribute updates — the account is on its way out.
        continue
    }

    # --- Active users: bring displayName / department in line with HR --------------
    # Compare first, write only on drift: harmless-looking "set it every night anyway"
    # writes bloat the AD replication stream and make change auditing useless.
    $hrDisplayName = '{0} {1}' -f $row.GivenName, $row.Surname
    $setParams = @{}

    if ($adUser.displayName -cne $hrDisplayName) {   # -cne: case-sensitive, so "mary jones" -> "Mary Jones" counts as drift
        $setParams['DisplayName'] = $hrDisplayName
    }
    if ($adUser.department -ne $row.Department) {
        $setParams['Department'] = $row.Department
    }

    if ($setParams.Count -eq 0) {
        $stats.Unchanged++
        continue
    }

    $changeList = ($setParams.Keys | ForEach-Object { '{0} -> "{1}"' -f $_, $setParams[$_] }) -join ', '
    if ($PSCmdlet.ShouldProcess($adUser.SamAccountName, "Update from HR: $changeList")) {
        Set-ADUser -Identity $adUser.DistinguishedName @setParams
        Write-SyncLog "UPDATED: $($adUser.SamAccountName) (EmployeeId $($row.EmployeeId)) - $changeList."
        $stats.Updated++
    }
}

Write-SyncLog ("=== Sync run finished. Disabled: {0}  Updated: {1}  Unchanged: {2}  NoMatch: {3} ===" -f `
        $stats.Disabled, $stats.Updated, $stats.Unchanged, $stats.NoMatch)

# Return a summary object so a scheduled-task wrapper (or a human) can act on the result.
[PSCustomObject]@{
    CsvPath   = $CsvPath
    LogPath   = $LogPath
    RowsRead  = $hrRows.Count
    Disabled  = $stats.Disabled
    Updated   = $stats.Updated
    Unchanged = $stats.Unchanged
    NoMatch   = $stats.NoMatch
}
#endregion Apply

# --- Example invocation (uncomment to run) ---
# .\Sync-HRUserToAD.ps1 -CsvPath C:\HRDrop\hr-export.csv -LogPath C:\Logs\hr-sync.log -WhatIf
