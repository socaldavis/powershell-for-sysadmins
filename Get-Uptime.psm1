# =====================================================================================
#  PC-Addicts PowerShell Library  —  Get-Uptime
#  ------------------------------------------------------------------------------------
#  FINE PRINT / USE AT YOUR OWN RISK
#  Provided as-is, as a teaching example, with NO WARRANTY of any kind, express or
#  implied. Read it, understand exactly what it does, and TEST IT IN A LAB before you
#  run it anywhere that matters. You are solely responsible for what it does on your
#  systems. Not affiliated with or representative of any employer.
#  ------------------------------------------------------------------------------------
#  Original by Chris Davis. Sanitized and modernized from Get-WmiObject to
#  Get-CimInstance. Read-only: queries a machine, changes nothing.
# =====================================================================================

function Get-Uptime {
    <#
    .SYNOPSIS
        Get the uptime and last boot time of one or more computers.
    .DESCRIPTION
        Checks connectivity first, then reports system name, last boot time, and
        uptime for each computer. Skips (with a warning) any box it can't reach.
        Accepts pipeline input. Read-only — it makes no changes to the target.
    .PARAMETER ComputerName
        One or more computer names to check.
    .EXAMPLE
        Get-Uptime SERVER-1
    .EXAMPLE
        Get-Content .\names.txt | Get-Uptime
    .EXAMPLE
        (Get-ADComputer -Filter * -SearchBase "OU=Servers,DC=corp,DC=example,DC=lab").Name | Get-Uptime
    .NOTES
        Requires WinRM/WMI reachable on the target and rights to query it.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ComputerName
    )
    process {
        foreach ($computer in $ComputerName) {
            try {
                Get-CimInstance -ClassName Win32_BIOS -ComputerName $computer -ErrorAction Stop | Out-Null
            } catch {
                Write-Warning "$computer : could not connect"
                continue
            }
            Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $computer |
                Select-Object @{ n = 'System';   e = { $_.CSName } },
                              @{ n = 'LastBoot'; e = { $_.LastBootUpTime } },
                              @{ n = 'Uptime';   e = { (Get-Date) - $_.LastBootUpTime } }
        }
    }
}
