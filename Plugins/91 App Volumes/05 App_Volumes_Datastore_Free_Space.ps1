# Start of Settings
# End of Settings

$Title          = 'App Volumes Datastore Free Space'
$Header         = '[count] datastore(s) below 15% free'
$Comments       = 'AppStacks + Writables consume datastore steadily; below 15% free, attachment fails for new volumes.'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P1'
$Recommendation = 'Reclaim space (delete unused versions, expire writables) or expand the datastore.'

if (-not (Get-AVRestSession)) { return }
$ds = Get-AVDatastore
if (-not $ds) { return }
foreach ($d in $ds.datastores) {
    if ($d.capacity -gt 0) {
        $pct = [math]::Round(($d.free_space / $d.capacity) * 100, 1)
        if ($pct -lt 15) {
            [pscustomobject]@{
                Datastore = $d.name; CapacityGB = [math]::Round($d.capacity / 1GB, 1)
                FreeGB = [math]::Round($d.free_space / 1GB, 1); FreePct = $pct
            }
        }
    }
}
