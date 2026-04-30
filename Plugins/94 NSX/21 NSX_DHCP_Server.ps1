# Start of Settings
# End of Settings

$Title          = 'NSX DHCP Server'
$Header         = '[count] DHCP server profile(s)'
$Comments       = 'NSX DHCP / Relay servers for tenant overlays.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'Info'
$Recommendation = 'Audit lease ranges; reduce lease time for desktop VLANs.'

if (-not (Get-NSXRestSession)) { return }
try { $d = Invoke-NSXRest -Path '/policy/api/v1/infra/dhcp-server-configs' } catch { return }
if (-not $d) { return }
foreach ($x in $d) {
    [pscustomobject]@{ Name=$x.display_name; LeaseTime=$x.lease_time; ServerAddresses=($x.server_addresses -join ',') }
}
