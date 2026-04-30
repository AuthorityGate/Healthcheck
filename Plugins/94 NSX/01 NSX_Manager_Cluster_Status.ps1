# Start of Settings
# End of Settings

$Title          = 'NSX Manager Cluster Status'
$Header         = 'NSX Manager management-cluster health'
$Comments       = "Reference: 'NSX Manager Cluster Stability' (NSX docs). 3-node cluster preferred for HA."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '94 NSX'
$Severity       = 'P1'
$Recommendation = "If status != STABLE, drain alarms, check disk space, restart 'manager' service on the unhealthy node."

if (-not (Get-NSXRestSession)) { return }
$s = Get-NSXClusterStatus
if (-not $s) { return }
[pscustomobject]@{
    OverallStatus       = $s.mgmt_cluster_status.status
    ControlClusterStatus = $s.control_cluster_status.status
    ControlPlaneVersion  = $s.control_cluster_status.version
}
