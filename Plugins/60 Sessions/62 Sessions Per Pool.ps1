# Start of Settings
# End of Settings

$Title          = 'Active Sessions per Pool'
$Header         = 'Sessions distributed by pool'
$Comments       = 'Spotting a pool consuming a disproportionate share of CCU is the first step in capacity planning.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '60 Sessions'
$Severity       = 'Info'
$Recommendation = 'Right-size pools: split high-CCU pools, consolidate low-utilization ones.'

if (-not (Get-HVRestSession)) { return }
$s = Get-HVSession
if (-not $s) { return }
$s | Group-Object desktop_pool_name | Sort-Object Count -Descending | ForEach-Object {
    [pscustomobject]@{ Pool=$_.Name; ActiveSessions=$_.Count }
}

