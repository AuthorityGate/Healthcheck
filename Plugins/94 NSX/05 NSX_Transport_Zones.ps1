# Start of Settings
# End of Settings

$Title          = 'NSX Transport Zones'
$Header         = '[count] transport zone(s)'
$Comments       = 'Overlay vs VLAN. Verify each TZ is mapped to the correct hosts via Uplink Profile.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'Info'
$Recommendation = 'Pin TZ <-> Uplink Profile <-> N-VDS lineage. Document for each cluster.'

if (-not (Get-NSXRestSession)) { return }
$tz = Get-NSXTransportZone
if (-not $tz) { return }
foreach ($z in $tz) {
    [pscustomobject]@{
        Name           = $z.display_name
        Type           = $z.tz_type
        TransportType  = $z.transport_type
        VlanId         = $z.vlan_id
    }
}
