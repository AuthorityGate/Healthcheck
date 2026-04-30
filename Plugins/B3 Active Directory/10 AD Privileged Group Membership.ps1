# Start of Settings
# End of Settings

$Title          = "AD Privileged Group Membership"
$Header         = "[count] member(s) in highly-privileged AD groups"
$Comments       = "Audits membership of Domain Admins, Enterprise Admins, Schema Admins, Account Operators, Server Operators, Backup Operators, Print Operators, DnsAdmins, and Group Policy Creator Owners. Excessive privileged-group membership = lateral-movement blast radius. Best practice: <= 5 named admins per group, no service accounts, no nested groups."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B3 Active Directory"
$Severity       = "P1"
$Recommendation = "Reduce direct membership to named human admins only. Move service accounts to specific delegated roles instead of blanket Domain Admin. Audit each member: is the account still active? Required? Following tier-zero hygiene (separate workstation, separate cred, MFA at logon)?"

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    [pscustomobject]@{ Note = 'ActiveDirectory PowerShell module not available. Install RSAT-AD-PowerShell.' }
    return
}
Import-Module ActiveDirectory -ErrorAction SilentlyContinue

# Build common -Server / -Credential splat from the AD tab's first row.
$_adArgs = @{}
$_adServer = if ($Global:ADServerFqdn) { $Global:ADServerFqdn } elseif ($Global:ADForestFqdn) { $Global:ADForestFqdn } else { $null }
if ($_adServer) { $_adArgs.Server = $_adServer }
if (Test-Path Variable:Global:ADCredential) { $_adArgs.Credential = $Global:ADCredential }

$privGroups = @('Domain Admins','Enterprise Admins','Schema Admins','Account Operators',
    'Server Operators','Backup Operators','Print Operators','DnsAdmins',
    'Group Policy Creator Owners','Cert Publishers','Protected Users')

foreach ($g in $privGroups) {
    try {
        $grp = Get-ADGroup -Filter "Name -eq '$g'" @_adArgs -ErrorAction SilentlyContinue
        if (-not $grp) { continue }
        $members = @(Get-ADGroupMember -Identity $grp -Recursive @_adArgs -ErrorAction SilentlyContinue)
        foreach ($m in $members) {
            $extra = $null
            try { $extra = Get-ADUser $m.SamAccountName -Properties LastLogonDate, PasswordLastSet, Enabled, AccountExpirationDate @_adArgs -ErrorAction SilentlyContinue } catch { }
            [pscustomobject]@{
                Group           = $g
                Member          = $m.SamAccountName
                MemberType      = $m.objectClass
                DN              = $m.DistinguishedName
                Enabled         = if ($extra) { [bool]$extra.Enabled } else { '' }
                LastLogon       = if ($extra -and $extra.LastLogonDate) { $extra.LastLogonDate.ToString('yyyy-MM-dd') } else { '' }
                PwdLastSet      = if ($extra -and $extra.PasswordLastSet) { $extra.PasswordLastSet.ToString('yyyy-MM-dd') } else { '' }
                ExpiresOn       = if ($extra -and $extra.AccountExpirationDate) { $extra.AccountExpirationDate.ToString('yyyy-MM-dd') } else { '(never)' }
            }
        }
    } catch { }
}

$TableFormat = @{
    Enabled    = { param($v,$row) if ($v -eq $false) { 'warn' } elseif ($v -eq $true) { 'ok' } else { '' } }
    MemberType = { param($v,$row) if ($v -eq 'computer') { 'warn' } else { '' } }
}
