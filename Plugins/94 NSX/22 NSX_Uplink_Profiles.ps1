# Start of Settings
# End of Settings

$Title          = 'NSX Uplink Profiles'
$Header         = '[count] uplink profile(s)'
$Comments       = 'Uplink profiles set MTU, teaming, transport VLAN. Mismatch with vDS = broken overlay.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'P2'
$Recommendation = 'Confirm transport VLAN and MTU >= 1700.'

if (-not (Get-NSXRestSession)) { return }
try { $u = Invoke-NSXRest -Path '/api/v1/host-switch-profiles?host_switch_profile_type=UplinkHostSwitchProfile' } catch { return }
if (-not $u) { return }
foreach ($x in $u) {
    [pscustomobject]@{ Name=$x.display_name; Mtu=$x.mtu; TransportVlan=$x.transport_vlan; TeamingPolicy=$x.teaming.policy }
}
