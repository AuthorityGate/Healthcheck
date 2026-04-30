# Start of Settings
# End of Settings

$Title          = 'AD Kerberos Delegation Audit'
$Header         = 'Every account configured for Kerberos delegation (any flavor)'
$Comments       = 'Unconstrained delegation is a critical security finding: any account that authenticates to a server with TrustedForDelegation can have its TGT extracted and used elsewhere. Constrained delegation (allowed-to-delegate-to) is safer; resource-based constrained (RBCD) is preferred. Lists every delegation configuration in the forest.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = 'B3 Active Directory'
$Severity       = 'P1'
$Recommendation = "Eliminate Unconstrained delegation (TrustedForDelegation = True). Migrate to Constrained or Resource-Based Constrained Delegation. Mark privileged accounts as 'Account is sensitive and cannot be delegated' (NOT_DELEGATED bit)."

if (-not (Test-Path Variable:Global:ADForestFqdn) -or -not $Global:ADForestFqdn) { return }
try { Import-Module ActiveDirectory -ErrorAction Stop } catch { return }

$adArgs = @{ Server = $(if ($Global:ADServerFqdn) { $Global:ADServerFqdn } else { $Global:ADForestFqdn }) }
if (Test-Path Variable:Global:ADCredential) { $adArgs.Credential = $Global:ADCredential }

try {
    $forest = Get-ADForest -Identity $Global:ADForestFqdn @adArgs -ErrorAction Stop
    foreach ($d in $forest.Domains) {
        # Unconstrained: userAccountControl has TRUSTED_FOR_DELEGATION bit (524288 / 0x80000)
        $u = @{ Filter='TrustedForDelegation -eq $true'; Properties=@('TrustedForDelegation','TrustedToAuthForDelegation','servicePrincipalName','msDS-AllowedToDelegateTo','msDS-AllowedToActOnBehalfOfOtherIdentity','Enabled'); Server=$d; ErrorAction='SilentlyContinue' }
        if (Test-Path Variable:Global:ADCredential) { $u.Credential = $Global:ADCredential }
        $unconstUsers = @(Get-ADUser @u)
        $unconstComps = @()
        try {
            $c = $u.Clone(); $c.Filter='TrustedForDelegation -eq $true'
            $unconstComps = @(Get-ADComputer @c -Properties TrustedForDelegation,TrustedToAuthForDelegation,'msDS-AllowedToDelegateTo','msDS-AllowedToActOnBehalfOfOtherIdentity',Enabled)
        } catch { }

        foreach ($acc in $unconstUsers + $unconstComps) {
            [pscustomobject]@{
                Domain         = $d
                Class          = if ($acc.ObjectClass -eq 'user') { 'User' } else { 'Computer' }
                Account        = $acc.SamAccountName
                DelegationType = 'UNCONSTRAINED (highest risk)'
                Targets        = '(any)'
                Enabled        = $acc.Enabled
                Status         = 'BAD (unconstrained)'
            }
        }

        # Constrained / RBCD: msDS-AllowedToDelegateTo or msDS-AllowedToActOnBehalfOfOtherIdentity populated
        try {
            $c2 = @{ Filter='msDS-AllowedToDelegateTo -like "*"'; Properties=@('msDS-AllowedToDelegateTo','TrustedToAuthForDelegation','Enabled'); Server=$d; ErrorAction='SilentlyContinue' }
            if (Test-Path Variable:Global:ADCredential) { $c2.Credential = $Global:ADCredential }
            $constU = @(Get-ADUser @c2)
            $constC = @(Get-ADComputer @c2)
            foreach ($acc in $constU + $constC) {
                $deleg = @($acc.'msDS-AllowedToDelegateTo')
                $type = if ($acc.TrustedToAuthForDelegation) { 'CONSTRAINED w/Protocol Transition (S4U2Self)' } else { 'CONSTRAINED' }
                [pscustomobject]@{
                    Domain         = $d
                    Class          = if ($acc.ObjectClass -eq 'user') { 'User' } else { 'Computer' }
                    Account        = $acc.SamAccountName
                    DelegationType = $type
                    Targets        = ($deleg -join '; ')
                    Enabled        = $acc.Enabled
                    Status         = if ($acc.TrustedToAuthForDelegation) { 'WARN (protocol transition)' } else { 'OK (constrained)' }
                }
            }
        } catch { }

        try {
            $c3 = @{ Filter='msDS-AllowedToActOnBehalfOfOtherIdentity -like "*"'; Properties=@('msDS-AllowedToActOnBehalfOfOtherIdentity','Enabled'); Server=$d; ErrorAction='SilentlyContinue' }
            if (Test-Path Variable:Global:ADCredential) { $c3.Credential = $Global:ADCredential }
            $rbcdU = @(Get-ADUser @c3)
            $rbcdC = @(Get-ADComputer @c3)
            foreach ($acc in $rbcdU + $rbcdC) {
                [pscustomobject]@{
                    Domain         = $d
                    Class          = if ($acc.ObjectClass -eq 'user') { 'User' } else { 'Computer' }
                    Account        = $acc.SamAccountName
                    DelegationType = 'RBCD (Resource-Based Constrained)'
                    Targets        = '(see msDS-AllowedToActOnBehalfOfOtherIdentity)'
                    Enabled        = $acc.Enabled
                    Status         = 'OK (RBCD - preferred)'
                }
            }
        } catch { }
    }
} catch {
    [pscustomobject]@{ Domain='ERROR'; Status=$_.Exception.Message }
}

$TableFormat = @{
    DelegationType = { param($v,$row) if ("$v" -match 'UNCONSTRAINED') { 'bad' } elseif ("$v" -match 'Protocol Transition') { 'warn' } else { '' } }
    Status         = { param($v,$row) if ("$v" -match '^OK') { 'ok' } elseif ("$v" -match 'BAD') { 'bad' } elseif ("$v" -match 'WARN') { 'warn' } else { '' } }
}
