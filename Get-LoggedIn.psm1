# =====================================================================================
#  PC-Addicts PowerShell Library  —  Get-LoggedIn
#  ------------------------------------------------------------------------------------
#  FINE PRINT / USE AT YOUR OWN RISK
#  Provided as-is, as a teaching example, with NO WARRANTY of any kind, express or
#  implied. Read it, understand exactly what it does, and TEST IT IN A LAB before you
#  run it anywhere that matters. You are solely responsible for what it does on your
#  systems. Not affiliated with or representative of any employer.
#  ------------------------------------------------------------------------------------
#  Original by Chris Davis. Sanitized (no real host/domain names) and modernized from
#  Get-WmiObject to Get-CimInstance. Read-only: queries a machine, changes nothing.
# =====================================================================================

function Get-LoggedIn {
    <#
    .SYNOPSIS
        Return the user currently logged into a computer.
    .DESCRIPTION
        Query one or more computers (by name or IP) and return who is logged in.
        Accepts pipeline input, so you can feed it a text file or Get-ADComputer.
        Read-only — it makes no changes to the target.
    .PARAMETER ComputerName
        One or more computer names or IP addresses to query.
    .EXAMPLE
        Get-LoggedIn SERVER-1
    .EXAMPLE
        Get-LoggedIn SERVER-1, SERVER-2
    .EXAMPLE
        Get-Content .\names.txt | Get-LoggedIn
    .EXAMPLE
        Get-ADComputer -Filter * -SearchBase "CN=Computers,DC=corp,DC=example,DC=lab" |
            Select-Object @{ l = 'ComputerName'; e = { $_.Name } } | Get-LoggedIn
    .NOTES
        Returns the interactive (console) user via Win32_ComputerSystem.UserName.
        Requires WinRM/WMI reachable on the target and rights to query it.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ComputerName
    )
    process {
        foreach ($name in $ComputerName) {
            try {
                Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $name -ErrorAction Stop |
                    Select-Object @{ l = 'ComputerName'; e = { $_.Name } }, UserName
            } catch {
                Write-Warning "$name : could not connect ($($_.Exception.Message))"
            }
        }
    }
}
