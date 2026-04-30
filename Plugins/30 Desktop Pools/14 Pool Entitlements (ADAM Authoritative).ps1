# Start of Settings
# Override the LDAPS port (default 636) for labs that only run LDAP/389.
$AdamPort = 636
# Set to $true to bind on LDAP/389 instead of LDAPS/636 (lab-only, plaintext bind).
$UseLdap = $false
# Default DN base for the Horizon ADAM directory. Customer-tunable but the
# value below matches the Horizon installer default.
$AdamBaseDN = 'OU=Applications,DC=vdi,DC=vmware,DC=int'
# End of Settings

$Title          = 'Pool Entitlements (ADAM Authoritative)'
$Header         = 'Per-pool entitlements pulled from each Connection Server local AD-LDS'
$Comments       = @"
Authoritative pool/application entitlement listing read directly from each Connection Server's local ADAM (AD-LDS) instance via read-only LDAPS bind. Used as the canonical source when REST `/v1/entitlements` and `/v2/entitlements` 404 (Horizon 8.6 default).

Each row is one user/group entitlement to one Desktop or Application pool.

Requirements:
- 'Set ADAM credential...' on the Horizon tab populated with a credential profile authorized for read-only bind on the ADAM instance.
- TCP 636/LDAPS (or 389/LDAP if `UseLdap=$true` in plugin settings) reachable from the runner to each CS FQDN.

Read-only contract: the underlying HorizonADAM module performs only Search operations; no writes are issued.
"@
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '30 Desktop Pools'
$Severity       = 'Info'
$Recommendation = 'If a pool you expected to be entitled is missing here, the entitlement object is absent in ADAM - check Horizon Console -> Inventory -> Pools -> Entitlements for the pool. Empty (no member DN) entitlements indicate orphaned objects that should be removed.'

# Source list of CS FQDNs - identical priority order to the WinRM-fallback
# CS Inventory plugin so the operator only configures it once.
$fqdns = New-Object System.Collections.Generic.HashSet[string]
if ($Global:HVConnectedFqdnList) {
    foreach ($f in @($Global:HVConnectedFqdnList)) { $t=([string]$f).Trim(); if ($t) { [void]$fqdns.Add($t.ToLower()) } }
}
if ($fqdns.Count -eq 0 -and $Global:HVServer) {
    foreach ($f in @($Global:HVServer -split '[,;\s]+')) { $t=([string]$f).Trim(); if ($t) { [void]$fqdns.Add($t.ToLower()) } }
}
if ($fqdns.Count -eq 0 -and (Get-HVRestSession)) {
    $sess = Get-HVRestSession
    if ($sess.Server) { [void]$fqdns.Add(([string]$sess.Server).ToLower()) }
}
if ($fqdns.Count -eq 0) {
    [pscustomobject]@{
        ConnectionServer = '(none)'
        EntitlementCN    = ''
        DisplayName      = ''
        ResourceType     = ''
        ResourceDN       = ''
        MemberDN         = ''
        Note             = 'No Horizon CS FQDN list available. Connect on the Horizon tab and re-run.'
    }
    return
}

if (-not $Global:HVAdamCredential) {
    [pscustomobject]@{
        ConnectionServer = ($fqdns | Select-Object -First 1)
        EntitlementCN    = ''
        DisplayName      = ''
        ResourceType     = ''
        ResourceDN       = ''
        MemberDN         = ''
        Note             = "No ADAM credential set on the Horizon tab. Click 'Set ADAM credential...' and pick a credential profile authorized for read-only LDAPS bind. Falling back to REST + SOAP entitlement sources for now."
    }
    return
}

if (-not (Get-Command -Name 'Get-HVAdamPoolEntitlement' -ErrorAction SilentlyContinue)) {
    [pscustomobject]@{
        ConnectionServer = ($fqdns | Select-Object -First 1)
        EntitlementCN    = '(plugin error)'
        DisplayName      = ''
        ResourceType     = ''
        ResourceDN       = ''
        MemberDN         = ''
        Note             = 'HorizonADAM module not loaded; cannot read AD-LDS. Verify Modules\HorizonADAM.psm1 ships with this build.'
    }
    return
}

$port = [int]$AdamPort
$useLdap = [bool]$UseLdap
$rows = New-Object System.Collections.ArrayList

foreach ($srv in $fqdns) {
    # Per-CS connection test first so we emit a clean diagnostic row when
    # the bind fails instead of a generic "AD-LDS error" toast 30 seconds
    # into the LDAP search.
    $probe = Test-HVAdamConnection -Server $srv -Credential $Global:HVAdamCredential -Port $port -LdapInsteadOfLdaps:$useLdap
    if (-not $probe.Connected) {
        [void]$rows.Add([pscustomobject]@{
            ConnectionServer = $srv
            EntitlementCN    = '(bind failed)'
            DisplayName      = ''
            ResourceType     = ''
            ResourceDN       = ''
            MemberDN         = ''
            Note             = "ADAM bind failed: $($probe.Error). Check that the credential has READ on the ADAM instance and that TCP $port is reachable from the runner."
        })
        continue
    }
    try {
        $ent = @(Get-HVAdamPoolEntitlement -Server $srv -Credential $Global:HVAdamCredential -BaseDN $AdamBaseDN -Port $port -LdapInsteadOfLdaps:$useLdap)
    } catch {
        [void]$rows.Add([pscustomobject]@{
            ConnectionServer = $srv
            EntitlementCN    = '(search failed)'
            DisplayName      = ''
            ResourceType     = ''
            ResourceDN       = ''
            MemberDN         = ''
            Note             = "Entitlement search failed: $($_.Exception.Message)"
        })
        continue
    }
    if ($ent.Count -eq 0) {
        [void]$rows.Add([pscustomobject]@{
            ConnectionServer = $srv
            EntitlementCN    = '(no entitlements)'
            DisplayName      = ''
            ResourceType     = ''
            ResourceDN       = ''
            MemberDN         = ''
            Note             = "ADAM bind succeeded but the entitlement search returned 0 objects. Verify the BaseDN ('$AdamBaseDN') matches your installation."
        })
        continue
    }
    foreach ($e in $ent) {
        [void]$rows.Add([pscustomobject]@{
            ConnectionServer = $srv
            EntitlementCN    = $e.EntitlementCN
            DisplayName      = $e.DisplayName
            ResourceType     = $e.ResourceType
            ResourceDN       = $e.ResourceDN
            MemberDN         = $e.MemberDN
            Note             = ''
        })
    }
    # Most replica pods share ADAM data - a single CS query is canonical for
    # the whole pod. Break after the first successful one to avoid 4x rows.
    break
}

$rows.ToArray()

$TableFormat = @{
    EntitlementCN = { param($v,$row) if ("$v" -like '(*' -or "$v" -eq '') { 'warn' } else { '' } }
    MemberDN      = { param($v,$row) if ("$v" -eq '(none)') { 'warn' } else { '' } }
}
