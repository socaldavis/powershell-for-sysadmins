<#
    Get-PendingReboot.ps1 — check computers for a pending reboot via the standard registry signals
    PC-Addicts script library · github.com/socaldavis/powershell-for-sysadmins
    Rewritten, generalized version of a script shown in the "Sr. SysAdmin PowerShell" series.
#>

function Get-PendingReboot {
    <#
    .SYNOPSIS
        Checks one or more computers for a pending reboot using the well-known registry locations.

    .DESCRIPTION
        Windows never gives you a single "reboot pending" flag — different subsystems each leave
        their own breadcrumb in the registry. This function checks the four standard signals:

          * Component Based Servicing  — HKLM:\...\Component Based Servicing\RebootPending key
          * Windows Update             — HKLM:\...\WindowsUpdate\Auto Update\RebootRequired key
          * Pending file renames       — PendingFileRenameOperations value under Session Manager
          * Pending computer rename    — ActiveComputerName differs from ComputerName

        Remote computers are checked with Invoke-Command (WinRM); the local computer is checked
        directly so the function works even when WinRM/remoting is not configured locally.
        Output is one object per computer with a boolean per signal plus an overall
        IsRebootPending, so you can filter a whole fleet down to the machines that need a bounce.

        Unreachable computers produce a warning and processing continues.

    .PARAMETER ComputerName
        One or more computer names to check. Accepts pipeline input (strings, or objects with a
        ComputerName property). Defaults to the local computer.

    .EXAMPLE
        PS> Get-PendingReboot -ComputerName FS01

        Shows all four reboot signals for FS01 plus the overall verdict.

    .EXAMPLE
        PS> 'DC01','FS01','PRINT01' | Get-PendingReboot | Where-Object IsRebootPending

        Checks three servers via the pipeline and returns only the ones that actually need a
        reboot — perfect after patch night.

    .NOTES
        These registry locations were popularized by Brian Wilhite's classic PendingReboot
        module (github.com/bcwilhite/PendingReboot) — this is an independent, simplified
        implementation written for teaching; use Brian's module for full coverage (SCCM, etc.).
        Part of the PC-Addicts script library — github.com/socaldavis/powershell-for-sysadmins
        — demonstrated on youtube.com/@PC-Addicts. Test in a lab before production.

        Requires WinRM on remote targets. PendingFileRenameOperations is the noisiest signal
        (installers set it constantly) — weigh it accordingly before mass-rebooting.
        Works in Windows PowerShell 5.1 and PowerShell 7.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME
    )

    begin {
        # One scriptblock, run locally or shipped over WinRM — same logic either way.
        $checkScript = {
            # Signal 1: CBS. The RebootPending KEY simply existing is the signal.
            $cbs = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'

            # Signal 2: Windows Update. Same pattern — key exists = reboot required.
            $wu = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'

            # Signal 3: files queued to be renamed/deleted at next boot. Here it's a VALUE
            # under an always-present key, so Test-Path won't work — read the property instead.
            $sessionMgr = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
                                           -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
            $pfro = [bool]($sessionMgr -and $sessionMgr.PendingFileRenameOperations)

            # Signal 4: computer was renamed but hasn't rebooted yet — the "active" name
            # still differs from the configured name until the next boot.
            $activeName = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -ErrorAction SilentlyContinue).ComputerName
            $pendingName = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -ErrorAction SilentlyContinue).ComputerName
            $rename = [bool]($activeName -and $pendingName -and ($activeName -ne $pendingName))

            [PSCustomObject]@{
                ComponentBasedServicing = $cbs
                WindowsUpdate           = $wu
                PendingFileRename       = $pfro
                PendingComputerRename   = $rename
            }
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose "Checking pending-reboot signals on $computer"
            try {
                if ($computer -in @($env:COMPUTERNAME, 'localhost', '127.0.0.1', '.')) {
                    # Local box: run directly so this works even without WinRM configured.
                    $result = & $checkScript
                }
                else {
                    $result = Invoke-Command -ComputerName $computer -ScriptBlock $checkScript `
                                             -ErrorAction Stop
                }

                [PSCustomObject]@{
                    ComputerName            = $computer
                    ComponentBasedServicing = $result.ComponentBasedServicing
                    WindowsUpdate           = $result.WindowsUpdate
                    PendingFileRename       = $result.PendingFileRename
                    PendingComputerRename   = $result.PendingComputerRename
                    IsRebootPending         = ($result.ComponentBasedServicing -or
                                               $result.WindowsUpdate -or
                                               $result.PendingFileRename -or
                                               $result.PendingComputerRename)
                }
            }
            catch {
                # Warn and keep going — one unreachable host shouldn't stop patch-night triage.
                Write-Warning "$computer — could not check pending reboot: $($_.Exception.Message)"
            }
        }
    }
}

# Get-PendingReboot -ComputerName 'DC01','FS01' | Where-Object IsRebootPending
