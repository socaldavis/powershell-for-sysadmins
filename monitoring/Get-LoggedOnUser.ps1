<#
    Get-LoggedOnUser.ps1 — report who is logged on to one or more computers, as real objects
    PC-Addicts script library · github.com/socaldavis/powershell-for-sysadmins
    Rewritten, generalized version of a script shown in the "Sr. SysAdmin PowerShell" series.
#>

function Get-LoggedOnUser {
    <#
    .SYNOPSIS
        Gets the users logged on to one or more computers by parsing quser.exe output into objects.

    .DESCRIPTION
        quser.exe (a.k.a. "query user") is the classic way to see interactive sessions, but it
        returns plain text. This function runs quser against each target computer and converts
        every session line into a PSCustomObject you can sort, filter, and export.

        It handles terminal servers / RDS session hosts with many simultaneous sessions, and it
        handles disconnected sessions (which quser prints with a BLANK session-name column —
        the usual thing that breaks naive parsers).

        Unreachable computers produce a warning and processing continues with the next computer,
        so one dead host never kills a big pipeline run.

    .PARAMETER ComputerName
        One or more computer names to query. Accepts pipeline input (strings, or objects with a
        ComputerName property such as Get-ADComputer output piped through Select-Object).
        Defaults to the local computer.

    .EXAMPLE
        PS> Get-LoggedOnUser -ComputerName FS01

        Shows every session on file server FS01, including disconnected ones.

    .EXAMPLE
        PS> 'DC01','FS01','PRINT01' | Get-LoggedOnUser | Where-Object State -eq 'Active'

        Queries three servers via the pipeline and keeps only the active sessions.

    .EXAMPLE
        PS> Get-LoggedOnUser -ComputerName TS01 | Sort-Object LogonTime | Format-Table

        Lists all sessions on a terminal server, oldest logon first.

    .NOTES
        Part of the PC-Addicts script library — github.com/socaldavis/powershell-for-sysadmins
        — demonstrated on youtube.com/@PCAddicts. Test in a lab before production.

        Requires the "Remote Desktop Services" RPC ports to be reachable on the target
        (quser uses RPC, not WinRM). Works in Windows PowerShell 5.1 and PowerShell 7.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME
    )

    process {
        foreach ($computer in $ComputerName) {
            Write-Verbose "Querying sessions on $computer"

            # quser is an .exe, not a cmdlet: errors go to stderr and $LASTEXITCODE,
            # so we redirect stream 2 into the output and inspect the exit code ourselves.
            $raw = quser.exe /server:$computer 2>&1

            if ($LASTEXITCODE -ne 0) {
                $message = ($raw | Out-String).Trim()
                if ($message -match 'No User exists') {
                    # Nobody logged on is a normal, useful answer — not an error.
                    Write-Verbose "$computer — no users are logged on."
                }
                else {
                    # Unreachable / access denied: warn and move on to the next computer.
                    Write-Warning "$computer — could not query sessions: $message"
                }
                continue
            }

            # Skip the header row; every remaining line is one session.
            foreach ($line in ($raw | Select-Object -Skip 1)) {

                # Collapse runs of 2+ spaces to a single delimiter. The logon timestamp
                # ("7/15/2026 8:03 AM") survives because its parts are one space apart.
                $fields = ($line.Trim() -replace '\s{2,}', ',').Split(',')

                # Disconnected sessions print a BLANK session-name column, so the same
                # line format can split into 5 fields (disc) or 6 fields (active).
                if ($fields.Count -eq 5) {
                    $userName, $sessionName          = $fields[0], ''
                    $sessionId, $state               = $fields[1], $fields[2]
                    $idleTime, $logonTimeRaw         = $fields[3], $fields[4]
                }
                else {
                    $userName, $sessionName          = $fields[0], $fields[1]
                    $sessionId, $state               = $fields[2], $fields[3]
                    $idleTime, $logonTimeRaw         = $fields[4], $fields[5]
                }

                # quser marks the session you ran it from with a leading ">".
                $userName = $userName.TrimStart('>')

                # Try to give callers a real [datetime]; fall back to the raw text if the
                # OS locale prints something .NET can't parse.
                try   { $logonTime = [datetime]$logonTimeRaw }
                catch { $logonTime = $logonTimeRaw }

                [PSCustomObject]@{
                    ComputerName = $computer
                    UserName     = $userName
                    SessionName  = $sessionName
                    SessionId    = [int]$sessionId
                    State        = $state
                    IdleTime     = $idleTime
                    LogonTime    = $logonTime
                }
            }
        }
    }
}

# Get-LoggedOnUser -ComputerName 'FS01','DC01' -Verbose
