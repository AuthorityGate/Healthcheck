# Start of Settings
# End of Settings

$Title          = 'vCenter HA (vCHA) Cluster Status'
$Header         = '[count] vCenter Server Appliance HA cluster row(s)'
$Comments       = 'vCenter HA (vCHA) is the active/passive/witness three-node clustering for vCenter Server Appliance itself. When deployed, the active node should be Primary, replication healthy, and failover tested annually. Most environments do not have vCHA.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '99 vSphere Lifecycle'
$Severity       = 'P3'
$Recommendation = 'If vCHA deployed: verify health via VAMI (port 5480) -> vCenter HA tab. If not deployed: confirm acceptable RTO/RPO for vCenter (file-based backup is the alternative)'

if (-not $Global:VCConnected) { return }

# vCHA status is exposed via /api/vcenter/vcha/cluster (REST). PowerCLI does not
# wrap this consistently across versions; emit a manual-check pointer.
$servers = @($global:DefaultVIServers | Where-Object { $_ -and $_.IsConnected })
if ($servers.Count -eq 0 -and $Global:VCServer) { $servers = @([pscustomobject]@{ Name = $Global:VCServer }) }
foreach ($srv in $servers) {
    [pscustomobject]@{
        vCenter      = $srv.Name
        Status       = 'Manual check required'
        ManualCheck  = "GET https://$($srv.Name)/api/vcenter/vcha/cluster (auth required) -> .runtime.health field"
        Recommendation = 'If vCHA deployed: verify .runtime.health=HEALTHY. Failover-test annually.'
    }
}
