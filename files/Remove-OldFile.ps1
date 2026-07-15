<#
    Remove-OldFile.ps1 — retention cleanup: delete files older than N days (safely)
    PC-Addicts script library · github.com/socaldavis/powershell-for-sysadmins
    Rewritten, generalized version of a script shown in the "Sr. SysAdmin PowerShell" series.
#>

<#
.SYNOPSIS
    Deletes files under a path that are older than a retention window.

.DESCRIPTION
    Classic retention cleanup for backup folders, log directories, and export drops:
    remove everything under -Path whose LastWriteTime is older than -RetentionDays.
    Narrow it with -Filter (e.g. *.bak) and walk subfolders with -Recurse.

    Safety features — because this script deletes things:
      * SupportsShouldProcess with ConfirmImpact High: it prompts by default, honors
        -WhatIf, and needs -Confirm:$false for unattended runs.
      * Never follows reparse points (junctions/symlinks). A junction in a backup
        folder pointing at D:\Data should not get D:\Data cleaned out by accident,
        so recursion uses its own walker instead of Get-ChildItem -Recurse.
      * Outputs an object per file (path, age, size) showing what was — or with
        -WhatIf, would be — removed, so runs are auditable.

    Windows PowerShell 5.1 compatible. (PS7's Get-ChildItem has -FollowSymlink and
    smarter defaults around reparse points; we don't rely on either.)

.PARAMETER Path
    Root folder to clean. Must exist.

.PARAMETER RetentionDays
    Keep files newer than this many days; delete the rest. Default: 10.

.PARAMETER Filter
    Optional wildcard filter, e.g. *.bak or *.log. Default: all files.

.PARAMETER Recurse
    Also clean subfolders (skipping any junction/symlink directories).

.EXAMPLE
    PS> .\Remove-OldFile.ps1 -Path D:\Backups\SQL -Filter *.bak -RetentionDays 14 -Recurse -WhatIf

    ALWAYS do this first: shows exactly which .bak files older than 14 days would be
    deleted, without touching anything.

.EXAMPLE
    PS> powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Scripts\Remove-OldFile.ps1 -Path D:\Backups\SQL -Filter *.bak -RetentionDays 14 -Recurse -Confirm:$false

    Scheduled-task usage: run it unattended from Task Scheduler. -Confirm:$false is
    required because ConfirmImpact is High — without it the task would hang waiting
    for a prompt nobody will ever answer.

.NOTES
    Part of the PC-Addicts script library — github.com/socaldavis/powershell-for-sysadmins
    — demonstrated on youtube.com/@PC-Addicts. Test in a lab before production.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$Path,

    [ValidateRange(0, 36500)]
    [int]$RetentionDays = 10,

    [ValidateNotNullOrEmpty()]
    [string]$Filter = '*',

    [switch]$Recurse
)

process {
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    Write-Verbose "Removing '$Filter' files under $Path last written before $cutoff"

    # Our own breadth-first walk instead of Get-ChildItem -Recurse: on 5.1, -Recurse
    # happily descends INTO junctions and symlinked directories, which is exactly how
    # a cleanup script ends up eating data it was never pointed at.
    $reparseFlag = [System.IO.FileAttributes]::ReparsePoint
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue((Get-Item -Path $Path))

    while ($queue.Count -gt 0) {
        $folder = $queue.Dequeue()

        if ($Recurse) {
            foreach ($sub in Get-ChildItem -LiteralPath $folder.FullName -Directory -ErrorAction SilentlyContinue) {
                # Skip junction/symlink directories entirely — never follow them.
                if (-not ($sub.Attributes -band $reparseFlag)) {
                    $queue.Enqueue($sub)
                }
            }
        }

        $oldFiles = Get-ChildItem -LiteralPath $folder.FullName -Filter $Filter -File -ErrorAction SilentlyContinue |
            Where-Object {
                # Skip file-level reparse points too (symlinked files, OneDrive stubs).
                -not ($_.Attributes -band $reparseFlag) -and $_.LastWriteTime -lt $cutoff
            }

        foreach ($file in $oldFiles) {
            $target = "{0} (last written {1:yyyy-MM-dd}, {2:N2} MB)" -f $file.FullName, $file.LastWriteTime, ($file.Length / 1MB)

            # ShouldProcess is the -WhatIf/-Confirm gate; nothing is deleted unless it says go.
            if ($PSCmdlet.ShouldProcess($target, "Remove file")) {
                Remove-Item -LiteralPath $file.FullName -Force

                [PSCustomObject]@{
                    FullName      = $file.FullName
                    LastWriteTime = $file.LastWriteTime
                    AgeDays       = [int]((Get-Date) - $file.LastWriteTime).TotalDays
                    SizeMB        = [math]::Round($file.Length / 1MB, 2)
                    Removed       = $true
                }
            }
            elseif ($WhatIfPreference) {
                # In -WhatIf mode still emit the object, flagged Removed=$false,
                # so you can pipe a dry run to Export-Csv and review it.
                [PSCustomObject]@{
                    FullName      = $file.FullName
                    LastWriteTime = $file.LastWriteTime
                    AgeDays       = [int]((Get-Date) - $file.LastWriteTime).TotalDays
                    SizeMB        = [math]::Round($file.Length / 1MB, 2)
                    Removed       = $false
                }
            }
        }
    }
}

# Example (commented out so pasting this file does nothing):
# .\Remove-OldFile.ps1 -Path D:\Backups\SQL -Filter *.bak -RetentionDays 14 -Recurse -WhatIf
