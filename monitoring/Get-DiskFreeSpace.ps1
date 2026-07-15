<#
    Get-DiskFreeSpace.ps1 — free disk space for local/remote computers, with a low-space filter
    PC-Addicts script library · github.com/socaldavis/powershell-for-sysadmins
    Rewritten, generalized version of a script shown in the "Sr. SysAdmin PowerShell" series.
#>

function Get-DiskFreeSpace {
    <#
    .SYNOPSIS
        Gets free space on fixed disks for one or more computers, in human-friendly numbers.

    .DESCRIPTION
        Queries Win32_LogicalDisk over CIM (WinRM) for fixed disks only (DriveType 3 — no
        CD-ROMs, no mapped drives) and returns one object per drive with size, free space, and
        free percentage already rounded to sane, on-screen-friendly values.

        Use -MinimumFreePercent to flip it from "report everything" into an alerting tool:
        only disks BELOW the threshold are returned, so an empty result means all clear —
        ideal for a scheduled task that only emails when something comes back.

        Unreachable computers produce a warning and processing continues.

    .PARAMETER ComputerName
        One or more computer names to query. Accepts pipeline input (strings, or objects with a
        ComputerName property). Defaults to the local computer.

    .PARAMETER MinimumFreePercent
        Alert threshold, 1-100. When set, only disks whose free percentage is below this value
        are returned. When omitted, every fixed disk is returned.

    .EXAMPLE
        PS> Get-DiskFreeSpace -ComputerName FS01

        Reports every fixed disk on file server FS01 with size, free GB, and free percent.

    .EXAMPLE
        PS> 'DC01','FS01','PRINT01' | Get-DiskFreeSpace -MinimumFreePercent 15

        Checks three servers via the pipeline and returns ONLY drives under 15% free —
        nothing back means nothing to worry about.

    .NOTES
        Part of the PC-Addicts script library — github.com/socaldavis/powershell-for-sysadmins
        — demonstrated on youtube.com/@PCAddicts. Test in a lab before production.

        Requires WinRM on remote targets (Get-CimInstance -ComputerName uses WSMan).
        Works in Windows PowerShell 5.1 and PowerShell 7.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$MinimumFreePercent
    )

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose "Querying fixed disks on $computer"
            try {
                # DriveType=3 filters to local fixed disks server-side — cheaper than
                # pulling every drive back and filtering in PowerShell.
                $disks = Get-CimInstance -ClassName Win32_LogicalDisk `
                                         -Filter 'DriveType = 3' `
                                         -ComputerName $computer -ErrorAction Stop

                foreach ($disk in $disks) {
                    # Guard against a 0-byte Size (rare, but divide-by-zero kills the run).
                    if (-not $disk.Size) { continue }

                    $freePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)

                    # Alert mode: with a threshold set, healthy disks are skipped entirely
                    # so the output IS the problem list.
                    if ($PSBoundParameters.ContainsKey('MinimumFreePercent') -and
                        $freePercent -ge $MinimumFreePercent) {
                        continue
                    }

                    [PSCustomObject]@{
                        ComputerName = $computer
                        Drive        = $disk.DeviceID
                        SizeGB       = [math]::Round($disk.Size / 1GB, 1)
                        FreeGB       = [math]::Round($disk.FreeSpace / 1GB, 1)
                        FreePercent  = $freePercent
                    }
                }
            }
            catch {
                # Warn and keep going — the rest of the fleet still gets checked.
                Write-Warning "$computer — could not query disks: $($_.Exception.Message)"
            }
        }
    }
}

# Get-DiskFreeSpace -ComputerName 'FS01','DC01' -MinimumFreePercent 20
