# Start of Settings
# End of Settings

$Title          = 'App Volumes Machine Inventory'
$Header         = '[count] AV-known machine(s)'
$Comments       = 'Cross-reference with Horizon machine inventory; orphaned AV machine records waste an AD computer account each.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P3'
$Recommendation = "Run 'Sync Machines' periodically or set up the cleanup task in AV console."

if (-not (Get-AVRestSession)) { return }
$m = Get-AVMachine
if (-not $m) { return }
@($m.machines) | Group-Object status | ForEach-Object {
    [pscustomobject]@{ Status = $_.Name; Count = $_.Count }
}
