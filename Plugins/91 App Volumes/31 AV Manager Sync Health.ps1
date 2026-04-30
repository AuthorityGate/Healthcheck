# Start of Settings
# End of Settings

$Title          = "App Volumes Manager Sync Health"
$Header         = "[count] sync status entry(s)"
$Comments       = "Sync state across the multi-manager deployment: package sync, manager-to-manager sync, AD sync, directory health. Out-of-sync managers can serve stale package metadata + cause attachment regressions."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "91 App Volumes"
$Severity       = "P2"
$Recommendation = "Sync gaps over 1h indicate manager isolation - check time skew, certificate trust, network reachability between managers."

if (-not (Get-AVRestSession)) { return }
$rows = @()
try {
    $pkg = Get-AVPackageSyncStatus
    if ($pkg) { foreach ($p in @($pkg)) { $rows += [pscustomobject]@{ Component='Package'; Manager=$p.manager_name; State=$p.sync_state; LastSync=$p.last_sync_at; LagMinutes=$p.sync_lag_minutes } } }
} catch { }
try {
    $mgr = Get-AVManagerSyncStatus
    if ($mgr) { foreach ($m in @($mgr)) { $rows += [pscustomobject]@{ Component='Manager'; Manager=$m.manager_name; State=$m.sync_state; LastSync=$m.last_sync_at; LagMinutes=$m.sync_lag_minutes } } }
} catch { }
try {
    $ad = Get-AVAdSyncStatus
    if ($ad) { foreach ($a in @($ad)) { $rows += [pscustomobject]@{ Component='ActiveDirectory'; Manager=$a.domain; State=$a.sync_state; LastSync=$a.last_sync_at; LagMinutes=$a.sync_lag_minutes } } }
} catch { }
if (-not $rows -or $rows.Count -eq 0) {
    [pscustomobject]@{ Note = 'No sync-status data returned. Single-manager deployment or older AppVol build.' }
    return
}
$rows

$TableFormat = @{
    State      = { param($v,$row) if ($v -match 'in_sync|ok') { 'ok' } elseif ($v -match 'lagging|warn') { 'warn' } elseif ($v) { 'bad' } else { '' } }
    LagMinutes = { param($v,$row) if ([int]"$v" -gt 60) { 'bad' } elseif ([int]"$v" -gt 15) { 'warn' } else { '' } }
}
