# Start of Settings
# End of Settings

$Title          = 'vSAN Witness Host (Stretched / 2-node)'
$Header         = '[count] cluster(s) with witness host'
$Comments       = 'Stretched / 2-node clusters need a witness. If unreachable, the cluster operates degraded.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '98 vSAN'
$Severity       = 'P1'
$Recommendation = 'Verify witness host reachable on TCP/2233. Consider VMware Cloud Witness.'

if (-not $Global:VCConnected) { return }
Get-Cluster -ErrorAction SilentlyContinue | Where-Object { $_.VsanEnabled } | ForEach-Object {
    $w = $_.ExtensionData.ConfigurationEx.VsanConfigInfo.WitnessConfig
    if ($w -and $w.HostId) {
        [pscustomobject]@{ Cluster=$_.Name; WitnessHostId=$w.HostId.Type+':'+$w.HostId.Value; PreferredFaultDomain=$w.PreferredFdName }
    }
}
