# Start of Settings
# End of Settings

$Title          = 'NSX Tier-1 Gateways'
$Header         = '[count] Tier-1 gateway(s)'
$Comments       = 'T1 = east-west between tenants. Each tenant typically gets a T1 gateway.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'Info'
$Recommendation = 'Audit T1 inventory; remove unused T1s.'

if (-not (Get-NSXRestSession)) { return }
$t = Get-NSXTier1
if (-not $t) { return }
foreach ($x in $t) {
    [pscustomobject]@{
        Name              = $x.display_name
        EdgeCluster       = $x.edge_cluster_path
        FailoverMode      = $x.failover_mode
        RouteAdvertisement = ($x.route_advertisement_types -join ', ')
    }
}
