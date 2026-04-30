# Start of Settings
$LookbackDays = 30
$IntervalSecs = 1800
# End of Settings

$Title          = "Nutanix Storage Container - 30 Day Capacity Peak"
$Header         = "[count] storage container(s) profiled (current + peak fill)"
$Comments       = @"
Per-container reserved + advertised capacity, current logical + physical usage, and 30-day peak utilization with the timestamp it occurred. Equivalent of vSphere Datastore_30Day_Peak. RF, compression, dedup, and erasure coding flags shown for capacity-planning context.
"@
$Display        = "Table"
$Author         = "AuthorityGate"
$PluginVersion  = 1.0
$PluginCategory = "97 Nutanix Prism"
$Severity       = "Info"
$Recommendation = "Containers with 30-day peak > 85% fill warrant capacity expansion or workload migration. RF=2 storage at > 70% is risky during host rebuilds (data resilience window grows). Verify dedup + compression settings match the workload profile (VDI = on; databases = off)."

if (-not (Get-NTNXRestSession)) { return }
$containers = @(Get-NTNXStorageContainer)
if (-not $containers) {
    [pscustomobject]@{ Note='No storage containers visible to this account.' }
    return
}

foreach ($sc in $containers) {
    if (-not $sc -or -not $sc.uuid) { continue }
    $peakPct = $null; $peakAt = $null; $note = ''
    $advCapBytes  = if ($sc.advertised_capacity_bytes) { [double]$sc.advertised_capacity_bytes } else { 0 }
    $usedBytes    = if ($sc.usage_stats -and $sc.usage_stats.'storage.usage_bytes') { [double]$sc.usage_stats.'storage.usage_bytes' } else { 0 }
    $freeBytes    = $advCapBytes - $usedBytes
    $pctNow       = if ($advCapBytes -gt 0) { [math]::Round(($usedBytes / $advCapBytes) * 100, 1) } else { '' }

    try {
        $stat = Get-NTNXStorageStat -Uuid $sc.uuid -Metric 'storage.usage_bytes' -LookbackDays $LookbackDays -IntervalSecs $IntervalSecs
        if ($stat -and $stat.stats_specific_responses -and $advCapBytes -gt 0) {
            $samples = @($stat.stats_specific_responses[0].values)
            if ($samples.Count -gt 0) {
                $top = $samples | Sort-Object value -Descending | Select-Object -First 1
                $peakPct = [math]::Round(([double]$top.value / $advCapBytes) * 100, 1)
                $peakAt  = [datetimeoffset]::FromUnixTimeMilliseconds([long]$top.timestamp_in_usecs / 1000).ToLocalTime().ToString('yyyy-MM-dd HH:mm zzz')
            }
        }
        if (-not $peakPct) { $note = 'No usage samples in window or capacity unknown.' }
    } catch { $note = "Stat query failed: $($_.Exception.Message)" }

    [pscustomobject]@{
        Container       = $sc.name
        Cluster         = if ($sc.cluster_reference) { $sc.cluster_reference.name } else { '' }
        AdvertisedGB    = if ($advCapBytes -gt 0) { [math]::Round($advCapBytes / 1GB, 1) } else { '' }
        ReservedGB      = if ($sc.replication_factor) { [math]::Round([double]$sc.reserved_capacity_bytes / 1GB, 1) } else { '' }
        UsedGBNow       = if ($usedBytes -gt 0) { [math]::Round($usedBytes / 1GB, 1) } else { '' }
        FreeGBNow       = if ($advCapBytes -gt 0) { [math]::Round($freeBytes / 1GB, 1) } else { '' }
        PctFullNow      = $pctNow
        PctFullPeak30d  = $peakPct
        PeakAt          = $peakAt
        RF              = $sc.replication_factor
        Compression     = [bool]$sc.compression_enabled
        Dedup           = $sc.on_disk_dedup
        ErasureCoding   = [bool]$sc.erasure_code
        Note            = $note
    }
}

$TableFormat = @{
    PctFullNow     = { param($v,$row) if ([double]"$v" -ge 90) { 'bad' } elseif ([double]"$v" -ge 80) { 'warn' } else { '' } }
    PctFullPeak30d = { param($v,$row) if ([double]"$v" -ge 95) { 'bad' } elseif ([double]"$v" -ge 85) { 'warn' } else { '' } }
    RF             = { param($v,$row) if ([int]"$v" -lt 2) { 'bad' } elseif ([int]"$v" -eq 2) { 'warn' } else { 'ok' } }
}
