#Requires -Modules ActiveDirectory
<#
    Copy-ADUser.ps1 — create a new AD user modeled on an existing "template" user
    PC-Addicts script library · github.com/socaldavis/powershell-for-sysadmins
    Rewritten, generalized version of a script shown in the "Sr. SysAdmin PowerShell" series.
#>

<#
.SYNOPSIS
    Creates a new AD user cloned from a template user — same OU, groups, and key attributes.

.DESCRIPTION
    The classic "make me another one like Bob" onboarding task, automated. Given an existing
    template user, this script creates a new account that:

      - lands in the SAME OU as the template
      - copies the key business attributes (department, title, office, manager, company)
      - joins the SAME security groups (except Domain Users, which is automatic)
      - gets a RANDOM initial password, flagged must-change-at-first-logon

    The random password is returned as a property of the output object so the helpdesk can
    hand it to the new hire. It is intentionally NOT written to any log — treat the console
    output as sensitive and clear it after use.

    Teaching point: copying group memberships is where clone scripts go wrong. If the
    template user is over-privileged, the clone is too. Pick clean, role-representative
    template accounts (or better: purpose-built template users per department).

.PARAMETER TemplateUser
    SamAccountName of the existing user to model the new account on, e.g. "jsmith".

.PARAMETER NewUserSamAccountName
    SamAccountName for the new account (max 20 characters — an old SAM-era limit AD still enforces).

.PARAMETER NewUserGivenName
    First name of the new user.

.PARAMETER NewUserSurname
    Last name of the new user.

.EXAMPLE
    .\Copy-ADUser.ps1 -TemplateUser jsmith -NewUserSamAccountName mjones -NewUserGivenName Mary -NewUserSurname Jones -WhatIf

    Shows what would be created — which OU, which groups — without creating anything.

.EXAMPLE
    $new = .\Copy-ADUser.ps1 -TemplateUser jsmith -NewUserSamAccountName mjones -NewUserGivenName Mary -NewUserSurname Jones
    $new.InitialPassword

    Creates the account and captures the object; the one-time password is in .InitialPassword.

.NOTES
    Part of the PC-Addicts script library — github.com/socaldavis/powershell-for-sysadmins
    — demonstrated on youtube.com/@PC-Addicts. Test in a lab before production.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TemplateUser,

    [Parameter(Mandatory)]
    [ValidateLength(1, 20)]   # sAMAccountName hard limit is 20 chars
    [string]$NewUserSamAccountName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$NewUserGivenName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$NewUserSurname
)

# --- Load the template, including the attributes we plan to copy -------------------
# -Properties is needed because Get-ADUser only returns a small default set.
$template = Get-ADUser -Identity $TemplateUser -Properties department, title, physicalDeliveryOfficeName, manager, company, memberOf

# Fail early and clearly if the new name is already taken — Get-ADUser throws if not
# found, which is exactly what we want here (hence the try/catch inversion).
try {
    $null = Get-ADUser -Identity $NewUserSamAccountName
    throw "An account named '$NewUserSamAccountName' already exists. Pick another SamAccountName."
}
catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    Write-Verbose "'$NewUserSamAccountName' is available."
}

# The template's OU is its DN minus the leading "CN=<name>," — the new user goes
# in the same place so it inherits the same GPO scoping.
$targetOu = ($template.DistinguishedName -split ',', 2)[1]
Write-Verbose "Template OU: $targetOu"

# --- Generate a random one-time password -------------------------------------------
# 16 chars drawn from a mixed set that satisfies typical complexity policy.
# (PS 5.1-friendly; on PS7+ you could also use Get-Random -Count over the array.)
$charset = ([char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%&*')
$rng = New-Object System.Random
$plainPassword = -join (1..16 | ForEach-Object { $charset[$rng.Next($charset.Length)] })
$securePassword = ConvertTo-SecureString -String $plainPassword -AsPlainText -Force

$displayName = '{0} {1}' -f $NewUserGivenName, $NewUserSurname
$upn = '{0}@corp.example.lab' -f $NewUserSamAccountName   # adjust to your UPN suffix

if ($PSCmdlet.ShouldProcess($NewUserSamAccountName, "Create user modeled on '$TemplateUser' in $targetOu")) {

    # --- Create the account ---------------------------------------------------------
    New-ADUser -Name $displayName `
        -SamAccountName $NewUserSamAccountName `
        -UserPrincipalName $upn `
        -GivenName $NewUserGivenName `
        -Surname $NewUserSurname `
        -DisplayName $displayName `
        -Path $targetOu `
        -Department $template.department `
        -Title $template.title `
        -Office $template.physicalDeliveryOfficeName `
        -Company $template.company `
        -Manager $template.manager `
        -AccountPassword $securePassword `
        -ChangePasswordAtLogon $true `
        -Enabled $true

    # --- Copy group memberships -----------------------------------------------------
    # memberOf holds group DNs. Domain Users isn't in memberOf (it's the primary
    # group), so it's covered automatically on account creation.
    foreach ($groupDn in $template.memberOf) {
        Add-ADGroupMember -Identity $groupDn -Members $NewUserSamAccountName
        Write-Verbose "Added to group: $groupDn"
    }

    # Return everything the helpdesk needs in one object. The password appears
    # ONLY here — it's must-change-at-logon, so it's a one-time secret.
    [PSCustomObject]@{
        SamAccountName    = $NewUserSamAccountName
        DisplayName       = $displayName
        UserPrincipalName = $upn
        OU                = $targetOu
        GroupsCopied      = @($template.memberOf).Count
        InitialPassword   = $plainPassword
        MustChangeAtLogon = $true
    }
}

# --- Example invocation (uncomment to run) ---
# .\Copy-ADUser.ps1 -TemplateUser jsmith -NewUserSamAccountName mjones -NewUserGivenName Mary -NewUserSurname Jones -WhatIf
