# Start of Settings
# Threshold scale 1 (apply only top priority recommendations) -> 5 (apply all).
# 3 is vSphere default and balances stability vs load-balance aggressiveness.
$RecommendedThreshold = 3
# End of Settings

$Title          = 'DRS Migration Threshold'
$Header         = 'Per-cluster DRS migration threshold (default = 3)'
$Comments       = 'DRS migration threshold drives how aggressively DRS rebalances. 1 = ignore everything but priority-1; 5 = apply every recommendation. 3 is vSphere default and recommended for most production clusters. Lists every DRS-enabled cluster so operators can confirm settings.'
$Display        = 'Table'
$Author         = 'AuthorityGate'
$PluginVersion  = 1.1
$PluginCategory = '95 vSphere Backing Infra'
$Severity       = 'P3'
$Recommendation = 'Cluster -> Configure -> vSphere DRS -> Edit -> Migration Threshold = level 3 unless workload tells you otherwise.'

if (-not $Global:VCConnected) { return }

$clusters = @(Get-Cluster -ErrorAction SilentlyContinue | Where-Object { $_.DrsEnabled } | Sort-Object Name)
if ($clusters.Count -eq 0) {
    [pscustomobject]@{ Note = 'No DRS-enabled clusters returned. Either DRS is disabled fleetwide or vCenter is not connected.' }
    return
}

foreach ($c in $clusters) {
    $thr = [int]$c.DrsMigrationThreshold
    [pscustomobject]@{
        Cluster            = $c.Name
        DrsAutomation      = "$($c.DrsAutomationLevel)"
        MigrationThreshold = $thr
        Recommended        = $RecommendedThreshold
        Note               = if ($thr -eq $RecommendedThreshold) { 'Default (balanced)' }
                             elseif ($thr -lt $RecommendedThreshold) { "Conservative ($thr) - DRS will migrate less" }
                             else { "Aggressive ($thr) - DRS will migrate more" }
        Status             = if ($thr -eq $RecommendedThreshold) { 'OK' } else { 'NON-DEFAULT' }
    }
}

$TableFormat = @{
    MigrationThreshold = { param($v,$row) if ([int]"$v" -ne 3) { 'warn' } else { '' } }
    Status             = { param($v,$row) if ("$v" -eq 'OK') { 'ok' } else { 'warn' } }
}
