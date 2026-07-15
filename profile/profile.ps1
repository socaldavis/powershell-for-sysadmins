<#
    profile.ps1 — TEMPLATE PowerShell profile for a working sysadmin
    PC-Addicts script library · github.com/socaldavis/powershell-for-sysadmins
    Rewritten, generalized version of a script shown in the "Sr. SysAdmin PowerShell" series.
#>

<#
.SYNOPSIS
    Template PowerShell profile: PATH, personal module, PSDrives, start folder, aliases.

.DESCRIPTION
    A profile is just a .ps1 that PowerShell dot-sources every time you open a console —
    it's where you make YOUR shell feel like yours. This template shows the pieces a
    working sysadmin actually uses:

        a) put a personal scripts folder on $env:PATH
        b) import a personal module (PCAddicts.Tools.psm1) so your functions tab-complete
        c) (optional) map PSDrives to paths you live in
        d) start every session in the folder you actually work from
        e) a couple of quality-of-life aliases
        f) (optional) transcript logging of everything you type

    Everything org-specific is a clearly-marked  <-- CHANGE ME  placeholder. Copy this
    file to $PROFILE, swap in your own paths, delete what you don't want.

    Windows PowerShell 5.1 path:  $HOME\Documents\WindowsPowerShell\profile.ps1
    PowerShell 7 path differs:    $HOME\Documents\PowerShell\profile.ps1
    (Run  $PROFILE  in each shell to see exactly where it wants the file.)

.EXAMPLE
    PS> Copy-Item .\profile.ps1 -Destination $PROFILE -Force
    PS> . $PROFILE

    Installs this template as your profile, then reloads it in the current session
    (new consoles pick it up automatically).

.EXAMPLE
    PS> notepad $PROFILE

    Opens your live profile for editing — do this every time you catch yourself
    typing the same setup command twice.

.NOTES
    Part of the PC-Addicts script library — github.com/socaldavis/powershell-for-sysadmins
    — demonstrated on youtube.com/@PCAddicts. Test in a lab before production.

    If profiles won't load, check your execution policy:  Get-ExecutionPolicy -List
    (RemoteSigned is the usual sysadmin setting.)
#>

[CmdletBinding()]
param()   # profiles take no parameters — this just keeps the library convention

# =====================================================================================
# (a) Personal scripts folder on PATH
#     WHY: anything in this folder (.ps1, .exe, .bat) runs by name from ANY directory,
#     exactly like a built-in command. This is the cheapest automation win there is.
# =====================================================================================
$myScripts = 'C:\Scripts'                                  # <-- CHANGE ME
if ((Test-Path $myScripts) -and ($env:PATH -notlike "*$myScripts*")) {
    # Only for THIS session — the profile re-adds it every launch, so the machine-wide
    # PATH stays clean.
    $env:PATH += ";$myScripts"
}

# =====================================================================================
# (b) Import your personal module
#     WHY: one module holding all your custom functions means they load together and
#     TAB-COMPLETE. With an initials prefix (Get-CD<tab>) you can cycle through your
#     whole toolbox without remembering a single exact name.
#     If the module lives in $env:USERPROFILE\Documents\WindowsPowerShell\Modules\
#     PCAddicts.Tools\, PowerShell auto-loads it on first use anyway — the explicit
#     import just makes it available (and any load error visible) immediately.
# =====================================================================================
if (Get-Module -ListAvailable -Name 'PCAddicts.Tools') {   # <-- CHANGE ME (your module name)
    Import-Module 'PCAddicts.Tools'
}
else {
    Write-Warning 'Personal module PCAddicts.Tools not found — see PCAddicts.Tools.psm1 for install path.'
}

# =====================================================================================
# (c) OPTIONAL: PSDrives for the paths you live in
#     WHY: 'cd S:' beats typing a UNC path forty times a day, and unlike 'net use'
#     these are session-only — nothing sticks to the machine.
#     Uncomment and adjust. (-Persist makes them real mapped drives Explorer can see;
#     leave it off to keep them PowerShell-only.)
# =====================================================================================
# New-PSDrive -Name O -PSProvider FileSystem -Root "$env:OneDrive\Documents" | Out-Null   # <-- CHANGE ME
# New-PSDrive -Name S -PSProvider FileSystem -Root '\\FS01\Shared'           | Out-Null   # <-- CHANGE ME

# =====================================================================================
# (d) Start where you actually work
#     WHY: consoles open in $HOME or system32 by default; you probably never work there.
# =====================================================================================
if (Test-Path $myScripts) {
    Set-Location $myScripts                                # <-- CHANGE ME if you start elsewhere
}

# =====================================================================================
# (e) Aliases — tiny, but you use them hundreds of times a week
#     WHY: an alias is for YOUR fingers; interactive-only. In shared scripts always
#     spell out full cmdlet names so they read on camera / in code review.
# =====================================================================================
# 'np <file>' opens a file in Notepad++ (point at plain notepad.exe if you don't have it).
Set-Alias -Name np -Value 'C:\Program Files\Notepad++\notepad++.exe'   # <-- CHANGE ME
# 'gh' = quick command-history search:  gh acl  → every command you've run mentioning acl.
function gh { param([string]$Pattern) Get-History | Where-Object CommandLine -like "*$Pattern*" }

# =====================================================================================
# (f) OPTIONAL: transcript logging
#     WHY: a text log of every command and its output, per session — gold for change
#     records and for "what exactly did I run at 2 AM?" Uncomment to enable.
#     PS7 note: PS7 supports -UseMinimalHeader; 5.1 does not.
# =====================================================================================
# $transcriptDir = 'C:\Scripts\Transcripts'                # <-- CHANGE ME
# if (-not (Test-Path $transcriptDir)) { New-Item -Path $transcriptDir -ItemType Directory | Out-Null }
# Start-Transcript -Path (Join-Path $transcriptDir ("PS_{0:yyyyMMdd_HHmmss}.txt" -f (Get-Date))) | Out-Null

# --- Example invocation (commented out so pasting this file does nothing) -------------
# Copy-Item .\profile.ps1 -Destination $PROFILE -Force; . $PROFILE
