# Start of Settings
# End of Settings

$Title          = 'HA VM + Application Monitoring'
$Header         = '[count] cluster(s) without VM monitoring enabled'
$Comments       = "vSphere HA VM Monitoring restarts VMs when their VMware Tools heartbeat stops, even if the host stays up. Application Monitoring extends this to in-guest health (App Awareness API). Both default to Disabled."
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.0
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P3'
$Recommendation = "Cluster -> Configure -> vSphere Availability -> Edit -> Failures and Responses -> 'VM Monitoring' = VM and Application Monitoring (or VM Monitoring Only)."

if (-not $Global:VCConnected) { return }

foreach ($c in (Get-Cluster -ErrorAction SilentlyContinue | Where-Object { $_.HAEnabled } | Sort-Object Name)) {
    try {
        $cv = ($c | Get-View)
        $vmMon = $cv.Configuration.DasConfig.VmMonitoring
        if (-not $vmMon -or $vmMon -eq 'vmMonitoringDisabled') {
            [pscustomobject]@{
                Cluster      = $c.Name
                VMMonitoring = $vmMon
                Recommended  = 'vmMonitoringOnly OR vmAndAppMonitoring'
            }
        }
    } catch { }
}
