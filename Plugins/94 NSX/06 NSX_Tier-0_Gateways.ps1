# Start of Settings
# End of Settings

$Title          = 'NSX Tier-0 Gateways'
$Header         = '[count] Tier-0 gateway(s)'
$Comments       = 'T0 = north-south boundary. HA mode (active-active vs active-standby) influences edge sizing.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'Info'
$Recommendation = 'Confirm HA mode matches the design. Active-Active for ECMP, Active-Standby for stateful services.'

if (-not (Get-NSXRestSession)) { return }
$t = Get-NSXTier0
if (-not $t) { return }
foreach ($x in $t) {
    [pscustomobject]@{
        Name         = $x.display_name
        HaMode       = $x.ha_mode
        FailoverMode = $x.failover_mode
        Transit      = $x.transit_subnets -join ', '
    }
}
