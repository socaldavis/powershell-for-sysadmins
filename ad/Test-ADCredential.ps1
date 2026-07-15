<#
    Test-ADCredential.ps1 — validate a username/password pair against the domain
    PC-Addicts script library · github.com/socaldavis/powershell-for-sysadmins
    Rewritten, generalized version of a script shown in the "Sr. SysAdmin PowerShell" series.
#>

<#
.SYNOPSIS
    Checks whether a username + password combination is valid in the current domain.

.DESCRIPTION
    Uses .NET's System.DirectoryServices.AccountManagement — specifically
    PrincipalContext.ValidateCredentials() — to test a credential against the domain
    WITHOUT starting a new logon session, mapping a drive, or otherwise disturbing the
    caller's own session. Handy for "is this service account password right?" checks
    and for verifying a credential before feeding it to a long automation run.

    Does not require the RSAT / ActiveDirectory module — it's pure .NET, so it works
    on any domain-joined box.

    !! LOCKOUT WARNING !! A failed validation is a real failed logon attempt as far as
    the domain is concerned. Every $false result counts toward the account lockout
    threshold. Do NOT loop this over password guesses, and be careful testing accounts
    that may already have failed attempts on the books.

.PARAMETER Credential
    A PSCredential holding the username and password to test. If omitted, you're
    prompted (Get-Credential), which keeps the password out of your console history.
    Username can be plain ("jsmith") or DOMAIN\jsmith / jsmith@corp.example.lab.

.PARAMETER Domain
    Domain to validate against. Defaults to the machine's current domain via the
    USERDNSDOMAIN environment variable.

.EXAMPLE
    .\Test-ADCredential.ps1

    Prompts for a username and password, then reports whether they're valid.

.EXAMPLE
    $cred = Get-Credential -UserName svc-backup -Message 'Credential to verify'
    .\Test-ADCredential.ps1 -Credential $cred

    Tests a service-account credential you were handed before wiring it into a task.

.EXAMPLE
    (.\Test-ADCredential.ps1 -Credential $cred).Valid

    Grabs just the boolean for use in an if() statement.

.NOTES
    Part of the PC-Addicts script library — github.com/socaldavis/powershell-for-sysadmins
    — demonstrated on youtube.com/@PCAddicts. Test in a lab before production.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Domain = $env:USERDNSDOMAIN
)

process {
    # Prompting via Get-Credential (instead of a -Password string parameter) means the
    # password never appears in plain text on the command line or in history.
    if (-not $Credential) {
        $Credential = Get-Credential -Message "Credential to validate against $Domain"
    }

    if (-not $Domain) {
        throw 'No domain detected (USERDNSDOMAIN is empty). Pass -Domain, e.g. -Domain corp.example.lab.'
    }

    # Every failed check is a genuine bad-password event on the DC — say so loudly.
    Write-Warning 'Each FAILED test counts toward the account lockout threshold. Do not retry in a loop.'

    # Load the AccountManagement assembly. Add-Type is a no-op if it's already loaded,
    # so calling it every run is safe. (PS 5.1 and PS 7 both support this form.)
    Add-Type -AssemblyName System.DirectoryServices.AccountManagement

    # ValidateCredentials wants the bare username; strip any DOMAIN\ or @suffix decoration.
    $userName = $Credential.UserName -replace '^.*\\' -replace '@.*$'

    $context = $null
    try {
        # A PrincipalContext scoped to the Domain is the "front door" for validation —
        # no logon session is created on this machine, the DC just answers yes/no.
        $context = New-Object System.DirectoryServices.AccountManagement.PrincipalContext(
            [System.DirectoryServices.AccountManagement.ContextType]::Domain, $Domain)

        # GetNetworkCredential() exposes the plain-text password just long enough to
        # hand it to .NET; we never store it in a variable.
        $isValid = $context.ValidateCredentials($userName, $Credential.GetNetworkCredential().Password)

        [PSCustomObject]@{
            Username = $userName
            Domain   = $Domain
            Valid    = $isValid
            TestedAt = Get-Date
        }
    }
    finally {
        # Dispose the context even if validation threw — it holds an LDAP connection.
        if ($context) { $context.Dispose() }
    }
}

# --- Example invocation (uncomment to run) ---
# .\Test-ADCredential.ps1 -Domain corp.example.lab
