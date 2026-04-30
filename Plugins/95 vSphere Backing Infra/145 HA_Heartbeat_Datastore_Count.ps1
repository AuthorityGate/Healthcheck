# Start of Settings
$MinHeartbeatDatastores = 2
# End of Settings

$Title          = 'HA Heartbeat Datastore Count'
$Header         = '[count] cluster(s) with fewer than ' + $MinHeartbeatDatastores + ' heartbeat datastores'
$Comments       = "HA uses datastore heartbeating as a tie-breaker when management network heartbeat fails. With < 2 heartbeat datastores, network partitions can cause split-brain or unnecessary failovers."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P3'
$Recommendation = "Cluster -> Configure -> vSphere Availability -> Heartbeat Datastores -> let vSphere automatically select OR pin >= 2 datastores. Avoid using a single shared datastore for heartbeat."

if (-not $Global:VCConnected) { return }

foreach ($c in (Get-Cluster -ErrorAction SilentlyContinue | Where-Object { $_.HAEnabled } | Sort-Object Name)) {
    try {
        $cv = ($c | Get-View)
        $hbCfg = $cv.Configuration.DasConfig.HeartbeatDatastore
        $count = if ($hbCfg) { $hbCfg.Count } else { 0 }
        $policy = $cv.Configuration.DasConfig.HBDatastoreCandidatePolicy
        if ($count -lt $MinHeartbeatDatastores) {
            [pscustomobject]@{
                Cluster                     = $c.Name
                HeartbeatDatastoreCount     = $count
                CandidatePolicy             = $policy
                Recommended                 = ">= $MinHeartbeatDatastores"
            }
        }
    } catch { }
}
