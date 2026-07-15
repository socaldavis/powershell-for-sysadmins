<#
    PCAddicts.Tools.psm1 — TEMPLATE personal module: one module, many functions, tab-completion
    PC-Addicts script library · github.com/socaldavis/powershell-for-sysadmins
    Rewritten, generalized version of a script shown in the "Sr. SysAdmin PowerShell" series.

    THE PATTERN
    -----------
    Instead of a pile of loose .ps1 files, keep your personal helper functions in ONE
    module. Install it where PowerShell auto-loads modules and every function is
    available (and tab-completes) in every console, no profile line required:

        $env:USERPROFILE\Documents\WindowsPowerShell\Modules\PCAddicts.Tools\PCAddicts.Tools.psm1

    Rules that make auto-loading work:
      * the FOLDER name and the .psm1 name must match ("PCAddicts.Tools" here),
      * PS7 note: PowerShell 7 looks in ...\Documents\PowerShell\Modules\ instead.

    THE TAB-COMPLETE TRICK
    ----------------------
    Every function gets your initials as a noun prefix (CD = the author's initials —
    swap in yours). Type  Get-CD  and press Tab: PowerShell cycles through only YOUR
    functions. Your whole toolbox is discoverable without remembering a single name,
    and you'll never collide with a built-in or vendor cmdlet.

    ADDING YOUR OWN FUNCTIONS
    -------------------------
    1. Copy one of the functions below as a skeleton (keep the comment-based help —
       future-you runs Get-Help too).
    2. Name it Verb-XXNoun with an approved verb (Get-Verb lists them) and YOUR initials.
    3. Add its name to Export-ModuleMember at the bottom of this file.
    4. Reload:  Import-Module PCAddicts.Tools -Force
#>

function Get-CDUptime {
<#
.SYNOPSIS
    How long has this box been up? (thin CIM wrapper)

.DESCRIPTION
    Queries Win32_OperatingSystem over CIM and returns the last boot time plus a
    live uptime for one or more computers. This is the classic "thin wrapper"
    personal-module function: it saves you retyping a query you run daily, and the
    CD prefix makes it tab-completable (Get-CD<tab>).

    Uses Get-CimInstance (WinRM), not the old DCOM Get-WmiObject — Get-WmiObject is
    gone in PowerShell 7, so this works in both 5.1 and 7.

.PARAMETER ComputerName
    One or more computer names to query. Defaults to the local machine.
    Accepts pipeline input, so you can feed it server lists.

.EXAMPLE
    PS> Get-CDUptime

    Uptime of the machine you're sitting at.

.EXAMPLE
    PS> Get-CDUptime -ComputerName FS01, DC01

    "Did those servers really reboot after patching last night?"

.EXAMPLE
    PS> Get-Content C:\Scripts\servers.txt | Get-CDUptime | Sort-Object UptimeDays -Descending

    Uptime for a whole server list, longest-running first.

.NOTES
    Part of the PC-Addicts script library — github.com/socaldavis/powershell-for-sysadmins
    — demonstrated on youtube.com/@PCAddicts. Test in a lab before production.
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME
    )

    process {
        foreach ($computer in $ComputerName) {
            try {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem `
                                      -ComputerName $computer -ErrorAction Stop
            }
            catch {
                # One dead box shouldn't kill a 50-server sweep — warn and move on.
                Write-Warning "Could not query $computer — $($_.Exception.Message)"
                continue
            }

            $uptime = (Get-Date) - $os.LastBootUpTime

            # Objects out, not text — so Sort/Where/Export-Csv all work downstream.
            [PSCustomObject]@{
                ComputerName = $os.CSName
                LastBoot     = $os.LastBootUpTime
                UptimeDays   = [math]::Round($uptime.TotalDays, 1)
                Uptime       = '{0}d {1}h {2}m' -f $uptime.Days, $uptime.Hours, $uptime.Minutes
            }
        }
    }
}

function Get-CDLoggedOn {
<#
.SYNOPSIS
    Who is logged on to a machine? (thin quser wrapper)

.DESCRIPTION
    Runs the classic quser.exe against a computer and parses its fixed-width text
    into real objects. quser's output is fine for eyeballs but useless in a pipeline —
    wrapping it once in your personal module means you never parse it by hand again.

    Second example of the module pattern: initials prefix (Get-CD<tab>), objects out,
    warnings for machines that don't answer.

.PARAMETER ComputerName
    One or more computer names to check. Defaults to the local machine.
    Accepts pipeline input.

.EXAMPLE
    PS> Get-CDLoggedOn -ComputerName FS01

    "Can I reboot FS01, or is someone still on it?"

.EXAMPLE
    PS> Get-CDLoggedOn -ComputerName FS01, PRINT01 | Where-Object State -eq 'Disc'

    Find disconnected (abandoned) sessions worth logging off across a few servers.

.NOTES
    Part of the PC-Addicts script library — github.com/socaldavis/powershell-for-sysadmins
    — demonstrated on youtube.com/@PCAddicts. Test in a lab before production.

    quser needs the Remote Desktop Services "allow remote RPC" bits reachable on the
    target; a warning here usually means firewall, not "nobody logged on".
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = $env:COMPUTERNAME
    )

    process {
        foreach ($computer in $ComputerName) {
            # 2>&1 folds quser's stderr ("No User exists...") into output we can test,
            # instead of splattering red text on the console.
            $raw = & quser.exe /server:$computer 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "quser failed for $computer — $($raw | Select-Object -First 1)"
                continue
            }

            # Skip the header row; each remaining line is one session.
            foreach ($line in ($raw | Select-Object -Skip 1)) {
                # The leading '>' marks YOUR session — strip it so columns line up,
                # then split on runs of 2+ spaces (quser pads columns with spaces).
                $parts = ($line -replace '^>').Trim() -split '\s{2,}'

                # Disconnected sessions have an EMPTY session-name column, so the split
                # yields 5 fields instead of 6. Handle both shapes.
                if ($parts.Count -eq 6) {
                    $user, $session, $id, $state, $idle, $logon = $parts
                }
                elseif ($parts.Count -eq 5) {
                    $user, $id, $state, $idle, $logon = $parts
                    $session = ''
                }
                else {
                    Write-Warning "Unrecognized quser line on ${computer}: $line"
                    continue
                }

                [PSCustomObject]@{
                    ComputerName = $computer
                    UserName     = $user
                    SessionName  = $session
                    Id           = [int]$id
                    State        = $state
                    IdleTime     = $idle
                    LogonTime    = $logon
                }
            }
        }
    }
}

# =====================================================================================
# Export list — the module's public surface.
# Only names listed here are visible (and tab-completable) to the shell; anything not
# listed stays a private helper. Added a function above? Add its name here too.
# =====================================================================================
Export-ModuleMember -Function Get-CDUptime, Get-CDLoggedOn

# --- Example invocation (commented out so pasting this file does nothing) -------------
# Import-Module PCAddicts.Tools -Force; Get-CDUptime -ComputerName FS01
