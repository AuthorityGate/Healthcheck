# Start of Settings
# End of Settings

$Title          = 'NSX Segments'
$Header         = '[count] segment(s)'
$Comments       = 'Segments = logical L2 networks. Sprawl can lead to MAC table pressure.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'Info'
$Recommendation = 'Trim segments not bound to any T1 / T0 / VM. Document connect mode.'

if (-not (Get-NSXRestSession)) { return }
$s = Get-NSXSegment
if (-not $s) { return }
foreach ($x in $s) {
    [pscustomobject]@{
        Name             = $x.display_name
        TransportZone    = $x.transport_zone_path
        ConnectivityPath = $x.connectivity_path
        VlanIds          = ($x.vlan_ids -join ', ')
    }
}
