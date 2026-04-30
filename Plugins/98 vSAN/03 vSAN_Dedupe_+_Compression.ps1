# Start of Settings
# End of Settings

$Title          = 'vSAN Dedupe + Compression'
$Header         = 'Dedupe / compression posture'
$Comments       = 'OSA dedupe-and-compression is per-cluster, all-flash only. ESA does compression-only by default.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '98 vSAN'
$Severity       = 'Info'
$Recommendation = 'Validate setting matches the workload. Heavy DB/IO workloads may benefit from compression-only.'

if (-not $Global:VCConnected) { return }
Get-Cluster -ErrorAction SilentlyContinue | Where-Object { $_.VsanEnabled } | ForEach-Object {
    [pscustomobject]@{
        Cluster                  = $_.Name
        DedupeEnabled            = $_.ExtensionData.ConfigurationEx.VsanConfigInfo.DataEfficiencyConfig.DedupEnabled
        CompressionEnabled       = $_.ExtensionData.ConfigurationEx.VsanConfigInfo.DataEfficiencyConfig.CompressionEnabled
    }
}
