<#
    Get-Uptime.ps1 — report last boot time and uptime for one or more computers via CIM
    PC-Addicts script library · github.com/socaldavis/powershell-for-sysadmins
    Rewritten, generalized version of a script shown in the "Sr. SysAdmin PowerShell" series.
#>

function Get-Uptime {
    <#
    .SYNOPSIS
        Gets last boot time and current uptime for one or more computers.

    .DESCRIPTION
        Reads Win32_OperatingSystem.LastBootUpTime over CIM (WinRM) and turns it into a
        friendly object: when the machine last booted, uptime as a proper [timespan] you can
        sort on, and uptime in days rounded for humans.

        Unreachable computers produce a warning and processing continues, so you can safely
        point this at a whole OU worth of servers.

        PS7 note: PowerShell 7 ships a built-in Get-Uptime, but it is LOCAL-ONLY — this
        function exists for the remote, fleet-wide case (and shadows the built-in when loaded).

    .PARAMETER ComputerName
        One or more computer names to query. Accepts pipeline input (strings, or objects with a
        ComputerName property). Defaults to the local computer.

    .EXAMPLE
        PS> Get-Uptime -ComputerName DC01

        Shows when DC01 last booted and how long it has been up.

    .EXAMPLE
        PS> 'DC01','FS01','PRINT01' | Get-Uptime | Sort-Object Uptime -Descending

        Queries three servers via the pipeline and lists the longest-running box first —
        handy for spotting servers that missed their patch-window reboot.

    .NOTES
        Part of the PC-Addicts script library — github.com/socaldavis/powershell-for-sysadmins
        — demonstrated on youtube.com/@PC-Addicts. Test in a lab before production.

        Requires WinRM on remote targets (Get-CimInstance -ComputerName uses WSMan).
        Works in Windows PowerShell 5.1 and PowerShell 7.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME
    )

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose "Querying uptime on $computer"
            try {
                # -ErrorAction Stop turns connection failures into catchable exceptions
                # so one dead host can't slip through as a silent non-terminating error.
                $os = Get-CimInstance -ClassName Win32_OperatingSystem `
                                      -ComputerName $computer -ErrorAction Stop

                # Get-CimInstance already returns LastBootUpTime as a [datetime] —
                # no ugly WMI date-string conversion needed (that was the old Get-WmiObject).
                $uptime = (Get-Date) - $os.LastBootUpTime

                [PSCustomObject]@{
                    ComputerName = $computer
                    LastBoot     = $os.LastBootUpTime
                    Uptime       = $uptime
                    UptimeDays   = [math]::Round($uptime.TotalDays, 1)
                }
            }
            catch {
                # Warn and keep going — the rest of the fleet still gets checked.
                Write-Warning "$computer — could not read uptime: $($_.Exception.Message)"
            }
        }
    }
}

# Get-Uptime -ComputerName 'DC01','FS01' -Verbose
