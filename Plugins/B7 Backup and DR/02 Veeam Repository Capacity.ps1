# Start of Settings
# End of Settings

$Title          = "Veeam Repository Capacity"
$Header         = "[count] Veeam backup repository(ies)"
$Comments       = "Per-repo total / used / free + percent used. Out-of-space repositories silently kill backup jobs. Plan capacity expansion or retention tightening at >85% used."
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "B7 Backup and DR"
$Severity       = "P1"
$Recommendation = "Repos > 85% full need immediate attention. Options: extend repository, add scale-out extent, tighten retention, or migrate older points to cloud / tape via SOBR."

if (-not (Get-VeeamRestSession)) { return }
$repos = Get-VeeamRepository
$states = Get-VeeamRepositoryState
if (-not $repos -or -not $repos.data) {
    [pscustomobject]@{ Note = 'No repositories returned.' }
    return
}
$stateMap = @{}
if ($states -and $states.data) { foreach ($st in $states.data) { $stateMap[$st.id] = $st } }

foreach ($r in $repos.data) {
    $st = $stateMap[$r.id]
    $totalGB = if ($st -and $st.capacityGB) { [math]::Round([double]$st.capacityGB, 1) } else { '' }
    $freeGB  = if ($st -and $st.freeGB) { [math]::Round([double]$st.freeGB, 1) } else { '' }
    $pct = if ($totalGB -and $freeGB -ne $null -and [double]$totalGB -gt 0) { [math]::Round((([double]$totalGB - [double]$freeGB) / [double]$totalGB) * 100, 1) } else { '' }
    [pscustomobject]@{
        Name      = $r.name
        Type      = $r.type
        Path      = $r.path
        TotalGB   = $totalGB
        FreeGB    = $freeGB
        PctFull   = $pct
        Encrypted = [bool]$r.encryptionEnabled
        Description = $r.description
    }
}

$TableFormat = @{
    PctFull = { param($v,$row) if ([double]"$v" -gt 90) { 'bad' } elseif ([double]"$v" -gt 80) { 'warn' } else { '' } }
}
