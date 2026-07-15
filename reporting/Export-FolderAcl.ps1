<#
    Export-FolderAcl.ps1 — audit NTFS folder permissions to a CSV
    PC-Addicts script library · github.com/socaldavis/powershell-for-sysadmins
    Rewritten, generalized version of a script shown in the "Sr. SysAdmin PowerShell" series.
#>

<#
.SYNOPSIS
    Walks a folder tree and exports every folder's NTFS permissions (ACL) to a CSV.

.DESCRIPTION
    Starting at -Path, this script collects the Access Control List of the root folder and
    every subfolder (optionally limited by -Depth), then flattens each Access Control Entry
    into one CSV row: folder path, identity, rights, Allow/Deny, and whether the entry is
    inherited or set explicitly on that folder.

    Folders the running account cannot read are skipped with a warning — the audit keeps
    going instead of dying halfway through a big file share. Run it from an account with
    read access to as much of the tree as possible (audits are only as good as your access).

    The rows are also written to the pipeline, so you can filter/sort them in the same
    command if you want more than just the CSV.

.PARAMETER Path
    Root folder to audit. Local path (D:\Data) or UNC path (\\FS01\Shared) both work.

.PARAMETER Depth
    Optional. How many levels of subfolders to descend below -Path.
    0 = the root folder only. Omit the parameter to walk the entire tree.

.PARAMETER OutputCsv
    Path of the CSV file to create (overwritten if it already exists).

.EXAMPLE
    PS> .\Export-FolderAcl.ps1 -Path \\FS01\Shared -OutputCsv C:\Reports\FS01-Shared-acl.csv

    Audits the whole \\FS01\Shared file share and writes every ACE to the CSV.
    Great "who can actually touch this share?" evidence before a permissions cleanup.

.EXAMPLE
    PS> .\Export-FolderAcl.ps1 -Path \\FS01\Shared -Depth 2 -OutputCsv C:\Reports\top-level-acl.csv

    Only goes two folder levels deep — usually where the explicit (non-inherited)
    permissions live on a well-run share, and much faster on huge trees.

.EXAMPLE
    PS> .\Export-FolderAcl.ps1 -Path D:\Data -OutputCsv C:\Reports\data-acl.csv |
            Where-Object { -not $_.IsInherited }

    Full export to CSV, but on screen show only the explicit ACEs — the ones somebody
    set by hand and you probably want to ask questions about.

.NOTES
    Part of the PC-Addicts script library — github.com/socaldavis/powershell-for-sysadmins
    — demonstrated on youtube.com/@PCAddicts. Test in a lab before production.

    Windows PowerShell 5.1 compatible. Read-only against the folder tree; the only thing
    it writes is the CSV.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Path,

    # Optional recursion limit. [int] so a typo like -Depth two fails fast.
    [ValidateRange(0, [int]::MaxValue)]
    [int]$Depth,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputCsv
)

# Fail fast if the root itself is wrong — no point warning our way through a bad path.
if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "Path not found or not a folder: $Path"
}

# --- Build the folder list -----------------------------------------------------------
# We audit the root folder itself PLUS its subfolders. -Depth implies recursion in
# PowerShell 5+, so we only add -Recurse when no depth limit was given.
$gciParams = @{
    LiteralPath   = $Path
    Directory     = $true
    ErrorAction   = 'SilentlyContinue'   # don't die on an unreadable branch...
    ErrorVariable = 'gciErrors'          # ...but remember it so we can warn below
}
if ($PSBoundParameters.ContainsKey('Depth')) {
    $gciParams['Depth'] = $Depth
}
else {
    $gciParams['Recurse'] = $true
}

Write-Verbose "Enumerating folders under $Path ..."
$folders = @(Get-Item -LiteralPath $Path) + @(Get-ChildItem @gciParams)

# Surface every branch the enumeration couldn't get into — skipped, not fatal.
foreach ($err in $gciErrors) {
    Write-Warning "Skipped (could not enumerate): $($err.TargetObject)"
}

Write-Verbose "Reading ACLs on $($folders.Count) folder(s) ..."

# --- Read each folder's ACL ----------------------------------------------------------
$report = foreach ($folder in $folders) {
    try {
        # Get-Acl needs read access to the security descriptor; that can fail even
        # when the folder listed fine, so it gets its own try/catch.
        $acl = Get-Acl -LiteralPath $folder.FullName -ErrorAction Stop
    }
    catch {
        Write-Warning "Skipped (could not read ACL): $($folder.FullName) — $($_.Exception.Message)"
        continue
    }

    # One CSV row per Access Control Entry, not per folder — that's what makes the
    # output filterable ("show me every Deny", "show me everything not inherited").
    foreach ($ace in $acl.Access) {
        [PSCustomObject]@{
            FolderPath  = $folder.FullName
            Identity    = $ace.IdentityReference.Value
            Rights      = $ace.FileSystemRights.ToString()
            AccessType  = $ace.AccessControlType.ToString()   # Allow / Deny
            IsInherited = $ace.IsInherited                    # $false = set explicitly here
            Owner       = $acl.Owner
        }
    }
}

# Export everything, and pass the rows down the pipeline for ad-hoc filtering.
$report | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
Write-Verbose "Wrote $(@($report).Count) ACL entries to $OutputCsv"
$report

# --- Example invocation (commented out so pasting this file does nothing) -------------
# .\Export-FolderAcl.ps1 -Path \\FS01\Shared -OutputCsv C:\Reports\FS01-Shared-acl.csv -Verbose
