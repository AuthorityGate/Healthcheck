# Start of Settings
$MaxRows = 200
# End of Settings

$Title          = 'AD Service Account SPN Inventory'
$Header         = 'Every account with one or more SPNs (group MSA, kMSA, regular)'
$Comments       = 'Accounts with ServicePrincipalNames are Kerberos service principals. AS-REP / Kerberoast risk: every user-class account with an SPN can be Kerberoasted offline if its password is weak. Group Managed Service Accounts (gMSA) auto-rotate; regular user accounts do NOT.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = 'B3 Active Directory'
$Severity       = 'P2'
$Recommendation = "Move every service-account-with-SPN to a gMSA OR enforce a 25+ character password rotated quarterly. Ensure 'This account supports Kerberos AES 128/256 bit encryption' is checked. Audit SPNs for duplicates (Get-ADObject -Filter {servicePrincipalName -ne `$null} | Group-Object servicePrincipalName)."

if (-not (Test-Path Variable:Global:ADForestFqdn) -or -not $Global:ADForestFqdn) { return }
try { Import-Module ActiveDirectory -ErrorAction Stop } catch { return }

$adArgs = @{ Server = $(if ($Global:ADServerFqdn) { $Global:ADServerFqdn } else { $Global:ADForestFqdn }) }
if (Test-Path Variable:Global:ADCredential) { $adArgs.Credential = $Global:ADCredential }

try {
    $forest = Get-ADForest -Identity $Global:ADForestFqdn @adArgs -ErrorAction Stop
    foreach ($d in $forest.Domains) {
        # Regular user accounts with SPN
        $u = @{ Filter='(servicePrincipalName -ne "$null")'; Properties=@('servicePrincipalName','PasswordLastSet','PasswordNeverExpires','msDS-SupportedEncryptionTypes','Enabled','LastLogonTimestamp','Description'); Server=$d; ErrorAction='SilentlyContinue' }
        if (Test-Path Variable:Global:ADCredential) { $u.Credential = $Global:ADCredential }
        $users = @(Get-ADUser @u | Select-Object -First $MaxRows)
        foreach ($user in $users) {
            $spns = @($user.servicePrincipalName)
            $pwAge = if ($user.PasswordLastSet) { [int]((Get-Date) - $user.PasswordLastSet).TotalDays } else { 'unknown' }
            $enc = $user.'msDS-SupportedEncryptionTypes'
            $encDesc = if ($enc) { switch ($enc) {0{'(default)'} 4{'RC4 only - WEAK'} 24{'AES 128+256'} 28{'AES 128+256+RC4'} default { "flags=$enc" } } } else { '(default)' }
            $status = if (-not $user.Enabled) { 'DISABLED' }
                      elseif ($pwAge -ne 'unknown' -and [int]$pwAge -gt 365) { "STALE PASSWORD ($pwAge d)" }
                      elseif ($encDesc -match 'RC4 only') { 'WEAK ENCRYPTION (RC4)' }
                      elseif ($user.PasswordNeverExpires) { 'PASSWORD NEVER EXPIRES' }
                      else { 'OK' }
            [pscustomobject]@{
                Domain          = $d
                AccountClass    = 'User'
                SamAccountName  = $user.SamAccountName
                SPNCount        = $spns.Count
                FirstSPN        = if ($spns.Count -gt 0) { $spns[0] } else { '' }
                PasswordAgeDays = $pwAge
                Encryption      = $encDesc
                NeverExpires    = $user.PasswordNeverExpires
                Enabled         = $user.Enabled
                Status          = $status
            }
        }

        # gMSA accounts (auto-rotating - lower risk)
        try {
            $g = @{ Filter='*'; Properties=@('servicePrincipalName','msDS-ManagedPassword','PasswordLastSet','Enabled'); Server=$d; ErrorAction='SilentlyContinue' }
            if (Test-Path Variable:Global:ADCredential) { $g.Credential = $Global:ADCredential }
            $gmsas = @(Get-ADServiceAccount @g)
            foreach ($gmsa in $gmsas) {
                $spns = @($gmsa.servicePrincipalName)
                [pscustomobject]@{
                    Domain          = $d
                    AccountClass    = 'gMSA'
                    SamAccountName  = $gmsa.SamAccountName
                    SPNCount        = $spns.Count
                    FirstSPN        = if ($spns.Count -gt 0) { $spns[0] } else { '' }
                    PasswordAgeDays = if ($gmsa.PasswordLastSet) { [int]((Get-Date) - $gmsa.PasswordLastSet).TotalDays } else { 'unknown' }
                    Encryption      = '(gMSA managed)'
                    NeverExpires    = $false
                    Enabled         = $gmsa.Enabled
                    Status          = 'OK (gMSA)'
                }
            }
        } catch { }
    }
} catch {
    [pscustomobject]@{ Domain='ERROR'; Status=$_.Exception.Message }
}

$TableFormat = @{
    Encryption   = { param($v,$row) if ("$v" -match 'RC4 only') { 'bad' } elseif ("$v" -match 'default') { 'warn' } else { '' } }
    NeverExpires = { param($v,$row) if ($v -eq $true) { 'warn' } else { '' } }
    Status       = { param($v,$row) if ("$v" -match '^OK') { 'ok' } elseif ("$v" -match 'WEAK|STALE') { 'bad' } elseif ("$v" -match 'NEVER|DISABLED') { 'warn' } else { '' } }
}
