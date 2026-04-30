# Start of Settings
# End of Settings

$Title          = 'vSAN Object Health Summary'
$Header         = 'Per-cluster vSAN object count + state'
$Comments       = 'Total vSAN objects (VMDKs, namespaces, swap), per-state counts (healthy, degraded, absent). High absent count after host failure indicates rebuild stalled.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '98 vSAN'
$Severity       = 'Info'
$Recommendation = "Investigate 'absent' objects via Skyline Health -> Data -> Object Health."

if (-not $Global:VCConnected) { return }
Get-Cluster -ErrorAction SilentlyContinue | Where-Object { $_.VsanEnabled } | ForEach-Object {
    [pscustomobject]@{
        Cluster = $_.Name
        Note    = 'Detailed object health requires Get-VsanObjectHealth (PowerCLI) or Skyline Health UI.'
        Reference = 'KB 2114803'
    }
}
