# Start of Settings
# End of Settings

$Title          = "Cloud Pod Architecture - Pods"
$Header         = "[count] pod(s) in federation"
$Comments       = "If only one pod is shown and CPA is not initialized, this is a single-pod environment (expected for many SMB deployments)."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "20 Cloud Pod Architecture"
$Severity       = "Info"

$pods = Get-HVPod
if (-not $pods) { return }

foreach ($p in $pods) {
    [pscustomobject]@{
        Name        = $p.name
        Description = $p.description
        Site        = $p.site_name
        LocalPod    = $p.local_pod
        Endpoints   = ($p.endpoints | ForEach-Object { $_.url }) -join '; '
    }
}
