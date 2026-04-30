# Start of Settings
# End of Settings

$Title          = 'Pool Network Mapping'
$Header         = 'Per-pool network label assignment'
$Comments       = 'Pools using non-existent VLAN / port-group labels (renamed dvPort, deleted std switch) silently fail to clone.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '30 Desktop Pools'
$Severity       = 'P3'
$Recommendation = 'Pool -> vCenter Settings -> verify the network label still exists in vCenter. Pin the dvPort by ID for stability.'

if (-not (Get-HVRestSession)) { return }
$pools = Get-HVDesktopPool
if (-not $pools) { return }
foreach ($p in $pools) {
    $nets = @()
    foreach ($prop in 'provisioning_settings','instant_clone_engine_provisioning_settings') {
        if ($p.$prop -and $p.$prop.networking) {
            foreach ($n in $p.$prop.networking) { $nets += $n.network_id }
        }
    }
    if ($nets.Count -gt 0) {
        [pscustomobject]@{ Pool=$p.name; Networks=($nets -join ', ') }
    }
}

