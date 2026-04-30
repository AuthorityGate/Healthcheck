# Start of Settings
# End of Settings

$Title          = 'NSX VPN IPSec'
$Header         = '[count] IPSec session(s)'
$Comments       = 'Site-to-site IPSec for inter-site / cloud DR. Down tunnels are silent failures.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'P2'
$Recommendation = 'Pull tunnel status from /api/v1/vpn/ipsec/sessions/{id}/status; restart sessions if down.'

if (-not (Get-NSXRestSession)) { return }
try { $v = Get-NSXVpnIpsec } catch { return }
if (-not $v) { return }
foreach ($x in $v) {
    [pscustomobject]@{
        Name      = $x.display_name
        Enabled   = $x.enabled
        TunnelProfile = $x.tunnel_profile_path
    }
}
