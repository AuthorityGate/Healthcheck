# Start of Settings
# End of Settings

$Title          = 'App Volumes Writable Volumes'
$Header         = '[count] writable volume(s)'
$Comments       = 'Inventory of all writable volumes (per-user persistent data layer).'
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = '91 App Volumes'
$Severity       = 'Info'
$Recommendation = 'Track size growth; archive abandoned volumes (last attach > 90d).'

if (-not (Get-AVRestSession)) { return }
$w = Get-AVWritable
if (-not $w) { return }
foreach ($v in $w.writables) {
    [pscustomobject]@{
        Name         = $v.name
        Owner        = $v.owner_name
        SizeGB       = [math]::Round($v.size_mb / 1024, 1)
        UsedPct      = $v.used_percent
        State        = $v.state
        LastAttached = $v.last_online_at
    }
}
