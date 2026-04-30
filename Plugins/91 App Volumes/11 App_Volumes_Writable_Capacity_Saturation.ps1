# Start of Settings
# End of Settings

$Title          = 'App Volumes Writable Capacity Saturation'
$Header         = '[count] writable volume(s) above 85% used'
$Comments       = 'Writable volumes that fill cause user-visible app failures (Office cache, profiles).'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'P2'
$Recommendation = "Resize via API or replace by 'expand-and-restore' procedure (KB 2127500 series for AV)."

if (-not (Get-AVRestSession)) { return }
$w = Get-AVWritable
if (-not $w) { return }
foreach ($v in $w.writables) {
    if ($v.used_percent -gt 85) {
        [pscustomobject]@{
            Owner = $v.owner_name; SizeGB = [math]::Round($v.size_mb / 1024, 1); UsedPercent = $v.used_percent; State = $v.state
        }
    }
}
