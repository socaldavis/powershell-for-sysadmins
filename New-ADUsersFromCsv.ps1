# =====================================================================================
#  PC-Addicts PowerShell Library  —  New-ADUsersFromCsv
#  ------------------------------------------------------------------------------------
#  FINE PRINT / USE AT YOUR OWN RISK
#  Provided as-is, as a teaching example, with NO WARRANTY of any kind, express or
#  implied. This script CREATES Active Directory user accounts. Read it, understand
#  exactly what it does, and TEST IT IN A LAB. Run it with -WhatIf first and confirm
#  the results. You are solely responsible for what it does on your systems. Not
#  affiliated with or representative of any employer.
#  ------------------------------------------------------------------------------------
#  A clean, generic teaching version of the CSV-to-AD bulk import. (Chris's production
#  version does more — manager lookups, nickname handling, term dates — but this is the
#  safe starting point everyone can build on.) Uses the built-in ActiveDirectory module.
# =====================================================================================
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Bulk-create Active Directory users from a CSV file.
.DESCRIPTION
    Reads a CSV, and for each row creates an AD user (skipping any that already exist),
    setting a temporary password that must be changed at first logon. Supports -WhatIf.

    Expected CSV columns (header row required):
        FirstName,LastName,SamAccountName,Department,Title
    Example row:
        Ada,Lovelace,alovelace,Engineering,Analyst
.PARAMETER CsvPath
    Path to the CSV file.
.PARAMETER OUPath
    Distinguished name of the OU to create the users in.
.PARAMETER UpnSuffix
    UPN / email domain suffix, e.g. corp.example.lab.
.PARAMETER DefaultPassword
    Temporary password as a SecureString. If omitted, you'll be prompted (never hardcode it).
.EXAMPLE
    .\New-ADUsersFromCsv.ps1 -CsvPath .\newhires.csv -OUPath "OU=Staff,DC=corp,DC=example,DC=lab" -UpnSuffix corp.example.lab -WhatIf
.NOTES
    Lab-first. Every new account is created disabled-safe: enabled but flagged to change
    password at first logon. Review your CSV before running for real.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)][string]$CsvPath,
    [Parameter(Mandatory = $true)][string]$OUPath,
    [Parameter(Mandatory = $true)][string]$UpnSuffix,
    [System.Security.SecureString]$DefaultPassword
)

if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }
if (-not $DefaultPassword) { $DefaultPassword = Read-Host 'Temporary password for new accounts' -AsSecureString }

$users = Import-Csv -Path $CsvPath
$required = 'FirstName', 'LastName', 'SamAccountName'
$missing = $required | Where-Object { $_ -notin $users[0].PSObject.Properties.Name }
if ($missing) { throw "CSV is missing required column(s): $($missing -join ', ')" }

foreach ($user in $users) {
    $sam = $user.SamAccountName.Trim()
    if (-not $sam) { Write-Warning "Skipping row with blank SamAccountName ($($user.FirstName) $($user.LastName))"; continue }

    if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        Write-Warning "$sam already exists — skipping"
        continue
    }

    $params = @{
        Name                  = "$($user.FirstName) $($user.LastName)"
        GivenName             = $user.FirstName
        Surname               = $user.LastName
        SamAccountName        = $sam
        UserPrincipalName     = "$sam@$UpnSuffix"
        DisplayName           = "$($user.FirstName) $($user.LastName)"
        Path                  = $OUPath
        AccountPassword       = $DefaultPassword
        Enabled               = $true
        ChangePasswordAtLogon = $true
    }
    if ($user.Department) { $params['Department'] = $user.Department }
    if ($user.Title)      { $params['Title']      = $user.Title }

    if ($PSCmdlet.ShouldProcess($sam, 'Create AD user')) {
        try {
            New-ADUser @params -ErrorAction Stop
            Write-Host "Created $sam"
        } catch {
            Write-Warning "Failed to create $sam : $($_.Exception.Message)"
        }
    }
}
