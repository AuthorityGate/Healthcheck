# Start of Settings
# End of Settings

$Title          = 'ESXi Active Directory Authentication'
$Header         = '[count] host(s) NOT joined to Active Directory'
$Comments       = "Hosts not joined to AD fall back to shared 'root' password authentication. AD-joined hosts inherit account lockout, password complexity, and per-admin attribution. VMware vSCG: Configure-ESXi-Use-AD."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P2'
$Recommendation = "Configure host AD via vSphere Authentication Service: Host -> Configure -> System -> Authentication Services -> Join Domain. Add an AD group to the 'ESX Admins' role for per-admin attribution."

if (-not $Global:VCConnected) { return }

foreach ($h in (Get-VMHost -ErrorAction SilentlyContinue | Sort-Object Name)) {
    try {
        $auth = Get-VMHostAuthentication -VMHost $h -ErrorAction Stop
        if (-not $auth.Domain) {
            [pscustomobject]@{
                Host          = $h.Name
                DomainJoined  = $false
                Domain        = ''
                TrustStatus   = ''
                Note          = 'Falls back to local root authentication only.'
            }
        } else {
            [pscustomobject]@{
                Host          = $h.Name
                DomainJoined  = $true
                Domain        = $auth.Domain
                TrustStatus   = $auth.DomainMembershipStatus
                Note          = if ($auth.DomainMembershipStatus -ne 'Ok') { 'AD trust degraded.' } else { '' }
            }
        }
    } catch { }
}

$TableFormat = @{
    DomainJoined = { param($v,$row) if ($v -ne $true) { 'bad' } else { 'ok' } }
    TrustStatus  = { param($v,$row) if ($v -and $v -ne 'Ok') { 'warn' } else { '' } }
}
